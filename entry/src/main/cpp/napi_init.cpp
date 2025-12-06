#include "napi/native_api.h"
#include <assert.h>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>
#include <netinet/in.h>
#include <setjmp.h>

#include "hilog/log.h"
#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3300
#define LOG_TAG "HiSH"

// 用于捕获 QEMU exit 调用的跳转缓冲区
static thread_local jmp_buf qemu_exit_jmp;
static thread_local bool qemu_exit_jmp_set = false;
static thread_local int qemu_exit_code = 0;

// 标识当前线程是否是 QEMU 线程
static thread_local bool is_qemu_thread = false;

// 覆盖 exit 函数
extern "C" void exit(int status) {
    if (is_qemu_thread && qemu_exit_jmp_set) {
        OH_LOG_INFO(LOG_APP, "QEMU called exit(%{public}d), using longjmp to return", status);
        qemu_exit_code = status;
        longjmp(qemu_exit_jmp, 1);
    } else {
        // 调用真正的 exit
        OH_LOG_INFO(LOG_APP, "Normal exit(%{public}d) called", status);
        _exit(status);
    }
}

struct data_buffer {
    char *buf;
    size_t size;
};

int serial_input_fd = -1;
napi_threadsafe_function on_data_callback = nullptr;
napi_threadsafe_function on_shutdown_callback = nullptr;

std::mutex buffer_mtx;
std::string temp_buffer = "";

typedef int (*QemuSystemEntry)(int, const char **);

static QemuSystemEntry getQemuSystemEntry() {

    static QemuSystemEntry qemuSystemEntry = nullptr;

    if (qemuSystemEntry != nullptr) {
        return qemuSystemEntry;
    }

    const char *libQemuPath = "libqemu-system-aarch64.so";

    void *libQemuHandle = dlopen(libQemuPath, RTLD_LAZY);

    if (!libQemuHandle) {
        OH_LOG_INFO(LOG_APP, "Failed to load libqemu.so errno: %{public}d", errno);
    }

    qemuSystemEntry = (QemuSystemEntry)dlsym(libQemuHandle, "qemu_system_entry");
    OH_LOG_INFO(LOG_APP, "libqemu.so, handle: 0x%{public}p, entry: 0x%{public}p", libQemuHandle, qemuSystemEntry);

    return qemuSystemEntry;
}

static void call_on_data_callback(napi_env env, napi_value js_callback, void *context, void *data) {

    data_buffer *buffer = static_cast<data_buffer *>(data);

    napi_value ab;
    char *input;
    napi_create_arraybuffer(env, buffer->size, (void **)&input, &ab);
    memcpy(input, buffer->buf, buffer->size);

    napi_value global;
    napi_get_global(env, &global);

    napi_value result;
    napi_value args[1] = {ab};
    napi_call_function(env, global, js_callback, 1, args, &result);

    delete[] buffer->buf;
    delete buffer;
}

static void call_on_shutdown_callback(napi_env env, napi_value js_callback, void *context, void *data) {

    napi_value global;
    napi_get_global(env, &global);

    napi_call_function(env, global, js_callback, 0, nullptr, nullptr);
}

std::string convert_to_hex(const uint8_t *buffer, int r) {
    std::string hex;
    for (int i = 0; i < r; i++) {
        if (buffer[i] >= 127 || buffer[i] < 32) {
            char temp[8];
            snprintf(temp, sizeof(temp), "\\x%02x", buffer[i]);
            hex += temp;
        } else if (buffer[i] == '\'' || buffer[i] == '\"' || buffer[i] == '\\') {
            char temp[8];
            snprintf(temp, sizeof(temp), "\\%c", buffer[i]);
            hex += temp;
        } else {
            hex += (char)buffer[i];
        }
    }
    return hex;
}

void send_data_to_callback(const std::string &hex, napi_threadsafe_function callback) {
    data_buffer *pbuf = new data_buffer{.buf = new char[hex.length()], .size = (size_t)hex.length()};
    memcpy(pbuf->buf, &hex[0], hex.length());
    napi_call_threadsafe_function(callback, pbuf, napi_tsfn_nonblocking);
}

