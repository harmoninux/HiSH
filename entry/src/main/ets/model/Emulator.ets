interface PortMapping {
  guest?: number
  host?: number
}

interface RootFilesystem {
  id: string
  name: string
  path: string
}

// 数据盘接口
interface DataDisk {
  id: string       // UUID，文件名前缀
  name: string     // 用户定义的名称
  path: string     // 完整文件路径
}

interface Emulator {
  id: string
  name: string,
  cpu: number,
  memory: number,
  init: string
  portMapping: PortMapping[]
  rootVda: string,
  rootFilesystem: string
  sharedFolderReadonly: boolean
  // 数据盘相关字段
  dataDiskId?: string     // 关联的数据盘 ID（可选）
  mountDataDisk: boolean  // 是否在启动时挂载数据盘
}

const defaultRootfs: RootFilesystem = {
  id: 'rootfs_aarch64',
  name: 'Alpine Linux',
  path: 'roots/rootfs_aarch64.qcow2'
}

const defaultEmulator: Emulator = {
  id: 'rootfs_aarch64',
  name: '默认模拟器',
  cpu: 1,
  memory: 512,
  init: '/init',
  portMapping: [],
  rootVda: '/dev/sda',
  rootFilesystem: 'vm/rootfs_aarch64.qcow2',
  sharedFolderReadonly: false,
  mountDataDisk: false
}

export { Emulator, PortMapping, RootFilesystem, DataDisk, defaultEmulator, defaultRootfs }
