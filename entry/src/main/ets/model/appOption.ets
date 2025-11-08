class appOption {
  static preferenceName = 'vm_pref'
  static cpuCountName = 'vmCpuCount'
  static memSizeName = 'vmMemSize'
  static portMappingEnabled = 'vmPortMappingEnabled'
  static portMapping = 'vmPortMapping'
  static keepScreenOn = 'appKeepScreenOn'
  static resetLinuxFlag = 'resetLinuxAtStart'
  static use9pRootFs = 'use9pRootFs'

  static vmBaseDir = 'vmBaseDir'
  static rootfsBaseDir = 'rootfsBaseDir'
  static sharedGuest = 'sharedGuest'
  static sharedHost = 'sharedHost'
  static rootFilesystem = 'rootFilesystem'
  static kernel = 'kernel'
  static portUsedByOthers = 'portUsedByOthers'

  static emulators = 'emulators'
  static rootFilesystems = 'rootFilesystems'
}

interface PortMapping {
  guest?: number
  host?: number
}

export default appOption

export { PortMapping }