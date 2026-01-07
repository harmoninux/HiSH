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
#include <sys/prctl.h>
#include <thread>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <setjmp.h>
#include <libgen.h>
#include <sys/auxv.h>
#include <atomic>


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

// P1-01修复: 保存 dlopen 句柄以便后续释放
static void *libQemuHandle = nullptr;
static void *libQemuImgHandle = nullptr;

// 自动释放句柄
__attribute__((destructor)) static void cleanup_handles()
{
    if (libQemuHandle)
    {
        dlclose(libQemuHandle);
        libQemuHandle = nullptr;
    }
    if (libQemuImgHandle)
    {
        dlclose(libQemuImgHandle);
        libQemuImgHandle = nullptr;
    }
}

// 覆盖 exit 函数
extern "C" void exit(int status)
{
    if (is_qemu_thread && qemu_exit_jmp_set)
    {
        // P1-06 & P1-13修复: 记录详细日志，并提醒 longjmp 风险
        // 注意：longjmp 会跳过当前栈帧的析构函数，QEMU 线程中应避免使用复杂的 C++ 对象
        OH_LOG_INFO(LOG_APP, "QEMU called exit(%{public}d), using longjmp to return to jump point", status);
        qemu_exit_code = status;
        longjmp(qemu_exit_jmp, 1);
    }
    else
    {
        // 调用真正的 exit
        OH_LOG_INFO(LOG_APP, "Normal exit(%{public}d) called, process will terminate", status);
        _exit(status);
    }
}

struct data_buffer
{
    char *buf;
    size_t size;
};

// QEMU 子进程 PID (PC 模式下使用)
static pid_t qemu_child_pid = -1;

// P0-08修复: 使用std::atomic避免多线程竞争
std::atomic<int> serial_input_fd{-1};
napi_threadsafe_function on_data_callback = nullptr;
napi_threadsafe_function on_shutdown_callback = nullptr;

std::mutex buffer_mtx;
std::string temp_buffer = "";

// ================== ARM 架构版本检测 ==================
// HWCAP 常量定义（参考 Linux asm/hwcap.h）
#ifndef HWCAP_ATOMICS
#define HWCAP_ATOMICS (1 << 8) // LSE (Large System Extensions)
#endif
#ifndef HWCAP_SHA3
#define HWCAP_SHA3 (1 << 17) // SHA3
#endif
#ifndef HWCAP_SM4
#define HWCAP_SM4 (1 << 19) // SM4
#endif
#ifndef HWCAP_ASIMDDP
#define HWCAP_ASIMDDP (1 << 20) // ASIMD dot product (DotProd)
#endif
#ifndef HWCAP_LRCPC
#define HWCAP_LRCPC (1 << 15) // RCPC (Release Consistent processor consistent)
#endif

// 全局 ARM 架构版本缓存
static std::string g_cpuArchVersion = "";

// 检测 ARM 架构版本
// 返回 "v85" 表示支持 ARMv8.5 所有特性，返回 "generic" 表示 ARMv8.2 兼容模式
static std::string detectArmArchVersion()
{
    if (!g_cpuArchVersion.empty())
    {
        return g_cpuArchVersion;
    }

    unsigned long hwcap = getauxval(AT_HWCAP);

    bool hasAtomics = (hwcap & HWCAP_ATOMICS) != 0;
    bool hasSha3 = (hwcap & HWCAP_SHA3) != 0;
    bool hasSm4 = (hwcap & HWCAP_SM4) != 0;
    bool hasAsimddp = (hwcap & HWCAP_ASIMDDP) != 0;
    bool hasLrcpc = (hwcap & HWCAP_LRCPC) != 0;

    bool isV85 = hasAtomics && hasSha3 && hasSm4 && hasAsimddp && hasLrcpc;

    OH_LOG_INFO(LOG_APP, "=== ARM CPU Feature Detection ===");
    OH_LOG_INFO(LOG_APP, "HWCAP: 0x%{public}lx", hwcap);
    OH_LOG_INFO(LOG_APP, "Features: Atomics=%{public}d, SHA3=%{public}d, SM4=%{public}d, DotProd=%{public}d, RCPC=%{public}d",
                hasAtomics, hasSha3, hasSm4, hasAsimddp, hasLrcpc);
    OH_LOG_INFO(LOG_APP, "Detected: %{public}s", isV85 ? "v85" : "generic");

    g_cpuArchVersion = isV85 ? "v85" : "generic";
    return g_cpuArchVersion;
}

typedef int (*QemuSystemEntry)(int, const char **);

static QemuSystemEntry getQemuSystemEntry()
{

    static QemuSystemEntry qemuSystemEntry = nullptr;

    if (qemuSystemEntry != nullptr)
    {
        return qemuSystemEntry;
    }

    // 根据 ARM 架构版本选择对应的 QEMU 库
    std::string archVersion = detectArmArchVersion();
    
    std::string libPathV85 = "/data/storage/el1/bundle/libs/arm64-v8a/libqemu-system-aarch64.so";
    std::string libPathV82 = "/data/storage/el1/bundle/libs/arm64-v82/libqemu-system-aarch64.so";
    
    std::string selectedPath = "";
    
    bool hasV85 = (access(libPathV85.c_str(), F_OK) == 0);
    bool hasV82 = (access(libPathV82.c_str(), F_OK) == 0);
    
    if (archVersion == "v85") {
        // 硬件支持 v85
        if (hasV85) {
            selectedPath = libPathV85; // 首选 v85
        } else if (hasV82) {
            selectedPath = libPathV82; // 回退到 v82 (兼容)
            OH_LOG_WARN(LOG_APP, "v85 hardware detected but v85 lib missing, using v82 lib");
        }
    } else {
        // 硬件仅支持 v82 (generic)
        if (hasV82) {
            selectedPath = libPathV82; // 首选 v82
        } else if (hasV85) {
            selectedPath = libPathV85; // 只有 v85，强制使用 (可能会崩，但满足用户"使用仅有的库"要求)
            OH_LOG_WARN(LOG_APP, "v82 hardware detected but v82 lib missing, forcing v85 lib (RISK OF CRASH)");
        }
    }
    
    if (selectedPath.empty()) {
        OH_LOG_WARN(LOG_APP, "No suitable QEMU library found in specific paths! Falling back to default library name.");
        selectedPath = "libqemu-system-aarch64.so";
    }

    OH_LOG_INFO(LOG_APP, "Loading QEMU from: %{public}s", selectedPath.c_str());

    libQemuHandle = dlopen(selectedPath.c_str(), RTLD_LAZY);

    if (!libQemuHandle)
    {
        OH_LOG_ERROR(LOG_APP, "Failed to load libqemu.so from %{public}s, errno: %{public}d, trying default path",
                     selectedPath.c_str(), errno);
        // 回退到默认路径
        libQemuHandle = dlopen("libqemu-system-aarch64.so", RTLD_LAZY);
    }

    if (!libQemuHandle)
    {
        OH_LOG_ERROR(LOG_APP, "Failed to load libqemu.so errno: %{public}d", errno);
        return nullptr;
    }

    qemuSystemEntry = (QemuSystemEntry)dlsym(libQemuHandle, "qemu_system_entry");
    OH_LOG_INFO(LOG_APP, "Library: %{public}s, handle: 0x%{public}p, entry: 0x%{public}p",
                selectedPath.c_str(), libQemuHandle, qemuSystemEntry);

    return qemuSystemEntry;
}

