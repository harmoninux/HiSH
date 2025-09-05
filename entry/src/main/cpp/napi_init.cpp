#include "napi/native_api.h"
#include <AbilityKit/ability_runtime/application_context.h>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <deviceinfo.h>
#include <dlfcn.h>
#include <limits.h>
#include <unistd.h>

#include "hilog/log.h"
#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3300
#define LOG_TAG "HiEMU"

typedef int (*QemuSystemEntry)(int, char **);

void getBundleCodeDir(char *bundleCodeDir) {
    int32_t codeDirLength;
    OH_AbilityRuntime_ApplicationContextGetBundleCodeDir(bundleCodeDir, PATH_MAX, &codeDirLength);
    bundleCodeDir[codeDirLength] = '\0';
}

static napi_value Add(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};

    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_valuetype valuetype0;
    napi_typeof(env, args[0], &valuetype0);

    napi_valuetype valuetype1;
    napi_typeof(env, args[1], &valuetype1);

    double value0;
    napi_get_value_double(env, args[0], &value0);

    double value1;
    napi_get_value_double(env, args[1], &value1);

    const char *abiList = OH_GetAbiList();
    OH_LOG_INFO(LOG_APP, "abiList: %{public}s", abiList);

    char bundleCodeDir[PATH_MAX];
    getBundleCodeDir(bundleCodeDir);
    OH_LOG_INFO(LOG_APP, "bundleCodeDir: %{public}s", bundleCodeDir);

    char libQemuPath[PATH_MAX];
    snprintf(libQemuPath, PATH_MAX, "%s/libs/%s/libqemu-system-aarch64.so", bundleCodeDir, abiList);
    OH_LOG_INFO(LOG_APP, "path of libqemu.so: %{public}s", libQemuPath);

    void *libQemuHandle = dlopen(libQemuPath, RTLD_LAZY);
    QemuSystemEntry qemuSystemEntry = (QemuSystemEntry)dlsym(libQemuHandle, "qemu_system_entry");
    OH_LOG_INFO(LOG_APP, "libqemu.so, handle: 0x%{public}p, entry: 0x%{public}p", libQemuHandle, qemuSystemEntry);

//    int q_argc = 1;
//    char *q_argv[] = {"qemu-system-aarch64"};
//    
//    qemuSystemEntry(q_argc, q_argv);

    char buffer[1024];
    int n;

    int pipefd[2];
    if (pipe(pipefd) == -1) {
        OH_LOG_INFO(LOG_APP, "create pipe failed: %{public}d", errno);
        goto end;
    }

    dup2(pipefd[1], STDOUT_FILENO);
    close(pipefd[1]);

    printf("Hello World\n");

    n = read(pipefd[0], buffer, sizeof(buffer));
    if (n >= 0) {
        buffer[n] = '\0';
    }
    OH_LOG_INFO(LOG_APP, "read from pipe: %{public}s", buffer);
    close(pipefd[0]);

end:
    napi_value sum;
    napi_create_double(env, value0 + value1, &sum);
    return sum;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {{"add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr}};
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
