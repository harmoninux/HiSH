class appOption {
  static preferenceName = 'vm_pref'
  static cpuCountName = 'vmCpuCount'
  static memSizeName = 'vmMemSize'
  static portMappingEnabled = 'vmPortMappingEnabled'
  static portMapping = 'vmPortMapping'
  static keepScreenOn = 'appKeepScreenOn'
  static resetLinuxFlag = 'resetLinuxAtStart'
}

interface PortMapping {
  guest?: number
  host?: number
}

export default appOption

export { PortMapping }