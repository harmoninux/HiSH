#include "napi/native_api.h"
#include <AbilityKit/ability_runtime/application_context.h>
#include <AbilityKit/native_child_process.h>
#include <assert.h>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deviceinfo.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
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

int stdin_pipe_fd = -1;
napi_threadsafe_function on_data_callback = nullptr;
napi_threadsafe_function on_exit_callback = nullptr;

typedef int (*QemuSystemEntry)(int, const char **);

std::string getBundleCodeDir() {

    char bundleCodeDir[PATH_MAX];

    int32_t dirLength;
    OH_AbilityRuntime_ApplicationContextGetBundleCodeDir(bundleCodeDir, PATH_MAX, &dirLength);
    bundleCodeDir[dirLength] = '\0';

    return bundleCodeDir;
}

std::string getTempDir() {

    char tempDir[PATH_MAX];

    int32_t dirLength;
    OH_AbilityRuntime_ApplicationContextGetTempDir(tempDir, PATH_MAX, &dirLength);
    tempDir[dirLength] = '\0';

    return tempDir;
}

std::string getFilesDir() {

    char tempDir[PATH_MAX];

    int32_t dirLength;
    OH_AbilityRuntime_ApplicationContextGetFilesDir(tempDir, PATH_MAX, &dirLength);
    tempDir[dirLength] = '\0';

    return tempDir;
}

static QemuSystemEntry getQemuSystemEntry() {

    static QemuSystemEntry qemuSystemEntry = nullptr;

    if (qemuSystemEntry != nullptr) {
        return qemuSystemEntry;
    }

    const char *abiList = OH_GetAbiList();
    OH_LOG_INFO(LOG_APP, "abiList: %{public}s", abiList);

    std::string bundleCodeDir = getBundleCodeDir();
    OH_LOG_INFO(LOG_APP, "bundleCodeDir: %{public}s", bundleCodeDir.c_str());

    char libQemuPath[PATH_MAX];
    snprintf(libQemuPath, PATH_MAX, "%s/libs/%s/libqemu-system-aarch64.so", bundleCodeDir.c_str(), abiList);
    OH_LOG_INFO(LOG_APP, "path of libqemu.so: %{public}s", libQemuPath);
    if (strcmp(abiList, "arm64-v8a") == 0 && access(libQemuPath, F_OK) != 0) {
        OH_LOG_INFO(LOG_APP, "%{public}s not exist, errno: %{public}d", libQemuPath, errno);
        snprintf(libQemuPath, PATH_MAX, "%s/libs/%s/libqemu-system-aarch64.so", bundleCodeDir.c_str(), "arm64");
    }

    void *libQemuHandle = dlopen(libQemuPath, RTLD_LAZY);

    if (!libQemuHandle) {
        OH_LOG_INFO(LOG_APP, "Failed to load libqemu.so errno: %{public}d", errno);
    }

    qemuSystemEntry = (QemuSystemEntry)dlsym(libQemuHandle, "qemu_system_entry");
    OH_LOG_INFO(LOG_APP, "libqemu.so, handle: 0x%{public}p, entry: 0x%{public}p", libQemuHandle, qemuSystemEntry);

    return qemuSystemEntry;
}

