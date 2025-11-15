#include "napi/native_api.h"
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <dlfcn.h>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

#include "hilog/log.h"
#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3300
#define LOG_TAG "HiSH"

typedef int (*qemu_system_entry)(int, const char **);

static qemu_system_entry get_qemu_system_entry() {

    static qemu_system_entry qemu_entry = nullptr;

    if (qemu_entry != nullptr) {
        return qemu_entry;
    }

    const char *libqemu_path = "libqemu-system-aarch64.so";

    void *libqemu_handle = dlopen(libqemu_path, RTLD_LAZY);

    if (!libqemu_handle) {
        OH_LOG_INFO(LOG_APP, "Failed to load libqemu.so errno: %{public}d", errno);
    }

    qemu_entry = (qemu_system_entry)dlsym(libqemu_handle, "qemu_system_entry");
    OH_LOG_INFO(LOG_APP, "libqemu.so, handle: 0x%{public}p, entry: 0x%{public}p", libqemu_handle, qemu_entry);

    return qemu_entry;
}

std::string get_string(napi_env env, napi_value value) {

    size_t size;
    napi_get_value_string_utf8(env, value, nullptr, 0, &size);

    char *buf = new char[size + 1];
    napi_get_value_string_utf8(env, value, buf, size + 1, &size);
    buf[size] = 0;

    std::string result = buf;
    delete[] buf;

    return result;
}

std::vector<std::string> split_string_by_new_line(const std::string &input) {
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

    napi_create_string_utf8(env, "argsLines", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_arg_lines);

    std::string args_lines = get_string(env, nv_arg_lines);
    std::vector<std::string> args_vector = split_string_by_new_line(args_lines);

    OH_LOG_INFO(LOG_APP, "run qemu_entry with: %{public}s", args_lines.c_str());

    std::thread vm_loop([args_vector]() {
        const char **argv = new const char *[args_vector.size() + 1];
        for (auto i = 0; i < args_vector.size(); i += 1) {
            argv[i] = args_vector[i].c_str();
        }
        argv[args_vector.size()] = nullptr;

        int argc = args_vector.size();

        auto qemu_entry = get_qemu_system_entry();
        qemu_entry(argc, argv);

        //  cannot reach here
        delete[] argv;
    });
    vm_loop.detach();

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
