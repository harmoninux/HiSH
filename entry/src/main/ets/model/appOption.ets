import preference from '@ohos.data.preferences';

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
  static defaultStartEmulator = 'defaultStartEmulator'
  static currentRunningEmulator = 'currentRunningEmulator'
  static temporaryStartEmulator = 'temporaryStartEmulator'
}

interface PortMapping {
  guest?: number
  host?: number
}

async function savePreference(key: string, value: object | string | boolean, context: UIContext) {
  const appContext = context.getHostContext()!!.getApplicationContext();
  const appPref: preference.Preferences = await preference.getPreferences(appContext, appOption.preferenceName);
  if (value instanceof Object) {
    await appPref.put(key, JSON.stringify(value));
  } else {
    await appPref.put(key, value)
  }
  await appPref.flush();
}

export default appOption

export { PortMapping, savePreference }