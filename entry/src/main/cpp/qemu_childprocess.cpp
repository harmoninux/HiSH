#include <AbilityKit/ability_runtime/application_context.h>
#include <AbilityKit/native_child_process.h>
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
#define LOG_TAG "HiEMUChild"

typedef int (*QemuSystemEntry)(int, char **);

extern "C" {

void Main(NativeChildProcess_Args args) {

    char *entryParams = args.entryParams;
    NativeChildProcess_Fd *current = args.fdList.head;
    while (current != nullptr) {
        char *fdName = current->fdName;
        int32_t fd = current->fd;
        current = current->next;
    }

    const char *abiList = OH_GetAbiList();
    OH_LOG_INFO(LOG_APP, "abiList: %{public}s", abiList);

    char *bundleCodeDir = entryParams;
    OH_LOG_INFO(LOG_APP, "bundleCodeDir: %{public}s", bundleCodeDir);

    char libQemuPath[PATH_MAX];
    snprintf(libQemuPath, PATH_MAX, "%s/libs/%s/libqemu-system-aarch64.so", bundleCodeDir, abiList);
    OH_LOG_INFO(LOG_APP, "path of libqemu.so: %{public}s", libQemuPath);

    void *libQemuHandle = dlopen(libQemuPath, RTLD_LAZY);
    QemuSystemEntry qemuSystemEntry = (QemuSystemEntry)dlsym(libQemuHandle, "qemu_system_entry");
    OH_LOG_INFO(LOG_APP, "libqemu.so, handle: 0x%{public}p, entry: 0x%{public}p", libQemuHandle, qemuSystemEntry);

    char *argv[] = {"qemu-system-aarch64"};
    qemuSystemEntry(1, argv);
}

} // extern "C"