// 前向声明
static std::string getString(napi_env env, napi_value value);

// qemu-img 入口函数类型
typedef int (*QemuImgEntry)(int, const char **);

static QemuImgEntry getQemuImgEntry()
{
    static QemuImgEntry qemuImgEntry = nullptr;

    if (qemuImgEntry != nullptr)
    {
        return qemuImgEntry;
    }

    const char *libQemuImgPath = "libqemu-img.so";
    libQemuImgHandle = dlopen(libQemuImgPath, RTLD_LAZY);

    if (!libQemuImgHandle)
    {
        OH_LOG_ERROR(LOG_APP, "Failed to load libqemu-img.so errno: %{public}d", errno);
        return nullptr;
    }

    qemuImgEntry = (QemuImgEntry)dlsym(libQemuImgHandle, "qemu_img_entry");
    OH_LOG_INFO(LOG_APP, "libqemu-img.so, handle: 0x%{public}p, entry: 0x%{public}p", libQemuImgHandle, qemuImgEntry);

    return qemuImgEntry;
}

// QCOW2 文件头结构（简化版）
// 参考: https://github.com/qemu/qemu/blob/master/docs/interop/qcow2.txt
struct Qcow2Header
{
    uint32_t magic;                   // 0-3: Magic number 'QFI\xfb'
    uint32_t version;                 // 4-7: Version (2 or 3)
    uint64_t backing_file_offset;     // 8-15
    uint32_t backing_file_size;       // 16-19
    uint32_t cluster_bits;            // 20-23: cluster_size = 1 << cluster_bits
    uint64_t size;                    // 24-31: Virtual size in bytes
    uint32_t crypt_method;            // 32-35
    uint32_t l1_size;                 // 36-39
    uint64_t l1_table_offset;         // 40-47
    uint64_t refcount_table_offset;   // 48-55
    uint32_t refcount_table_clusters; // 56-59
    uint32_t nb_snapshots;            // 60-63
    uint64_t snapshots_offset;        // 64-71
    // QCOW2 v3 additional fields
    uint64_t incompatible_features; // 72-79
    uint64_t compatible_features;   // 80-87
    uint64_t autoclear_features;    // 88-95
    uint32_t refcount_order;        // 96-99: refcount_bits = 1 << refcount_order
    uint32_t header_length;         // 100-103
};

// 大端转小端（网络字节序转主机字节序）
static uint32_t be32toh_manual(uint32_t val)
{
    return ((val & 0xFF) << 24) | ((val & 0xFF00) << 8) |
           ((val & 0xFF0000) >> 8) | ((val & 0xFF000000) >> 24);
}

static uint64_t be64toh_manual(uint64_t val)
{
    uint32_t low = (uint32_t)(val & 0xFFFFFFFF);
    uint32_t high = (uint32_t)(val >> 32);
    return ((uint64_t)be32toh_manual(low) << 32) | be32toh_manual(high);
}

// 直接从 QCOW2 文件头读取信息
static std::string getQcow2Info(const std::string &imagePath)
{
    int fd = open(imagePath.c_str(), O_RDONLY);
    if (fd < 0)
    {
        // P1-11修复: 返回详细的错误信息
        int err = errno;
        OH_LOG_ERROR(LOG_APP, "Failed to open image file: %{public}s, errno: %{public}d (%{public}s)",
                     imagePath.c_str(), err, strerror(err));
        return "{\"error\": \"Failed to open image file\", \"errno\": " + std::to_string(err) + ", \"message\": \"" + strerror(err) + "\"}";
    }

    // 获取文件大小（实际磁盘占用）
    struct stat st;
    if (fstat(fd, &st) < 0)
    {
        close(fd);
        return "{\"error\": \"Failed to stat image file\"}";
    }
    uint64_t actual_size = st.st_size;

    // 读取头部
    Qcow2Header header;
    ssize_t bytesRead = read(fd, &header, sizeof(header));
    close(fd);

    if (bytesRead < 72)
    { // 至少需要读取到 v2 头部
        return "{\"error\": \"Failed to read QCOW2 header\"}";
    }

    // 检查 magic number
    uint32_t magic = be32toh_manual(header.magic);
    if (magic != 0x514649FB)
    { // 'QFI\xfb'
        return "{\"error\": \"Not a valid QCOW2 file\", \"magic\": " + std::to_string(magic) + "}";
    }

    // 解析头部字段
    uint32_t version = be32toh_manual(header.version);
    uint64_t virtual_size = be64toh_manual(header.size);
    uint32_t cluster_bits = be32toh_manual(header.cluster_bits);
    // P0-07修复: QCOW2规范要求 cluster_bits 在 9-21 范围内 (512B - 2MB clusters)
    if (cluster_bits < 9 || cluster_bits > 21)
    {
        return "{\"error\": \"Invalid cluster_bits value\", \"cluster_bits\": " + std::to_string(cluster_bits) + "}";
    }
    // P1-09修复: 使用 64 位无符号整数计算 cluster_size，防止中间过程溢出
    uint64_t cluster_size = 1ULL << cluster_bits;
    uint32_t nb_snapshots = be32toh_manual(header.nb_snapshots);

    // QCOW2 v3 特有字段
    bool lazy_refcounts = false;
    bool extended_l2 = false;
    uint32_t refcount_bits = 16; // 默认值

    if (version >= 3 && bytesRead >= 104)
    {
        uint64_t compat_features = be64toh_manual(header.compatible_features);
        lazy_refcounts = (compat_features & 0x01) != 0; // bit 0: lazy refcounts

        uint64_t incompat_features = be64toh_manual(header.incompatible_features);
        extended_l2 = (incompat_features & 0x10) != 0; // bit 4: extended L2

        uint32_t refcount_order = be32toh_manual(header.refcount_order);
        refcount_bits = 1 << refcount_order;
    }

    // 构建 JSON 输出（与 qemu-img info --output=json 格式兼容）
    std::ostringstream json;
    json << "{"
         << "\"filename\": \"" << imagePath << "\","
         << "\"format\": \"qcow2\","
         << "\"virtual-size\": " << virtual_size << ","
         << "\"actual-size\": " << actual_size << ","
         << "\"cluster-size\": " << cluster_size << ","
         << "\"format-specific\": {"
         << "\"type\": \"qcow2\","
         << "\"data\": {"
         << "\"compat\": \"" << (version >= 3 ? "1.1" : "0.10") << "\","
         << "\"lazy-refcounts\": " << (lazy_refcounts ? "true" : "false") << ","
         << "\"refcount-bits\": " << refcount_bits << ","
         << "\"extended-l2\": " << (extended_l2 ? "true" : "false") << ","
         << "\"corrupt\": false"
         << "}}"
         << "}";

    OH_LOG_INFO(LOG_APP, "QCOW2 info: version=%{public}d, virtual_size=%{public}llu, cluster_size=%{public}d",
                version, (unsigned long long)virtual_size, cluster_size);

    return json.str();
}