void on_serial_data_received(const std::string &hex) {
    if (hex.length() > 0) {
        std::lock_guard<std::mutex> lk(buffer_mtx);
        if (on_data_callback != nullptr) {
            send_data_to_callback(hex, on_data_callback);
        } else {
            temp_buffer.append(hex);
        }
    }
}

void serial_output_worker(const char *unix_socket_path) {

    while (true) {
        int acc = access(unix_socket_path, F_OK);
        if (acc == 0) {
            break;
        }
        OH_LOG_INFO(LOG_APP, "serial unix socket not exist: %{public}s", unix_socket_path);
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }

    OH_LOG_INFO(LOG_APP, "serial unix socket found: %{public}s", unix_socket_path);

    struct sockaddr_un server_addr;
    int client_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (client_fd == -1) {
        OH_LOG_INFO(LOG_APP, "Failed to create unix socket: %{public}d", errno);
        return;
    }

    // Connect to server
    memset(&server_addr, 0, sizeof(struct sockaddr_un));
    server_addr.sun_family = AF_UNIX;
    strncpy(server_addr.sun_path, unix_socket_path, sizeof(server_addr.sun_path) - 1);

    if (connect(client_fd, (struct sockaddr *)&server_addr, sizeof(struct sockaddr_un)) == -1) {
        OH_LOG_INFO(LOG_APP, "Failed to connect to unix socket: %{public}d", errno);
        return;
    }

    serial_input_fd = client_fd;

    OH_LOG_INFO(LOG_APP, "Connected to unix socket: %{public}d", serial_input_fd);

    while (true) {

        bool broken = false;

        struct pollfd fds[2];
        fds[0].fd = client_fd;
        fds[0].events = POLLIN;
        int res = poll(fds, 1, 100);

        uint8_t buffer[1024];
        for (int i = 0; i < res; i += 1) {
            int fd = fds[i].fd;
            ssize_t r = read(fd, buffer, sizeof(buffer) - 1);
            if (r > 0) {
                // pretty print
                auto hex = convert_to_hex(buffer, r);
                //  call callback registered by ArkTS
                on_serial_data_received(hex);
                OH_LOG_INFO(LOG_APP, "Received, data: %{public}s", hex.c_str());
            } else if (r < 0) {
                OH_LOG_INFO(LOG_APP, "Program exited, %{public}ld %{public}d", r, errno);
                broken = true;
            }
        }

        if (broken) {
            break;
        }
    }

    if (on_data_callback != nullptr) {
        napi_release_threadsafe_function(on_data_callback, napi_threadsafe_function_release_mode::napi_tsfn_release);
        on_data_callback = nullptr;
    }

    OH_LOG_INFO(LOG_APP, "Serial unix socket broken: %{public}d", errno);
}

std::string getString(napi_env env, napi_value value) {

    size_t size;
    napi_get_value_string_utf8(env, value, nullptr, 0, &size);

    char *buf = new char[size + 1];
    napi_get_value_string_utf8(env, value, buf, size + 1, &size);
    buf[size] = 0;

    std::string result = buf;
    delete[] buf;

    return result;
}

std::vector<std::string> splitStringByNewline(const std::string &input) {
    std::vector<std::string> result;
    std::istringstream iss(input);
    std::string line;
    while (std::getline(iss, line)) {
        result.push_back(line);
    }
    return result;
}

