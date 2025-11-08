interface PortMapping {
  guest?: number
  host?: number
}

interface RootFilesystem {
  id: string
  name: string
  //  相对路径
  path: string
}

interface Emulator {
  id: string
  name: string,
  cpu: number,
  memory: number,
  networking: boolean
  init: string
  portMapping: PortMapping[]
  rootFilesystem: string
  sharedFolderReadonly: boolean
}

//  TODO: use uri
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
  networking: true,
  init: '/init',
  portMapping: [],
  rootFilesystem: 'vm/rootfs_aarch64.qcow2',
  sharedFolderReadonly: false
}

export { Emulator, PortMapping, RootFilesystem, defaultEmulator, defaultRootfs }