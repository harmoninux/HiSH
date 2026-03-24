export type NapiVmOptions = {
  argsLines: string
  unixSocket: string
  qmpSocket: string
}

export const startVM: (options: NapiVmOptions) => boolean;

export const onData: (callback: (ArrayBuffer) => void) => void;

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

// ================== VNC Viewer Functions ==================

/**
 * VNC 更新处理
 * @param onResize 回调函数，当 VNC 缓冲区大小改变时调用
 * @param onUpdate 回调函数，当 VNC 有新的帧更新时调用
 * @returns 返回值表示消息处理状态
 */
export const vncUpdate: (
  onResize: (size: number) => ArrayBuffer,
  onUpdate: (updateInfo: Uint8Array) => void
) => number;

/**
 * 初始化 VNC 连接
 * @param address VNC 服务器地址
 * @param port VNC 端口
 * @param password VNC 密码（可为空）
 * @returns ArrayBuffer 类型的帧缓冲区，连接失败时返回 null
 */
export const vncInit: (address: string, port: number, password: string) => ArrayBuffer | null;

/**
 * 关闭 VNC 连接
 * @returns 0 表示成功
 */
export const vncClose: () => number;

/**
 * 发送鼠标事件到 VNC 服务器
 * @param x 鼠标 X 坐标
 * @param y 鼠标 Y 坐标
 * @param buttonMask 按钮掩码（RFB_BUTTON1-5）
 */
export const vncMouseEvent: (x: number, y: number, buttonMask: number) => void;

/**
 * 发送键盘事件到 VNC 服务器
 * @param key RFB 按键码（X11 keysym）
 * @param down true 表示按下，false 表示释放
司 */
export const vncKeyEvent: (key: number, down: boolean) => void;