// NAPI 函数：获取镜像信息（直接读取 QCOW2 头部，不调用 qemu-img）
static napi_value getImageInfo(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1)
    {
        napi_value result;
        napi_create_string_utf8(env, "{\"error\": \"Missing image path argument\"}", NAPI_AUTO_LENGTH, &result);
        return result;
    }

    std::string imagePath = getString(env, args[0]);

    OH_LOG_INFO(LOG_APP, "getImageInfo called with path: %{public}s", imagePath.c_str());

    // 直接读取 QCOW2 文件头获取信息
    std::string output = getQcow2Info(imagePath);

    napi_value result;
    napi_create_string_utf8(env, output.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

// ================== 快照管理功能 ==================

// QCOW2 快照头部结构
// 参考: https://github.com/qemu/qemu/blob/master/docs/interop/qcow2.txt
#pragma pack(push, 1)
struct QcowSnapshotHeader
{
    uint64_t l1_table_offset; // 快照 L1 表偏移
    uint32_t l1_size;         // L1 表大小
    uint16_t id_str_size;     // ID 字符串长度
    uint16_t name_size;       // 名称长度
    uint32_t date_sec;        // 创建日期（秒）
    uint32_t date_nsec;       // 创建日期（纳秒）
    uint64_t vm_clock_nsec;   // VM 时钟（纳秒）
    uint32_t vm_state_size;   // VM 状态大小
    uint32_t extra_data_size; // QCOW2 v3: 额外数据大小
    // 后面跟着: id_str, name, padding
};
#pragma pack(pop)

// 标记 qemu-img 是否已调用过（用于检测是否需要重启）
static bool qemu_img_called = false;
static bool qemu_img_failed = false;

// 读取 QCOW2 快照列表（直接解析文件，不调用 qemu-img）
static std::string getSnapshotsFromFile(const std::string &imagePath)
{
    int fd = open(imagePath.c_str(), O_RDONLY);
    if (fd < 0)
    {
        return "{\"error\": \"Failed to open image file\"}";
    }

    // 读取头部
    Qcow2Header header;
    ssize_t bytesRead = read(fd, &header, sizeof(header));

    if (bytesRead < 72)
    {
        close(fd);
        return "{\"error\": \"Failed to read QCOW2 header\"}";
    }

    // 检查 magic number
    uint32_t magic = be32toh_manual(header.magic);
    if (magic != 0x514649FB)
    {
        close(fd);
        return "{\"error\": \"Not a valid QCOW2 file\"}";
    }

    uint32_t nb_snapshots = be32toh_manual(header.nb_snapshots);
    uint64_t snapshots_offset = be64toh_manual(header.snapshots_offset);
    uint32_t version = be32toh_manual(header.version);

    OH_LOG_INFO(LOG_APP, "QCOW2: nb_snapshots=%{public}d, snapshots_offset=%{public}llu",
                nb_snapshots, (unsigned long long)snapshots_offset);

    if (nb_snapshots == 0)
    {
        close(fd);
        return "{\"snapshots\": []}";
    }

    // 跳转到快照表
    if (lseek(fd, snapshots_offset, SEEK_SET) < 0)
    {
        close(fd);
        return "{\"error\": \"Failed to seek to snapshot table\"}";
    }

    std::ostringstream json;
    json << "{\"snapshots\": [";

    for (uint32_t i = 0; i < nb_snapshots; i++)
    {
        QcowSnapshotHeader snapHeader;
        if (read(fd, &snapHeader, sizeof(snapHeader)) < (ssize_t)sizeof(snapHeader))
        {
            break;
        }

        uint16_t id_str_size = (snapHeader.id_str_size >> 8) | (snapHeader.id_str_size << 8); // BE to LE
        uint16_t name_size = (snapHeader.name_size >> 8) | (snapHeader.name_size << 8);
        uint32_t date_sec = be32toh_manual(snapHeader.date_sec);
        uint64_t vm_clock_nsec = be64toh_manual(snapHeader.vm_clock_nsec);
        uint32_t vm_state_size = be32toh_manual(snapHeader.vm_state_size);
        uint32_t extra_data_size = be32toh_manual(snapHeader.extra_data_size);

        // 跳过额外数据（QCOW2 v3）
        if (version >= 3 && extra_data_size > 0)
        {
            lseek(fd, extra_data_size, SEEK_CUR);
        }

        // P0-04修复: 限制快照名称最大长度，防止OOM攻击
        const size_t MAX_SNAPSHOT_NAME_SIZE = 4096;

        // 读取 ID 字符串
        if (id_str_size > MAX_SNAPSHOT_NAME_SIZE)
        {
            OH_LOG_ERROR(LOG_APP, "Snapshot id_str_size too large: %{public}u", id_str_size);
            break;
        }
        std::string id_str(id_str_size, '\0');
        if (id_str_size > 0 && read(fd, &id_str[0], id_str_size) != id_str_size)
        {
            OH_LOG_ERROR(LOG_APP, "Failed to read snapshot id");
            break;
        }

        // 读取名称
        if (name_size > MAX_SNAPSHOT_NAME_SIZE)
        {
            OH_LOG_ERROR(LOG_APP, "Snapshot name_size too large: %{public}u", name_size);
            break;
        }
        std::string name(name_size, '\0');
        if (name_size > 0 && read(fd, &name[0], name_size) != name_size)
        {
            OH_LOG_ERROR(LOG_APP, "Failed to read snapshot name");
            break;
        }

        // 跳过 padding（对齐到 8 字节）
        size_t header_size = sizeof(QcowSnapshotHeader) + extra_data_size + id_str_size + name_size;
        size_t padding = (8 - (header_size % 8)) % 8;
        if (padding > 0)
        {
            lseek(fd, padding, SEEK_CUR);
        }

        // 转换日期
        char date_str[32];
        time_t t = (time_t)date_sec;
        struct tm *tm_info = localtime(&t);
        strftime(date_str, sizeof(date_str), "%Y-%m-%d %H:%M:%S", tm_info);

        // 转换 VM 时钟
        uint64_t vm_clock_sec = vm_clock_nsec / 1000000000ULL;
        uint32_t hours = vm_clock_sec / 3600;
        uint32_t minutes = (vm_clock_sec % 3600) / 60;
        uint32_t seconds = vm_clock_sec % 60;
        char vm_clock_str[32];
        snprintf(vm_clock_str, sizeof(vm_clock_str), "%02d:%02d:%02d.%03d",
                 hours, minutes, seconds, (int)((vm_clock_nsec % 1000000000ULL) / 1000000));

        if (i > 0)
            json << ",";
        json << "{"
             << "\"id\": " << (i + 1) << ","
             << "\"name\": \"" << name << "\","
             << "\"vm_size\": " << vm_state_size << ","
             << "\"date\": \"" << date_str << "\","
             << "\"vm_clock\": \"" << vm_clock_str << "\""
             << "}";
    }

    json << "]}";
    close(fd);

    return json.str();
}

// NAPI 函数：获取快照列表
static napi_value getSnapshots(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1)
    {
        napi_value result;
        napi_create_string_utf8(env, "{\"error\": \"Missing image path argument\"}", NAPI_AUTO_LENGTH, &result);
        return result;
    }

    std::string imagePath = getString(env, args[0]);
    OH_LOG_INFO(LOG_APP, "getSnapshots called with path: %{public}s", imagePath.c_str());

    std::string output = getSnapshotsFromFile(imagePath);

    napi_value result;
    napi_create_string_utf8(env, output.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

// 前向声明
static napi_value createSnapshot(napi_env env, napi_callback_info info);

// 全局函数指针
static QemuImgEntry g_qemu_img_entry = nullptr;
static void *g_qemu_lib_handle = nullptr;

// 初始化 QEMU 库 (在父进程调用)
static bool initQemuLibrary()
{
    if (g_qemu_img_entry != nullptr)
        return true;

    // 查找库路径
    std::string libPath = "libqemu-img.so";
    Dl_info info;
    if (dladdr((void *)createSnapshot, &info) && info.dli_fname)
    {
        std::string path = info.dli_fname;
        std::vector<char> pathCopy(path.begin(), path.end());
        pathCopy.push_back('\0');
        char *dir = dirname(pathCopy.data());
        libPath = std::string(dir) + "/libqemu-img.so";
    }

    // 加载库
    // 使用 RTLD_GLOBAL 确保符号可见，RTLD_NOW 立即解析
    g_qemu_lib_handle = dlopen(libPath.c_str(), RTLD_LAZY | RTLD_LOCAL);
    if (!g_qemu_lib_handle)
    {
        // 尝试默认路径
        g_qemu_lib_handle = dlopen("libqemu-img.so", RTLD_LAZY | RTLD_LOCAL);
    }

    if (!g_qemu_lib_handle)
    {
        OH_LOG_ERROR(LOG_APP, "Failed to load libqemu-img.so: %{public}s", dlerror());
        return false;
    }

    g_qemu_img_entry = (QemuImgEntry)dlsym(g_qemu_lib_handle, "qemu_img_entry");
    if (!g_qemu_img_entry)
    {
        OH_LOG_ERROR(LOG_APP, "Failed to find qemu_img_entry symbol");
        dlclose(g_qemu_lib_handle);
        g_qemu_lib_handle = nullptr;
        return false;
    }

    OH_LOG_INFO(LOG_APP, "Successfully loaded libqemu-img.so");
    return true;
}

// 执行 qemu-img 命令（使用 fork + 直接调用方式）
static std::string executeQemuImgCommand(const std::vector<std::string> &args)
{
    // 确保库已加载
    if (!initQemuLibrary())
    {
        return "{\"error\": \"Failed to load qemu-img library\"}";
    }

    int pipefd[2];
    if (pipe(pipefd) == -1)
    {
        OH_LOG_ERROR(LOG_APP, "pipe failed: %{public}s", strerror(errno));
        return "{\"error\": \"pipe failed\"}";
    }

    pid_t pid = fork();
    if (pid == -1)
    {
        OH_LOG_ERROR(LOG_APP, "fork failed: %{public}s", strerror(errno));
        close(pipefd[0]);
        close(pipefd[1]);
        return "{\"error\": \"fork failed\"}";
    }

    if (pid == 0)
    {                     // Child process
        close(pipefd[0]); // Close read end

        // Redirect stdout and stderr to pipe
        if (dup2(pipefd[1], STDOUT_FILENO) == -1 || dup2(pipefd[1], STDERR_FILENO) == -1)
        {
            _exit(1);
        }
        close(pipefd[1]); // Close write end after dup

        // Prepare args
        std::vector<const char *> argv;
        for (const auto &arg : args)
        {
            argv.push_back(arg.c_str());
        }

        // Disable buffering
        setbuf(stdout, NULL);
        setbuf(stderr, NULL);

        // Reset signals (important in child)
        signal(SIGPIPE, SIG_DFL);

        // Ignore signals that qemu-img may trigger during shutdown
        // Signal 40, 91, 92 are OHOS-specific signals that can be triggered
        // when qemu-img cleans up resources
        struct sigaction sa;
        sa.sa_handler = SIG_IGN;
        sigemptyset(&sa.sa_mask);
        sa.sa_flags = 0;
        sigaction(40, &sa, nullptr);
        sigaction(91, &sa, nullptr);
        sigaction(92, &sa, nullptr);
        sigaction(89, &sa, nullptr);
        sigaction(90, &sa, nullptr);
        // Call entry point directly
        // Since we forked, we have a copy of the parent's memory state.
        // The library is loaded, and global variables are in the state they were in the parent.
        // Assuming the parent NEVER calls this function, the state is clean.
        int ret = g_qemu_img_entry(argv.size(), argv.data());

        _exit(ret);
    }
    else
    {                     // Parent process
        close(pipefd[1]); // Close write end

        // Read output
        std::string output;
        char buffer[1024];
        ssize_t bytesRead;
        while ((bytesRead = read(pipefd[0], buffer, sizeof(buffer) - 1)) > 0)
        {
            buffer[bytesRead] = '\0';
            output += buffer;
        }
        close(pipefd[0]);

        int status;
        waitpid(pid, &status, 0);

        if (WIFEXITED(status))
        {
            int exit_code = WEXITSTATUS(status);
            if (exit_code != 0)
            {
                OH_LOG_ERROR(LOG_APP, "qemu-img exited with code %{public}d, output: %{public}s", exit_code, output.c_str());

                if (output.find("{") != 0)
                {
                    std::string escaped;
                    for (char c : output)
                    {
                        switch (c) {
                            case '"':  escaped += "\\\""; break;
                            case '\\': escaped += "\\\\"; break;
                            case '\n': escaped += "\\n";  break;
                            case '\r': escaped += "\\r";  break;
                            case '\t': escaped += "\\t";  break;
                            case '\b': escaped += "\\b";  break;
                            case '\f': escaped += "\\f";  break;
                            default:
                                if ((unsigned char)c < 32) {
                                    // 其他不可见控制字符，转义为 \u00xx 格式
                                    char temp[8];
                                    snprintf(temp, sizeof(temp), "\\u%04x", (unsigned char)c);
                                    escaped += temp;
                                } else {
                                    escaped += c;
                                }
                                break;
                        }
                    }
                    if (escaped.empty())
                        escaped = "Unknown error (exit code " + std::to_string(exit_code) + ")";
                    return "{\"error\": \"" + escaped + "\"}";
                }
            }
        }
        else if (WIFSIGNALED(status))
        {
            int sig = WTERMSIG(status);
            // Signal 40, 44, 89-92 are OHOS-specific or Real-Time signals triggered during qemu-img cleanup
            // These usually happen after the work is done, so we treat them as success.
            // Standard crash signals (SEGV, ABRT, etc.) are < 32.
            if (sig >= 32)
            {
                OH_LOG_INFO(LOG_APP, "qemu-img terminated with signal %{public}d (assumed benign cleanup issue)", sig);
                // Continue to success path
            }
            else
            {
                OH_LOG_ERROR(LOG_APP, "qemu-img crashed with signal %{public}d", sig);
                return "{\"error\": \"qemu-img crashed with signal " + std::to_string(sig) + "\"}";
            }
        }

        if (output.empty())
        {
            return "{\"success\": true}";
        }

        if (output.find("{") == 0 || output.find("[") == 0)
        {
            return output;
        }
        else
        {
            OH_LOG_WARN(LOG_APP, "qemu-img success but unexpected output: %{public}s", output.c_str());
            return "{\"success\": true, \"message\": \"" + output + "\"}";
        }
    }
}

// NAPI 函数：创建快照
static napi_value createSnapshot(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 2)
    {
        napi_value result;
        napi_create_string_utf8(env, "{\"error\": \"Missing arguments (imagePath, snapshotName)\"}", NAPI_AUTO_LENGTH, &result);
        return result;
    }

    std::string imagePath = getString(env, args[0]);
    std::string snapshotName = getString(env, args[1]);

    OH_LOG_INFO(LOG_APP, "createSnapshot: path=%{public}s, name=%{public}s", imagePath.c_str(), snapshotName.c_str());

    std::vector<std::string> cmdArgs = {"qemu-img", "snapshot", "-c", snapshotName, imagePath};
    std::string output = executeQemuImgCommand(cmdArgs);

    napi_value result;
    napi_create_string_utf8(env, output.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

// NAPI 函数：恢复快照
static napi_value applySnapshot(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 2)
    {
        napi_value result;
        napi_create_string_utf8(env, "{\"error\": \"Missing arguments (imagePath, snapshotName)\"}", NAPI_AUTO_LENGTH, &result);
        return result;
    }

    std::string imagePath = getString(env, args[0]);
    std::string snapshotName = getString(env, args[1]);

    OH_LOG_INFO(LOG_APP, "applySnapshot: path=%{public}s, name=%{public}s", imagePath.c_str(), snapshotName.c_str());

    std::vector<std::string> cmdArgs = {"qemu-img", "snapshot", "-a", snapshotName, imagePath};
    std::string output = executeQemuImgCommand(cmdArgs);

    napi_value result;
    napi_create_string_utf8(env, output.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

// NAPI 函数：删除快照
static napi_value deleteSnapshot(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 2)
    {
        napi_value result;
        napi_create_string_utf8(env, "{\"error\": \"Missing arguments (imagePath, snapshotName)\"}", NAPI_AUTO_LENGTH, &result);
        return result;
    }

    std::string imagePath = getString(env, args[0]);
    std::string snapshotName = getString(env, args[1]);

    OH_LOG_INFO(LOG_APP, "deleteSnapshot: path=%{public}s, name=%{public}s", imagePath.c_str(), snapshotName.c_str());

    std::vector<std::string> cmdArgs = {"qemu-img", "snapshot", "-d", snapshotName, imagePath};
    std::string output = executeQemuImgCommand(cmdArgs);

    napi_value result;
    napi_create_string_utf8(env, output.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

// NAPI 函数：优化镜像
// mode: "sparse" - 稀疏压缩, "prealloc" - 预分配, "cleanup" - 清理预分配, "optimize" - 仅优化格式参数
static napi_value optimizeImage(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 3)
    {
        napi_value result;
        napi_create_string_utf8(env, "{\"error\": \"Missing arguments (imagePath, outputPath, mode)\"}", NAPI_AUTO_LENGTH, &result);
        return result;
    }

    std::string imagePath = getString(env, args[0]);
    std::string outputPath = getString(env, args[1]);
    std::string mode = getString(env, args[2]);

    OH_LOG_INFO(LOG_APP, "optimizeImage: input=%{public}s, output=%{public}s, mode=%{public}s",
                imagePath.c_str(), outputPath.c_str(), mode.c_str());

    std::vector<std::string> cmdArgs = {"qemu-img", "convert", "-f", "qcow2", "-O", "qcow2"};

    if (mode == "prealloc")
    {
        // 预分配格式（最高性能）
        cmdArgs.push_back("-o");
        cmdArgs.push_back("preallocation=full");
    }
    // sparse, cleanup, optimize 模式不需要 preallocation 参数

    // 所有模式都启用优化参数
    cmdArgs.push_back("-o");
    cmdArgs.push_back("lazy_refcounts=on");
    cmdArgs.push_back("-o");
    cmdArgs.push_back("extended_l2=on");

    cmdArgs.push_back(imagePath);
    cmdArgs.push_back(outputPath);

    std::string output = executeQemuImgCommand(cmdArgs);

    napi_value result;
    napi_create_string_utf8(env, output.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

// NAPI 函数：检查是否需要重启应用
static napi_value needRestart(napi_env env, napi_callback_info info)
{
    napi_value result;
    // Fork 模式不需要重启
    napi_get_boolean(env, false, &result);
    return result;
}

// NAPI 函数：执行任意 qemu-img 命令（用于创建数据盘等操作）
// 参数: args[] - 命令参数数组 (不包含 "qemu-img" 本身)
// 例如: ["create", "-f", "qcow2", "-o", "lazy_refcounts=on,extended_l2=on", "/path/to/disk.qcow2", "1024M"]
static napi_value executeQemuImg(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1)
    {
        napi_value result;
        napi_create_string_utf8(env, "{\"error\": \"Missing arguments array\"}", NAPI_AUTO_LENGTH, &result);
        return result;
    }

    // 检查参数是否为数组
    bool isArray = false;
    napi_is_array(env, args[0], &isArray);
    if (!isArray)
    {
        napi_value result;
        napi_create_string_utf8(env, "{\"error\": \"Argument must be an array\"}", NAPI_AUTO_LENGTH, &result);
        return result;
    }

    // 获取数组长度
    uint32_t arrayLength = 0;
    napi_get_array_length(env, args[0], &arrayLength);

    // 构建命令参数
    std::vector<std::string> cmdArgs;
    cmdArgs.push_back("qemu-img");

    for (uint32_t i = 0; i < arrayLength; i++)
    {
        napi_value element;
        napi_get_element(env, args[0], i, &element);
        cmdArgs.push_back(getString(env, element));
    }

    OH_LOG_INFO(LOG_APP, "executeQemuImg: executing command with %{public}zu args", cmdArgs.size());

    std::string output = executeQemuImgCommand(cmdArgs);

    napi_value result;
    napi_create_string_utf8(env, output.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}


static void call_on_shutdown_callback(napi_env env, napi_value js_callback, void *context, void *data)
{

    napi_value global;
    napi_get_global(env, &global);

    napi_call_function(env, global, js_callback, 0, nullptr, nullptr);
}

static void call_on_data_callback(napi_env env, napi_value js_callback, void *context, void *data)
{

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

std::string convert_to_hex(const uint8_t *buffer, int r)
{
    std::string hex;
    for (int i = 0; i < r; i++)
    {
        if (buffer[i] >= 127 || buffer[i] < 32)
        {
            char temp[8];
            snprintf(temp, sizeof(temp), "\\x%02x", buffer[i]);
            hex += temp;
        }
        else if (buffer[i] == '\'' || buffer[i] == '\"' || buffer[i] == '\\')
        {
            char temp[8];
            snprintf(temp, sizeof(temp), "\\%c", buffer[i]);
            hex += temp;
        }
        else
        {
            hex += (char)buffer[i];
        }
    }
    return hex;
}

void send_data_to_callback(const std::string &hex, napi_threadsafe_function callback)
{
    data_buffer *pbuf = new data_buffer{.buf = new char[hex.length()], .size = (size_t)hex.length()};
    memcpy(pbuf->buf, &hex[0], hex.length());
    napi_call_threadsafe_function(callback, pbuf, napi_tsfn_nonblocking);
}

void on_serial_data_received(const std::string &hex)
{
    if (hex.length() > 0)
    {
        std::lock_guard<std::mutex> lk(buffer_mtx);
        if (on_data_callback != nullptr)
        {
            send_data_to_callback(hex, on_data_callback);
        }
        else
        {
            temp_buffer.append(hex);
        }
    }
}

void serial_output_worker(const char *unix_socket_path)
{

    while (true)
    {
        int acc = access(unix_socket_path, F_OK);
        if (acc == 0)
        {
            break;
        }
        OH_LOG_INFO(LOG_APP, "serial unix socket not exist: %{public}s", unix_socket_path);
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }

    OH_LOG_INFO(LOG_APP, "serial unix socket found: %{public}s", unix_socket_path);

    struct sockaddr_un server_addr;
    int client_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (client_fd == -1)
    {
        OH_LOG_INFO(LOG_APP, "Failed to create unix socket: %{public}d", errno);
        return;
    }

    // Connect to server
    memset(&server_addr, 0, sizeof(struct sockaddr_un));
    server_addr.sun_family = AF_UNIX;
    // P0-03修复: 验证路径长度，防止缓冲区溢出
    size_t path_len = strlen(unix_socket_path);
    if (path_len >= sizeof(server_addr.sun_path))
    {
        OH_LOG_ERROR(LOG_APP, "Unix socket path too long: %{public}zu >= %{public}zu",
                     path_len, sizeof(server_addr.sun_path));
        close(client_fd);
        return;
    }
    strncpy(server_addr.sun_path, unix_socket_path, sizeof(server_addr.sun_path) - 1);

    if (connect(client_fd, (struct sockaddr *)&server_addr, sizeof(struct sockaddr_un)) == -1)
    {
        OH_LOG_INFO(LOG_APP, "Failed to connect to unix socket: %{public}d", errno);
        close(client_fd); // 修复：连接失败时关闭 fd
        return;
    }

    serial_input_fd.store(client_fd);

    OH_LOG_INFO(LOG_APP, "Connected to unix socket: %{public}d", serial_input_fd.load());

    while (true)
    {

        bool broken = false;

        struct pollfd fds[2];
        fds[0].fd = client_fd;
        fds[0].events = POLLIN;
        int res = poll(fds, 1, 100);

        uint8_t buffer[1024];
        for (int i = 0; i < res; i += 1)
        {
            int fd = fds[i].fd;
            ssize_t r = read(fd, buffer, sizeof(buffer) - 1);
            if (r > 0)
            {
                // pretty print
                auto hex = convert_to_hex(buffer, r);
                //  call callback registered by ArkTS
                on_serial_data_received(hex);
                OH_LOG_INFO(LOG_APP, "Received, data: %{public}s", hex.c_str());
            }
            else if (r < 0)
            {
                OH_LOG_INFO(LOG_APP, "Program exited, %{public}ld %{public}d", r, errno);
                broken = true;
            }
            else if (r == 0)
            {
                // EOF: 对端关闭了连接
                OH_LOG_INFO(LOG_APP, "Serial socket EOF - peer closed connection");
                broken = true;
            }
        }

        if (broken)
        {
            break;
        }
    }

    // 清理 socket 资源，但保留回调以便新的 worker 线程使用
    close(client_fd);
    serial_input_fd.store(-1);
    OH_LOG_INFO(LOG_APP, "Closed serial socket fd: %{public}d", client_fd);

    // 注意：不释放 on_data_callback，因为 VM 切换时新的 serial_output_worker 仍需使用它
    // 回调的生命周期由 WebTerminal 组件管理，只要组件存在，回调就有效

    OH_LOG_INFO(LOG_APP, "Serial unix socket broken: %{public}d", errno);
}

std::string getString(napi_env env, napi_value value)
{

    size_t size;
    napi_get_value_string_utf8(env, value, nullptr, 0, &size);

    char *buf = new char[size + 1];
    napi_get_value_string_utf8(env, value, buf, size + 1, &size);
    buf[size] = 0;

    std::string result = buf;
    delete[] buf;

    return result;
}

std::vector<std::string> splitStringByNewline(const std::string &input)
{
    std::vector<std::string> result;
    std::istringstream iss(input);
    std::string line;
    while (std::getline(iss, line))
    {
        result.push_back(line);
    }
    return result;
}

static napi_value startVM(napi_env env, napi_callback_info info)
{

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value key_name;
    napi_value nv_arg_lines;
    napi_value nv_unix_socket;
    napi_value nv_is_pc_device;
    napi_value nv_pid_file_path;

    napi_create_string_utf8(env, "argsLines", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_arg_lines);

    napi_create_string_utf8(env, "unixSocket", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_unix_socket);

    napi_create_string_utf8(env, "isPcDevice", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_is_pc_device);

    napi_create_string_utf8(env, "pidFilePath", NAPI_AUTO_LENGTH, &key_name);
    napi_get_property(env, args[0], key_name, &nv_pid_file_path);

    std::string argsLines = getString(env, nv_arg_lines);
    std::vector<std::string> argsVector = splitStringByNewline(argsLines);

    std::string unixSocket = getString(env, nv_unix_socket);
    std::string pidFilePath = getString(env, nv_pid_file_path);

    bool isPcDevice = false;
    napi_get_value_bool(env, nv_is_pc_device, &isPcDevice);

    OH_LOG_INFO(LOG_APP, "run qemuEntry with: %{public}s, isPcDevice: %{public}d", argsLines.c_str(), isPcDevice);

    if (isPcDevice)
    {
        // PC 设备：使用 fork 子进程运行 QEMU（QEMU 退出不影响主进程）
        OH_LOG_INFO(LOG_APP, "Using fork mode for PC device");

        int pipefd[2];
        if (pipe(pipefd) == -1)
        {
            OH_LOG_ERROR(LOG_APP, "Failed to create pipe: %{public}d", errno);
            return nullptr;
        }

        pid_t pid = fork();
        if (pid < 0)
        {
            OH_LOG_ERROR(LOG_APP, "Failed to fork QEMU process: %{public}d", errno);
            close(pipefd[0]);
            close(pipefd[1]);
            return nullptr;
        }
        else if (pid == 0)
        {
            // 子进程：运行 QEMU
            // 当父进程退出时，子进程自动收到 SIGKILL，确保不会成为孤儿进程
            prctl(PR_SET_PDEATHSIG, SIGKILL);

            close(pipefd[0]); // 关闭读端

            // 重定向 stdout 和 stderr 到管道
            if (dup2(pipefd[1], STDOUT_FILENO) == -1 || dup2(pipefd[1], STDERR_FILENO) == -1)
            {
                _exit(1);
            }
            close(pipefd[1]); // 关闭写端

            // 设置行缓冲，确保输出及时刷新
            setvbuf(stdout, nullptr, _IOLBF, 0);
            setvbuf(stderr, nullptr, _IOLBF, 0);

            const char **argv = new const char *[argsVector.size() + 1];
            for (auto i = 0; i < argsVector.size(); i += 1)
            {
                argv[i] = argsVector[i].c_str();
            }
            argv[argsVector.size()] = nullptr;

            int argc = argsVector.size();

            auto qemuEntry = getQemuSystemEntry();
            qemuEntry(argc, argv);

            delete[] argv;
            _exit(0);
        }
        else
        {
            // 父进程：保存子进程 PID 并启动监控线程
            qemu_child_pid = pid;
            close(pipefd[1]); // 关闭写端

            OH_LOG_INFO(LOG_APP, "QEMU started in child process with PID: %{public}d", pid);

            // 将 PID 写入文件（用于跨重启清理）
            if (!pidFilePath.empty())
            {
                FILE *f = fopen(pidFilePath.c_str(), "w");
                if (f)
                {
                    fprintf(f, "%d", pid);
                    fclose(f);
                    OH_LOG_INFO(LOG_APP, "Wrote PID %{public}d to file: %{public}s", pid, pidFilePath.c_str());
                }
                else
                {
                    OH_LOG_ERROR(LOG_APP, "Failed to write PID file: %{public}s, errno: %{public}d", pidFilePath.c_str(), errno);
                }
            }

            // 启动日志读取线程
            std::thread log_thread([pipefd]()
                                   {
                char buffer[1024];
                ssize_t bytesRead;
                std::string line_buffer;
                
                while ((bytesRead = read(pipefd[0], buffer, sizeof(buffer) - 1)) > 0) {
                    buffer[bytesRead] = '\0';
                    line_buffer += buffer;
                    
                    size_t pos;
                    while ((pos = line_buffer.find('\n')) != std::string::npos) {
                        std::string line = line_buffer.substr(0, pos);
                        if (!line.empty()) {
                            OH_LOG_INFO(LOG_APP, "QEMU: %{public}s", line.c_str());
                        }
                        line_buffer.erase(0, pos + 1);
                    }
                }
                
                if (!line_buffer.empty()) {
                    OH_LOG_INFO(LOG_APP, "QEMU: %{public}s", line_buffer.c_str());
                }
                
                close(pipefd[0]); });
            log_thread.detach();

            std::thread monitor_thread([pid, pidFilePath]()
                                       {
                int status;
                waitpid(pid, &status, 0);
                qemu_child_pid = -1;  // 子进程已退出，清除 PID
                OH_LOG_INFO(LOG_APP, "QEMU child process exited with status: %{public}d", status);
                
                // 删除 PID 文件
                if (!pidFilePath.empty()) {
                    unlink(pidFilePath.c_str());
                    OH_LOG_INFO(LOG_APP, "Deleted PID file on exit: %{public}s", pidFilePath.c_str());
                }
                
                if (on_shutdown_callback != nullptr) {
                    napi_call_threadsafe_function(on_shutdown_callback, nullptr, napi_tsfn_nonblocking);
                } });
            monitor_thread.detach();
        }
    }
    else
    {
        // 非 PC 设备：使用线程运行 QEMU（QEMU 退出会导致应用退出，但这里无法使用 fork）
        OH_LOG_INFO(LOG_APP, "Using thread mode for non-PC device");

        std::thread vm_loop([argsVector]()
                            {
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
            OH_LOG_INFO(LOG_APP, "QEMU shutdown callback triggered, thread ending normally"); });
        vm_loop.detach();
    }

    std::thread worker([=]()
                       { serial_output_worker(unixSocket.c_str()); });
    worker.detach();

    return nullptr;
}

static napi_value sendInput(napi_env env, napi_callback_info info)
{

    if (serial_input_fd.load() < 0)
    {
        return nullptr;
    }

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    uint8_t *data;
    size_t length;
    // P0-01修复: 移除assert，使用显式错误处理
    napi_status ret = napi_get_arraybuffer_info(env, args[0], (void **)&data, &length);
    if (ret != napi_ok)
    {
        OH_LOG_ERROR(LOG_APP, "Failed to get arraybuffer info: %{public}d", ret);
        return nullptr;
    }

    // P0-06修复: 将ret改为length
    std::string hex = convert_to_hex(data, length);
    OH_LOG_INFO(LOG_APP, "Send, data: %{public}s", hex.c_str());

    int written = 0;
    while (written < (int)length)
    {
        // P0-02修复: 移除assert，使用显式错误处理
        int size = write(serial_input_fd.load(), (uint8_t *)data + written, length - written);
        if (size < 0)
        {
            OH_LOG_ERROR(LOG_APP, "Serial write failed: errno=%{public}d", errno);
            break;
        }
        written += size;
    }

    return nullptr;
}

static napi_value onData(napi_env env, napi_callback_info info)
{

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
        if (!temp_buffer.empty())
        {
            send_data_to_callback(temp_buffer, data_callback);
            temp_buffer.clear();
        }
        // P1-14修复: 将设置移入锁保护范围内
        on_data_callback = data_callback;
    }

    return nullptr;
}

static napi_value onShutdown(napi_env env, napi_callback_info info)
{

    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value data_cb_name;
    napi_create_string_utf8(env, "shutdown_callback", NAPI_AUTO_LENGTH, &data_cb_name);
    napi_create_threadsafe_function(env, args[0], nullptr, data_cb_name, 0, 1, nullptr, nullptr, nullptr,
                                    call_on_shutdown_callback, &on_shutdown_callback);

    return nullptr;
}

static napi_value bool_from_int(napi_env env, int v)
{
    napi_value result;
    napi_get_boolean(env, v != 0, &result);
    return result;
}

static napi_value checkPortUsed(napi_env env, napi_callback_info info)
{

    napi_status status;

    size_t argc = 1;
    napi_value argv[1];
    status = napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
    if (status != napi_ok)
    {
        return bool_from_int(env, 1);
    }

    if (argc < 1)
    {
        return bool_from_int(env, 1);
    }

    // Ensure the argument is a number
    napi_valuetype vt;
    status = napi_typeof(env, argv[0], &vt);
    if (status != napi_ok || (vt != napi_number))
    {
        return bool_from_int(env, 1);
    }

    double port_d;
    status = napi_get_value_double(env, argv[0], &port_d);
    if (status != napi_ok)
    {
        return bool_from_int(env, 1);
    }

    if (!(port_d >= 0 && port_d <= 65535))
    {
        return bool_from_int(env, 1);
    }

    int port = (int)port_d;

    // Create an IPv4 TCP socket
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0)
    {
        return bool_from_int(env, 1);
    }

    int v = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &v, sizeof(v));

    // Prepare sockaddr_in for binding to INADDR_ANY:port
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = htonl(INADDR_ANY);
    sa.sin_port = htons((uint16_t)port);

    int bind_res = bind(sock, (struct sockaddr *)&sa, sizeof(sa));
    if (bind_res == 0)
    {
        close(sock);
        return bool_from_int(env, 0);
    }
    else
    {
        int err = errno;
        close(sock);
        if (err == EADDRINUSE)
        {
            return bool_from_int(env, 1);
        }
        else if (err == EACCES)
        {
            return bool_from_int(env, 1);
        }
        else
        {
            return bool_from_int(env, 1);
        }
    }
}

// NAPI 函数：获取 CPU 架构版本
// 返回 "v85" 或 "generic"
static napi_value getCpuArchVersion(napi_env env, napi_callback_info info)
{
    std::string version = detectArmArchVersion();

    napi_value result;
    napi_create_string_utf8(env, version.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

// 杀死 QEMU 子进程 (PC 模式下使用)
// 接受一个参数: pidFilePath (PID 文件路径)
static napi_value killQemuProcess(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string pidFilePath;
    if (argc >= 1)
    {
        pidFilePath = getString(env, args[0]);
    }

    pid_t pid_to_kill = -1;

    // 优先从内存中获取 PID
    if (qemu_child_pid > 0)
    {
        pid_to_kill = qemu_child_pid;
        OH_LOG_INFO(LOG_APP, "Using in-memory PID: %{public}d", pid_to_kill);
    }
    // 如果内存中没有，尝试从文件读取
    else if (!pidFilePath.empty())
    {
        FILE *f = fopen(pidFilePath.c_str(), "r");
        if (f)
        {
            int pid_from_file = 0;
            if (fscanf(f, "%d", &pid_from_file) == 1 && pid_from_file > 0)
            {
                pid_to_kill = pid_from_file;
                OH_LOG_INFO(LOG_APP, "Read PID from file %{public}s: %{public}d", pidFilePath.c_str(), pid_to_kill);
            }
            fclose(f);
        }
    }

    if (pid_to_kill > 0)
    {
        // P1-05修复: 发送信号前验证进程名称，防止杀错重用 PID 的进程
        char cmdPath[64];
        snprintf(cmdPath, sizeof(cmdPath), "/proc/%d/cmdline", pid_to_kill);
        FILE *cmdFile = fopen(cmdPath, "r");
        if (cmdFile)
        {
            char cmdline[256] = {0};
            fread(cmdline, 1, sizeof(cmdline) - 1, cmdFile);
            fclose(cmdFile);
            if (strstr(cmdline, "qemu") == nullptr)
            {
                OH_LOG_WARN(LOG_APP, "PID %{public}d exists but is not a QEMU process (cmdline: %{public}s). Skipping kill.", pid_to_kill, cmdline);
                return nullptr;
            }
        }
        else
        {
            OH_LOG_WARN(LOG_APP, "Failed to open %{public}s to verify PID %{public}d, errno: %{public}d", cmdPath, pid_to_kill, errno);
            // 如果无法打开 cmdline（可能是权限问题或进程刚退出），为了安全起见，不执行 kill
            return nullptr;
        }

        OH_LOG_INFO(LOG_APP, "===== Start cleanup QEMU process (PID: %{public}d) =====", pid_to_kill);

        // 发送 SIGTERM，等待进程优雅退出
        int result = kill(pid_to_kill, SIGTERM);
        if (result == 0)
        {
            OH_LOG_INFO(LOG_APP, "SIGTERM sent, waiting for graceful exit...");
            usleep(1500000); // 1.5 秒（原来 500ms）

            // 检查进程是否还在运行
            result = kill(pid_to_kill, 0);
            if (result == 0)
            {
                // 进程还在，使用 SIGKILL 强制杀死
                OH_LOG_INFO(LOG_APP, "Process still running, sending SIGKILL");
                kill(pid_to_kill, SIGKILL);
                usleep(500000); // 等待 SIGKILL 生效

                // 二次验证进程是否已退出
                result = kill(pid_to_kill, 0);
                if (result == 0)
                {
                    OH_LOG_WARN(LOG_APP, "Process still exists after SIGKILL!");
                }
                else
                {
                    OH_LOG_INFO(LOG_APP, "Process terminated by SIGKILL");
                }
            }
            else
            {
                OH_LOG_INFO(LOG_APP, "Process exited gracefully");
            }
        }
        else
        {
            // SIGTERM 失败（可能进程已不存在），尝试 SIGKILL
            OH_LOG_WARN(LOG_APP, "SIGTERM failed (errno: %{public}d), trying SIGKILL", errno);
            kill(pid_to_kill, SIGKILL);
            usleep(500000); // 500ms
        }

        // 阻塞等待收割 zombie，最多尝试 10 次
        int status;
        int max_attempts = 10;
        bool reaped = false;

        OH_LOG_INFO(LOG_APP, "Reaping zombie process...");
        for (int i = 0; i < max_attempts; i++)
        {
            pid_t wait_result = waitpid(pid_to_kill, &status, WNOHANG);
            if (wait_result > 0)
            {
                OH_LOG_INFO(LOG_APP, "Reaped process %{public}d (status: %{public}d, attempt: %{public}d/%{public}d)",
                            wait_result, status, i + 1, max_attempts);
                reaped = true;
                break;
            }
            else if (wait_result == 0)
            {
                // 进程还在运行，等待 100ms 后重试
                OH_LOG_INFO(LOG_APP, "Process still running, retry %{public}d/%{public}d...", i + 1, max_attempts);
                usleep(100000); // 100ms
            }
            else
            {
                // waitpid 出错
                if (errno == ECHILD)
                {
                    OH_LOG_INFO(LOG_APP, "Process already gone (ECHILD)");
                }
                else
                {
                    OH_LOG_INFO(LOG_APP, "waitpid error: %{public}d (errno: %{public}d)", wait_result, errno);
                }
                reaped = true;
                break;
            }
        }

        if (!reaped)
        {
            OH_LOG_WARN(LOG_APP, "Failed to reap process, will be cleaned by prctl");
        }

        qemu_child_pid = -1;

        // 删除 PID 文件
        if (!pidFilePath.empty())
        {
            unlink(pidFilePath.c_str());
            OH_LOG_INFO(LOG_APP, "Deleted PID file: %{public}s", pidFilePath.c_str());
        }

        OH_LOG_INFO(LOG_APP, "===== QEMU process cleanup complete =====");
    }
    else
    {
        OH_LOG_INFO(LOG_APP, "No QEMU process to cleanup");
    }

    return nullptr;
}

// 检查 QEMU 进程是否存活
// 接受一个参数: pidFilePath (PID 文件路径)
// 返回: boolean (true 表示进程存活, false 表示进程已退出)
static napi_value checkQemuAlive(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string pidFilePath;
    if (argc >= 1)
    {
        pidFilePath = getString(env, args[0]);
    }

    pid_t pid_to_check = -1;

    // 优先从内存中获取 PID
    if (qemu_child_pid > 0)
    {
        pid_to_check = qemu_child_pid;
    }
    // 如果内存中没有，尝试从文件读取
    else if (!pidFilePath.empty())
    {
        FILE *f = fopen(pidFilePath.c_str(), "r");
        if (f)
        {
            int pid_from_file = 0;
            if (fscanf(f, "%d", &pid_from_file) == 1 && pid_from_file > 0)
            {
                pid_to_check = pid_from_file;
            }
            fclose(f);
        }
    }

    if (pid_to_check <= 0)
    {
        // 没有 PID 信息，认为进程不存在
        return bool_from_int(env, 0);
    }

    // 使用 kill(pid, 0) 检测进程是否存活
    int result = kill(pid_to_check, 0);
    if (result == 0)
    {
        // 进程存活
        return bool_from_int(env, 1);
    }
    else
    {
        // 进程不存在或无权限
        return bool_from_int(env, 0);
    }
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"startVM", nullptr, startVM, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"onData", nullptr, onData, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"onShutdown", nullptr, onShutdown, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"sendInput", nullptr, sendInput, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"checkPortUsed", nullptr, checkPortUsed, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getImageInfo", nullptr, getImageInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
        // 快照管理功能
        {"getSnapshots", nullptr, getSnapshots, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"createSnapshot", nullptr, createSnapshot, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"applySnapshot", nullptr, applySnapshot, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"deleteSnapshot", nullptr, deleteSnapshot, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"optimizeImage", nullptr, optimizeImage, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"needRestart", nullptr, needRestart, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"killQemuProcess", nullptr, killQemuProcess, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"checkQemuAlive", nullptr, checkQemuAlive, nullptr, nullptr, nullptr, napi_default, nullptr},
        // 数据盘管理
        {"executeQemuImg", nullptr, executeQemuImg, nullptr, nullptr, nullptr, napi_default, nullptr},      
        // ARM 架构版本检测
        {"getCpuArchVersion", nullptr, getCpuArchVersion, nullptr, nullptr, nullptr, napi_default, nullptr}};
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
