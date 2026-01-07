import preference from '@ohos.data.preferences';

type CursorShape = 'BLOCK' | 'BEAM' | 'UNDERLINE'

class appOption {
  static preferenceName = 'vm_pref'
  static keepScreenOn = 'appKeepScreenOn'
  static terminalFontSize = 'terminalFontSize'
  static terminalCursorBlink = 'terminalCursorBlink'
  static terminalCursorShape = 'terminalCursorShape'
  static appTempDir = 'appTempDir'
  static appFilesDir = 'appFilesDir'
  static vmBaseDir = 'vmBaseDir'
  static rootfsBaseDir = 'rootfsBaseDir'
  static sharedGuest = 'sharedGuest'
  static sharedHost = 'sharedHost'
  static kernel = 'kernel'
  static portUsedByOthers = 'portUsedByOthers'
  static emulators = 'emulators'
  static rootFilesystems = 'rootFilesystems'
  static defaultStartEmulator = 'defaultStartEmulator'
  static currentRunningEmulator = 'currentRunningEmulator'
  static currentEmulatorStatus = 'currentEmulatorStatus'
  static bundleInfo = 'bundleInfo'
  static temporaryStartEmulator = 'temporaryStartEmulator'
  static serialChannel = 'serialChannel'
  static lastResourceVersion = 'lastResourceVersion';
  static runningInBackground = 'runningInBackground';
  static showVirtKey = 'showVirtKey';
  static isPowerManagementOpen = 'isPowerManagementOpen';
  static vncEnabled = 'vncEnabled';
  // qemu-img 后台任务状态
  static qemuImgTaskRunning = 'qemuImgTaskRunning';
  static qemuImgTaskDescription = 'qemuImgTaskDescription';
  // VM 切换标志，防止 shutdown 回调覆盖状态
  static isVmSwitching = 'isVmSwitching';
  // ARM CPU 架构版本 ('v85' 或 'generic')
  static cpuArchVersion = 'cpuArchVersion';

  // Terminal Features
  static terminalEffects = 'terminalEffects'
  static terminalTransparency = 'terminalTransparency'
  static terminalScreensaver = 'terminalScreensaver'
  static terminalEffectType = 'terminalEffectType'

  // 数据盘管理
  static dataDisks = 'dataDisks'           // 数据盘列表
}

async function savePreference(key: string, value: object | string | boolean | number, context: UIContext) {
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

export { savePreference, CursorShape }