static napi_value startVM(napi_env env, napi_callback_info info) {

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value key_name;
    napi_value nv_arg_lines;
    napi_value nv_unix_socket;
    napi_value nv_is_pc_device;

    napi_create_string_utf8(env, "argsLines", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_arg_lines);

    napi_create_string_utf8(env, "unixSocket", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_unix_socket);

    napi_create_string_utf8(env, "isPcDevice", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_is_pc_device);

    std::string argsLines = getString(env, nv_arg_lines);
    std::vector<std::string> argsVector = splitStringByNewline(argsLines);

    std::string unixSocket = getString(env, nv_unix_socket);

    bool isPcDevice = false;
    napi_get_value_bool(env, nv_is_pc_device, &isPcDevice);

    OH_LOG_INFO(LOG_APP, "run qemuEntry with: %{public}s, isPcDevice: %{public}d", argsLines.c_str(), isPcDevice);

    if (isPcDevice) {
        // PC 设备：使用 fork 子进程运行 QEMU（QEMU 退出不影响主进程）
        OH_LOG_INFO(LOG_APP, "Using fork mode for PC device");
        
        pid_t pid = fork();
        if (pid < 0) {
            OH_LOG_ERROR(LOG_APP, "Failed to fork QEMU process: %{public}d", errno);
            return nullptr;
        } else if (pid == 0) {
            // 子进程：运行 QEMU
            const char **argv = new const char *[argsVector.size() + 1];
            for (auto i = 0; i < argsVector.size(); i += 1) {
                argv[i] = argsVector[i].c_str();
            }
            argv[argsVector.size()] = nullptr;

            int argc = argsVector.size();

            auto qemuEntry = getQemuSystemEntry();
            qemuEntry(argc, argv);

            delete[] argv;
            _exit(0);
        } else {
            // 父进程：启动一个线程监控子进程状态
            OH_LOG_INFO(LOG_APP, "QEMU started in child process with PID: %{public}d", pid);
            
            std::thread monitor_thread([pid]() {
                int status;
                waitpid(pid, &status, 0);
                OH_LOG_INFO(LOG_APP, "QEMU child process exited with status: %{public}d", status);
                
                if (on_shutdown_callback != nullptr) {
                    napi_call_threadsafe_function(on_shutdown_callback, nullptr, napi_tsfn_nonblocking);
                }
            });
            monitor_thread.detach();
        }
    } else {
        // 非 PC 设备：使用线程运行 QEMU（QEMU 退出会导致应用退出，但这里无法使用 fork）
        OH_LOG_INFO(LOG_APP, "Using thread mode for non-PC device");
        
        std::thread vm_loop([argsVector]() {
            // 标记这是 QEMU 线程
            is_qemu_thread = true;
            
            // 在 QEMU 线程中设置信号处理
            struct sigaction thread_sa;
            memset(&thread_sa, 0, sizeof(thread_sa));
            thread_sa.sa_handler = SIG_IGN;
            sigemptyset(&thread_sa.sa_mask);
            thread_sa.sa_flags = 0;
            sigaction(SIGTERM, &thread_sa, nullptr);
            sigaction(SIGINT, &thread_sa, nullptr);

            const char **argv = new const char *[argsVector.size() + 1];
            for (auto i = 0; i < argsVector.size(); i += 1) {
                argv[i] = argsVector[i].c_str();
            }
            argv[argsVector.size()] = nullptr;

            int argc = argsVector.size();
            int status = 0;

            OH_LOG_INFO(LOG_APP, "QEMU thread starting...");

            // 设置跳转点，尝试捕获 QEMU 的 exit 调用
            if (setjmp(qemu_exit_jmp) == 0) {
                qemu_exit_jmp_set = true;
                auto qemuEntry = getQemuSystemEntry();
                status = qemuEntry(argc, argv);
                qemu_exit_jmp_set = false;
                OH_LOG_INFO(LOG_APP, "qemuEntry returned normally with: %{public}d", status);
            } else {
                // QEMU 调用了 exit()，通过 longjmp 跳回这里
                qemu_exit_jmp_set = false;
                status = qemu_exit_code;
                OH_LOG_INFO(LOG_APP, "qemuEntry exit was intercepted, exit code: %{public}d", status);
            }

            delete[] argv;

            if (on_shutdown_callback != nullptr) {
                napi_call_threadsafe_function(on_shutdown_callback, nullptr, napi_tsfn_nonblocking);
            }
            
            is_qemu_thread = false;
            OH_LOG_INFO(LOG_APP, "QEMU shutdown callback triggered, thread ending normally");
        });
        vm_loop.detach();
    }

    std::thread worker([=]() { serial_output_worker(unixSocket.c_str()); });
    worker.detach();

    return nullptr;
}

