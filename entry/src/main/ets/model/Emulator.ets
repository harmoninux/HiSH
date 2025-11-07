interface PortMapping {
  guest?: number
  host?: number
}

interface RootFilesystem {
  id: string
  name: string
  path: string
}

interface Emulator {
  id: string
  name: string,
  cpu: number,
  memory: number,
  networking: boolean
  init: string | undefined
  portMapping: PortMapping[]
  rootFilesystem: string
}

//  TODO: use uri
const defaultRootfs: RootFilesystem = {
  id: '63233e0f84ed4efa8901c0d617aae884',
  name: 'Alpine Linux',
  path: 'rootfs_aarch64.qcow2'
}

const defaultEmulator: Emulator = {
  id: '316ebe3596344e9d8b0a6c1a9bc840d2',
  name: '默认模拟器',
  cpu: 1,
  memory: 512,
  networking: true,
  init: '/init',
  portMapping: [],
  rootFilesystem: 'rootfs_aarch64.qcow2'
}

export { Emulator, PortMapping, defaultEmulator, defaultRootfs }