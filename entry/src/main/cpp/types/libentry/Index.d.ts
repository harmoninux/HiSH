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

// ================== VNC Functions (XComponent + OpenGL) ==================

/**
 * 初始化 VNC 连接
 * @param address VNC 服务器地址
 * @param port VNC 端口
 * @param password VNC 密码（可为空）
 * @returns 连接是否成功
 */
export const vncInit: (address: string, port: number, password: string) => boolean;

/**
 * 关闭 VNC 连接并停止渲染
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
 * @param keyCode 鸿蒙按键码
 * @param down true 表示按下，false 表示释放
 */
export const vncKeyEvent: (keyCode: number, down: boolean) => void;

/**
 * VNC 轮询结果
 */
export interface VncPollResult {
  status: number;
  fbWidth: number;
  fbHeight: number;
}

/**
 * 启动 VNC 更新轮询循环（在后台线程中轮询 VNC 消息并触发 OpenGL 渲染）
 * @param onStatusUpdate 状态更新回调
 * @returns 是否成功启动
 */
export const vncStartUpdateLoop: (onStatusUpdate: (result: VncPollResult) => void) => boolean;

/**
 * 停止 VNC 更新轮询循环
 */
export const vncStopUpdateLoop: () => void;

/**
 * 创建 VNC 渲染表面（使用 XComponent 的 surfaceId）
 * @param surfaceId XComponent 提供的 surface ID
 * @returns 是否成功创建
 */
export const vncCreateSurface: (surfaceId: bigint) => boolean;

/**
 * 调整 VNC 渲染表面大小
 * @param surfaceId XComponent 的 surface ID
 * @param width 宽度
 * @param height 高度
 * @returns 0 表示成功
 */
export const vncResizeSurface: (surfaceId: bigint, width: number, height: number) => number;

/**
 * 销毁 VNC 渲染表面
 * @returns 0 表示成功
 */
export const vncDestroySurface: () => number;

/**
 * 渲染脏帧（在 JS 线程执行 GL 渲染）
 * 由 TSFN 回调触发，将 VNC framebuffer 更新绘制到 EGL surface
 */
export const vncRenderFrame: () => void;
