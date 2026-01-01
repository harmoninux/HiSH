export type NapiVmOptions = {
  argsLines: string
  unixSocket: string
  qmpSocket: string
  isPcDevice: boolean
  pidFilePath: string  // PID 文件路径，用于跨重启清理
}

export const startVM: (options: NapiVmOptions) => void;

export const onData: (callback: (data: ArrayBuffer) => void) => void;

export const onShutdown: (callback: () => void) => void;

export const sendInput: (content: ArrayBuffer) => void;

export const checkPortUsed: (port: number) => boolean;

/**
 * 获取 QCOW2 镜像的详细信息
 * @param imagePath 镜像文件的完整路径
 * @returns JSON 格式的镜像信息字符串
 */
export const getImageInfo: (imagePath: string) => string;

// ================== 快照管理功能 ==================

/**
 * 获取 QCOW2 镜像的快照列表
 * @param imagePath 镜像文件的完整路径
 * @returns JSON 格式的快照列表 {snapshots: [{id, name, vm_size, date, vm_clock}]}
 */
export const getSnapshots: (imagePath: string) => string;

/**
 * 创建快照
 * @param imagePath 镜像文件的完整路径
 * @param snapshotName 快照名称
 * @returns JSON 格式的结果 {success: true} 或 {error: string, need_restart?: boolean}
 */
export const createSnapshot: (imagePath: string, snapshotName: string) => string;

/**
 * 恢复快照
 * @param imagePath 镜像文件的完整路径
 * @param snapshotName 快照名称
 * @returns JSON 格式的结果
 */
export const applySnapshot: (imagePath: string, snapshotName: string) => string;

/**
 * 删除快照
 * @param imagePath 镜像文件的完整路径
 * @param snapshotName 快照名称
 * @returns JSON 格式的结果
 */
export const deleteSnapshot: (imagePath: string, snapshotName: string) => string;

/**
 * 优化镜像
 * @param imagePath 输入镜像文件路径
 * @param outputPath 输出镜像文件路径
 * @param mode 优化模式: 'sparse' (稀疏压缩), 'prealloc' (预分配), 'cleanup' (清理预分配), 'optimize' (仅优化格式参数)
 * @returns JSON 格式的结果
 */
export const optimizeImage: (imagePath: string, outputPath: string, mode: 'sparse' | 'prealloc' | 'cleanup' | 'optimize') => string;

/**
 * 检查是否需要重启应用
 * @returns 如果 qemu-img 操作失败需要重启则返回 true
 */
export const needRestart: () => boolean;

/**
 * 杀死 QEMU 子进程 (PC 模式下使用)
 * 在应用关闭时调用，确保 QEMU 进程被正确清理
 * @param pidFilePath PID 文件路径，如果内存中没有 PID 则从文件读取
 */
export const killQemuProcess: (pidFilePath?: string) => void;