static napi_value sendInput(napi_env env, napi_callback_info info) {

    if (serial_input_fd < 0) {
        return nullptr;
    }

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    uint8_t *data;
    size_t length;
    napi_status ret = napi_get_arraybuffer_info(env, args[0], (void **)&data, &length);
    assert(ret == napi_ok);

    std::string hex = convert_to_hex(data, ret);
    OH_LOG_INFO(LOG_APP, "Send, data: %{public}s", hex.c_str());

    int written = 0;
    while (written < length) {
        int size = write(serial_input_fd, (uint8_t *)data + written, length - written);
        assert(size >= 0);
        written += size;
    }

    return nullptr;
}

static napi_value onData(napi_env env, napi_callback_info info) {

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_threadsafe_function data_callback;

    napi_value data_cb_name;
    napi_create_string_utf8(env, "data_callback", NAPI_AUTO_LENGTH, &data_cb_name);
    napi_create_threadsafe_function(env, args[0], nullptr, data_cb_name, 0, 1, nullptr, nullptr, nullptr,
                                    call_on_data_callback, &data_callback);

    {
        std::lock_guard<std::mutex> lk(buffer_mtx);
        if (!temp_buffer.empty()) {
            send_data_to_callback(temp_buffer, data_callback);
            temp_buffer.clear();
        }
        on_data_callback = data_callback;
    }

    return nullptr;
}

static napi_value onShutdown(napi_env env, napi_callback_info info) {

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value data_cb_name;
    napi_create_string_utf8(env, "shutdown_callback", NAPI_AUTO_LENGTH, &data_cb_name);
    napi_create_threadsafe_function(env, args[0], nullptr, data_cb_name, 0, 1, nullptr, nullptr, nullptr,
                                    call_on_shutdown_callback, &on_shutdown_callback);

    return nullptr;
}

static napi_value bool_from_int(napi_env env, int v) {
    napi_value result;
    napi_get_boolean(env, v != 0, &result);
    return result;
}

static napi_value checkPortUsed(napi_env env, napi_callback_info info) {

    napi_status status;

    size_t argc = 1;
    napi_value argv[1];
    status = napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    if (status != napi_ok) {
        return bool_from_int(env, 1);
    }

    if (argc < 1) {
        return bool_from_int(env, 1);
    }

    // Ensure the argument is a number
    napi_valuetype vt;
    status = napi_typeof(env, argv[0], &vt);
    if (status != napi_ok || (vt != napi_number)) {
        return bool_from_int(env, 1);
    }

    double port_d;
    status = napi_get_value_double(env, argv[0], &port_d);
    if (status != napi_ok) {
        return bool_from_int(env, 1);
    }

    if (!(port_d >= 0 && port_d <= 65535)) {
        return bool_from_int(env, 1);
    }

    int port = (int)port_d;

    // Create an IPv4 TCP socket
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        return bool_from_int(env, 1);
    }

    // Prepare sockaddr_in for binding to INADDR_ANY:port
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = htonl(INADDR_ANY);
    sa.sin_port = htons((uint16_t)port);

    int bind_res = bind(sock, (struct sockaddr *)&sa, sizeof(sa));
    if (bind_res == 0) {
        close(sock);
        return bool_from_int(env, 0);
    } else {
        int err = errno;
        close(sock);
        if (err == EADDRINUSE) {
            return bool_from_int(env, 1);
        } else if (err == EACCES) {
            return bool_from_int(env, 1);
        } else {
            return bool_from_int(env, 1);
        }
    }
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"startVM", nullptr, startVM, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"onData", nullptr, onData, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"onShutdown", nullptr, onShutdown, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"sendInput", nullptr, sendInput, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"checkPortUsed", nullptr, checkPortUsed, nullptr, nullptr, nullptr, napi_default, nullptr}};
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) { napi_module_register(&demoModule); }
