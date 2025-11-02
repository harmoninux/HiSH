#include "napi/native_api.h"
#include <assert.h>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>

#include "hilog/log.h"
#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3300
#define LOG_TAG "HiSH"

struct data_buffer {
    char *buf;
    size_t size;
};

int serial_input_fd = -1;
napi_threadsafe_function on_data_callback = nullptr;

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

    OH_LOG_INFO(LOG_APP, "Serial unix socket broken: %{public}d", errno);
}

static int getArgc(const char **args) {
    int argc = 0;
    while (args[argc] != nullptr) {
        argc += 1;
    }
    return argc;
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

static void append_args(std::vector<std::string> &out, const std::vector<std::string> &partial) {
    for (auto &v : partial) {
        out.push_back(v);
    }
}

static napi_value startVM(napi_env env, napi_callback_info info) {

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value key_name;
    napi_value nv_temp_dir;
    napi_value nv_files_dir;
    napi_value nv_cpu_count;
    napi_value nv_mem_size;
    napi_value nv_port_mapping;
    napi_value nv_is_pc;
    napi_value nv_root_fs;
    napi_value nv_shared_folder;
    napi_value nv_vm_base;
    napi_value nv_kernel;

    napi_create_string_utf8(env, "tempDir", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_temp_dir);

    napi_create_string_utf8(env, "filesDir", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_files_dir);

    napi_create_string_utf8(env, "cpuCount", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_cpu_count);

    napi_create_string_utf8(env, "memSize", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_mem_size);

    napi_create_string_utf8(env, "portMapping", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_port_mapping);

    napi_create_string_utf8(env, "isPc", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_is_pc);

    napi_create_string_utf8(env, "rootFilesystem", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_root_fs);

    napi_create_string_utf8(env, "sharedFolder", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_shared_folder);

    napi_create_string_utf8(env, "vmBaseDir", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_vm_base);

    napi_create_string_utf8(env, "kernel", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_kernel);

    std::string tempDir = getString(env, nv_temp_dir);
    std::string portMapping = getString(env, nv_port_mapping);
    std::string rootFilesystem = getString(env, nv_root_fs);
    std::string sharedFolder = getString(env, nv_shared_folder);
    std::string vmBaseDir = getString(env, nv_vm_base);
    std::string kernel = getString(env, nv_kernel);

    int cpuCount, memSize;
    napi_get_value_int32(env, nv_cpu_count, &cpuCount);
    napi_get_value_int32(env, nv_mem_size, &memSize);

    bool isPc;
    napi_get_value_bool(env, nv_is_pc, &isPc);

    std::string unixSocketPath = tempDir + "/serial_socket";
    OH_LOG_INFO(LOG_APP, "serial unix socket: %{public}s", unixSocketPath.c_str());
    if (access(unixSocketPath.c_str(), F_OK) == 0) {
        OH_LOG_INFO(LOG_APP, "remove exist unix socket: %{public}s", unixSocketPath.c_str());
        unlink(unixSocketPath.c_str());
    }

    OH_LOG_INFO(LOG_APP, "shared folder from host to guest: %{public}s", sharedFolder.c_str());
    if (access(sharedFolder.c_str(), F_OK) != 0) {
        mkdir(sharedFolder.c_str(), S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH);
    }

    std::thread vm_loop(
        [unixSocketPath, vmBaseDir, cpuCount, memSize, portMapping, sharedFolder, isPc, rootFilesystem, kernel]() {
            std::string unixSocketSerial = "unix:" + unixSocketPath + ",server,nowait";
            std::string cpu = std::to_string(cpuCount);
            std::string mem = std::to_string(memSize) + "M";
            std::string portMappingOption = portMapping.empty() ? "user,id=eth0" : "user,id=eth0," + portMapping;
            std::string fsDev0Option = "local,security_model=mapped-file,id=fsdev0,path=" + sharedFolder;

            std::vector<std::string> basic = {"-machine",   "virt", "-cpu",    "cortex-a53", "-smp",
                                              cpu,          "-m",   mem,       "-kernel",    kernel,
                                              "-nographic", "-L",   vmBaseDir, "-serial",    unixSocketSerial};

            std::vector<std::string> net = {"-netdev", portMappingOption};

            std::vector<std::string> shared = {"-device", "virtio-net-device,netdev=eth0",
                                               "-fsdev",  fsDev0Option,
                                               "-device", "virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=hostshare"};

            std::vector<std::string> argsVector = {"qemu-system-aarch64"};
            append_args(argsVector, basic);
            append_args(argsVector, net);
            append_args(argsVector, shared);

            if (rootFilesystem != sharedFolder) {
                std::string driveOption = "if=none,format=qcow2,file=" + rootFilesystem + ",id=hd0";
                std::vector<std::string> drive = {"-drive", driveOption, "-device", "virtio-blk-device,drive=hd0"};
                std::vector<std::string> kernelParam = {"-append",
                                                        "root=/dev/vda rw rootfstype=ext4 console=ttyAMA0 TERM=ansi"};
                append_args(argsVector, drive);
                append_args(argsVector, kernelParam);
            } else {
                std::vector<std::string> kernelParam = {"-append",
                                                        "root=hostshare rw rootfstype=9p rootflags=trans=virtio,version=9p2000.L console=ttyAMA0 TERM=ansi"};
                append_args(argsVector, kernelParam);
            }

            if (isPc) {
                std::vector<std::string> userShared = {
                    "-fsdev", "local,security_model=mapped-file,id=fsdev1,path=/storage/Users/currentUser", "-device",
                    "virtio-9p-pci,id=fs1,fsdev=fsdev1,mount_tag=usershare"};
                append_args(argsVector, userShared);
            }

            const char **args = new const char *[argsVector.size() + 1];
            for (auto i = 0; i < argsVector.size(); i += 1) {
                args[i] = argsVector[i].c_str();
            }
            args[argsVector.size()] = nullptr;

            int argc = getArgc(args);

            OH_LOG_INFO(LOG_APP, "run qemuEntry with: %{public}d", argc);
            OH_LOG_INFO(LOG_APP, "linux kernel: %{public}s", kernel.c_str());
            OH_LOG_INFO(LOG_APP, "rootfs: %{public}s", rootFilesystem.c_str());

            auto qemuEntry = getQemuSystemEntry();
            qemuEntry(argc, args);

            //  cannot reach here
            delete[] args;
        });
    vm_loop.detach();

    std::thread worker([=]() { serial_output_worker(unixSocketPath.c_str()); });
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

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"startVM", nullptr, startVM, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"onData", nullptr, onData, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"sendInput", nullptr, sendInput, nullptr, nullptr, nullptr, napi_default, nullptr}};
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
