#include <iostream>
#include <vector>
#include <dlfcn.h>
#include <unistd.h>
#include <libgen.h>
#include <string.h>

typedef int (*QemuImgEntry)(int argc, const char **argv);

int main(int argc, char *argv[]) {
    // Disable buffering
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    // Find libqemu-img.so path
    // Assuming it's in the same directory as this executable
    std::string libPath = "libqemu-img.so";
    Dl_info info;
    if (dladdr((void*)main, &info) && info.dli_fname) {
        std::string path = info.dli_fname;
        std::vector<char> pathCopy(path.begin(), path.end());
        pathCopy.push_back('\0');
        char *dir = dirname(pathCopy.data());
        libPath = std::string(dir) + "/libqemu-img.so";
    }

    void *handle = dlopen(libPath.c_str(), RTLD_LAZY);
    if (!handle) {
        // Try fallback path if relative path fails
        handle = dlopen("libqemu-img.so", RTLD_LAZY);
        if (!handle) {
            std::cerr << "{\"error\": \"Failed to load libqemu-img.so: " << dlerror() << "\"}" << std::endl;
            return 1;
        }
    }

    QemuImgEntry entry = (QemuImgEntry)dlsym(handle, "qemu_img_entry");
    if (!entry) {
        std::cerr << "{\"error\": \"Failed to find qemu_img_entry symbol\"}" << std::endl;
        return 1;
    }

    // Prepare args for qemu_img_entry
    // argv[0] is this runner, argv[1]... are args for qemu-img
    // We construct: {"qemu-img", argv[1], argv[2], ...}
    
    std::vector<const char*> qemu_argv;
    qemu_argv.push_back("qemu-img");
    for (int i = 1; i < argc; ++i) {
        qemu_argv.push_back(argv[i]);
    }

    // Execute qemu_img_entry
    // We don't catch signals here; if it crashes, the parent will know.
    // But since we are in a clean process (exec-ed), thread-safety issues should be gone.
    return entry(qemu_argv.size(), qemu_argv.data());
}