static void startQemuProcess() {

    auto bundleCodeDir = getBundleCodeDir();

    NativeChildProcess_Args args;
    args.entryParams = strdup(bundleCodeDir.c_str());

    args.fdList.head = (NativeChildProcess_Fd *)malloc(sizeof(NativeChildProcess_Fd));
    args.fdList.head->fdName = (char *)malloc(sizeof(char) * 4);
    (void)strcpy(args.fdList.head->fdName, "fd1");
    int32_t fd = open("/data/storage/el2/base/haps/entry/files/test.txt", O_RDWR | O_CREAT, 0644);
    args.fdList.head->fd = fd;
    args.fdList.head->next = NULL;
    NativeChildProcess_Options options = {.isolationMode = NCP_ISOLATION_MODE_ISOLATED};

    int32_t pid = -1;
    Ability_NativeChildProcess_ErrCode ret =
        OH_Ability_StartNativeChildProcess("libqemu_childprocess.so:Main", args, options, &pid);
    if (ret != NCP_NO_ERROR) {
        // 释放NativeChildProcess_Args中的内存空间防止内存泄漏
        // 子进程未能正常启动时的异常处理
        // ...
    }
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

static void call_on_exit_callback(napi_env env, napi_value js_callback, void *context, void *data) {

    napi_value global;
    napi_get_global(env, &global);

    napi_value result;
    napi_value args[1] = {};
    napi_call_function(env, global, js_callback, 0, args, &result);
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

void call_data_callback(const std::string &hex) {
    if (hex.length() > 0 && on_data_callback != nullptr) {
        data_buffer *pbuf = new data_buffer{.buf = new char[hex.length()], .size = (size_t)hex.length()};
        memcpy(pbuf->buf, &hex[0], hex.length());
        napi_call_threadsafe_function(on_data_callback, pbuf, napi_tsfn_nonblocking);
    }
}

void terminal_worker(const char *unix_socket_path) {

    while (true) {
        int acc = access(unix_socket_path, F_OK);
        if (acc == 0) {
            break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }

    struct sockaddr_un server_addr;
    int client_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (client_fd == -1) {
        OH_LOG_INFO(LOG_APP, "Failed to create unix socket: %{public}s", errno);
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

    stdin_pipe_fd = client_fd;

    while (true) {

        bool broken;

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
                call_data_callback(hex);
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

    if (on_exit_callback) {
        napi_call_threadsafe_function(on_exit_callback, nullptr, napi_tsfn_nonblocking);
    }
}

static napi_value startVM(napi_env env, napi_callback_info info) {

    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value data_cb_name;
    napi_create_string_utf8(env, "data_callback", NAPI_AUTO_LENGTH, &data_cb_name);
    napi_create_threadsafe_function(env, args[0], nullptr, data_cb_name, 0, 1, nullptr, nullptr, nullptr,
                                    call_on_data_callback, &on_data_callback);

    napi_value exit_cb_name;
    napi_create_string_utf8(env, "exit_callback", NAPI_AUTO_LENGTH, &exit_cb_name);
    napi_create_threadsafe_function(env, args[1], nullptr, exit_cb_name, 0, 1, nullptr, nullptr, nullptr,
                                    call_on_exit_callback, &on_exit_callback);

    auto qemuEntry = getQemuSystemEntry();

    auto vmFilesDir = getFilesDir() + "/vm";
    auto tempDir = getTempDir();
    std::string unixSocketPath = tempDir + "/serial_socket";

    if (access(unixSocketPath.c_str(), F_OK) == 0) {
        unlink(unixSocketPath.c_str());
    }

    std::thread vm_loop([qemuEntry, unixSocketPath, vmFilesDir]() {
        std::string unixSocketSerial = "unix:" + unixSocketPath + ",server";
        std::string kernelPath = vmFilesDir + "/kernel_aarch64";
        std::string rootFsImgPath = vmFilesDir + "/alpine_aarch64_rootfs.qcow2";
        std::string driveOption = "if=none,format=qcow2,file=" + rootFsImgPath + ",id=hd0";
        const char *args[] = {"qemu-system-aarch64",
                              "-machine",
                              "virt",
                              "-cpu",
                              "cortex-a53",
                              "-smp",
                              "2",
                              "-m",
                              "1G",
                              "-kernel",
                              kernelPath.c_str(),
                              "-drive",
                              driveOption.c_str(),
                              "-device",
                              "virtio-blk-device,drive=hd0",
                              "-append",
                              "root=/dev/vda rw rootfstype=ext4 console=ttyAMA0 TERM=ansi",
                              "-nographic",
                              "-L",
                              vmFilesDir.c_str(),
                              "-serial",
                              unixSocketSerial.c_str(),
                              "-netdev",
                              "user,id=eth0",
                              "-device",
                              "virtio-net-device,netdev=eth0",
                              nullptr};
        int argc = 0;
        while (args[argc] != nullptr) {
            argc += 1;
        }

        qemuEntry(argc, args);
    });
    vm_loop.detach();

    std::thread thread([=]() { terminal_worker(unixSocketPath.c_str()); });
    thread.detach();

    return nullptr;
}

static napi_value send(napi_env env, napi_callback_info info) {

    if (stdin_pipe_fd < 0) {
        return nullptr;
    }

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char *data;
    size_t length;
    napi_status ret = napi_get_arraybuffer_info(env, args[0], (void **)&data, &length);
    assert(ret == napi_ok);

    std::string hex;
    for (int i = 0; i < length; i++) {
        if (data[i] >= 127 || data[i] < 32) {
            char temp[8];
            snprintf(temp, sizeof(temp), "\\x%02x", data[i]);
            hex += temp;
        } else {
            hex += (char)data[i];
        }
    }
    OH_LOG_INFO(LOG_APP, "Send, data: %{public}s", hex.c_str());

    int fd = stdin_pipe_fd;
    int written = 0;
    while (written < length) {
        int size = write(fd, (uint8_t *)data + written, length - written);
        assert(size >= 0);
        written += size;
    }

    return nullptr;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {{"startVM", nullptr, startVM, nullptr, nullptr, nullptr, napi_default, nullptr},
                                       {"send", nullptr, send, nullptr, nullptr, nullptr, napi_default, nullptr}};
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
