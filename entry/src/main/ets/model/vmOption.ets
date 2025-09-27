class vmOption {
  static preferenceName = 'vm_pref'
  static cpuCountName = 'vmCpuCount'
  static memSizeName = 'vmMemSize'
  static portMappingEnabled = 'vmPortMappingEnabled'
  static portMapping = 'vmPortMapping'
}

interface PortMapping {
  guest?: number
  host?: number
}

export default vmOption

export { PortMapping }