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

typedef int (*QemuSystemEntry)(int, char **);

static void getBundleCodeDir(char *bundleCodeDir) {
    int32_t codeDirLength;
    OH_AbilityRuntime_ApplicationContextGetBundleCodeDir(bundleCodeDir, PATH_MAX, &codeDirLength);
    bundleCodeDir[codeDirLength] = '\0';
}

static QemuSystemEntry getQemuSystemEntry() {

    static QemuSystemEntry qemuSystemEntry = nullptr;

    if (qemuSystemEntry != nullptr) {
        return qemuSystemEntry;
    }

    const char *abiList = OH_GetAbiList();
    OH_LOG_INFO(LOG_APP, "abiList: %{public}s", abiList);

    char bundleCodeDir[PATH_MAX];
    getBundleCodeDir(bundleCodeDir);
    OH_LOG_INFO(LOG_APP, "bundleCodeDir: %{public}s", bundleCodeDir);

    char libQemuPath[PATH_MAX];
    snprintf(libQemuPath, PATH_MAX, "%s/libs/%s/libqemu-system-aarch64.so", bundleCodeDir, abiList);
    OH_LOG_INFO(LOG_APP, "path of libqemu.so: %{public}s", libQemuPath);

    void *libQemuHandle = dlopen(libQemuPath, RTLD_LAZY);
    qemuSystemEntry = (QemuSystemEntry)dlsym(libQemuHandle, "qemu_system_entry");
    OH_LOG_INFO(LOG_APP, "libqemu.so, handle: 0x%{public}p, entry: 0x%{public}p", libQemuHandle, qemuSystemEntry);

    return qemuSystemEntry;
}

static void startQemuProcess() {

    char bundleCodeDir[PATH_MAX];
    getBundleCodeDir(bundleCodeDir);

    NativeChildProcess_Args args;
    args.entryParams = strdup(bundleCodeDir);

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

void terminal_worker(int stdout_pipe_fd) {

    while (true) {

        bool broken;

        struct pollfd fds[2];
        fds[0].fd = stdout_pipe_fd;
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

    size_t argc = 4;
    napi_value args[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    double value0;
    napi_get_value_double(env, args[0], &value0);
    int width = value0;

    double value1;
    napi_get_value_double(env, args[1], &value1);
    int height = value1;

    napi_value data_cb_name;
    napi_create_string_utf8(env, "data_callback", NAPI_AUTO_LENGTH, &data_cb_name);
    napi_create_threadsafe_function(env, args[2], nullptr, data_cb_name, 0, 1, nullptr, nullptr, nullptr,
                                    call_on_data_callback, &on_data_callback);

    napi_value exit_cb_name;
    napi_create_string_utf8(env, "exit_callback", NAPI_AUTO_LENGTH, &exit_cb_name);
    napi_create_threadsafe_function(env, args[3], nullptr, exit_cb_name, 0, 1, nullptr, nullptr, nullptr,
                                    call_on_exit_callback, &on_exit_callback);

    auto entry = getQemuSystemEntry();

    int stdout_pipe[2];
    int stdin_pipe[2];
    pipe(stdout_pipe);
    pipe(stdin_pipe);

    dup2(stdout_pipe[1], STDOUT_FILENO);
    close(stdout_pipe[1]);
    dup2(stdin_pipe[0], STDIN_FILENO);
    close(stdin_pipe[0]);

    int stdout_pipe_fd = stdout_pipe[0];
    stdin_pipe_fd = stdin_pipe[1];

    std::thread thread([=]() { terminal_worker(stdout_pipe_fd); });
    thread.detach();

    std::thread vm([entry]() {
        char *args[] = {"qemu-system-aarch64",
                        "-machine",
                        "virt",
                        "-cpu",
                        "cortex-a53",
                        "-smp",
                        "1",
                        "-m",
                        "1G",
                        "-kernel",
                        "/data/storage/el2/base/haps/entry/files/vm/kernel_aarch64",
                        "-drive",
                        "if=none,format=qcow2,file=/data/storage/el2/base/haps/entry/files/vm/alpine_aarch64_rootfs.qcow2,id=hd0",
                        "-device",
                        "virtio-blk-device,drive=hd0",
                        "-append",
                        "root=/dev/vda rw rootfstype=ext4 console=ttyAMA0",
                        "-nographic",
                        "-L",
                        "/data/storage/el2/base/haps/entry/files/vm/",
                        nullptr};
        int argc = 0;
        while (args[argc] != nullptr) {
            argc += 1;
        }

        entry(argc, args);
    });
    vm.detach();

    return nullptr;
}

static napi_value send(napi_env env, napi_callback_info info) {

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
