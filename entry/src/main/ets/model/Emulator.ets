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
  sharedFolder: string | undefined
}

export { Emulator, PortMapping }