import preference from '@ohos.data.preferences';

type CursorShape = 'BLOCK' | 'BEAM' | 'UNDERLINE'

class AppOption {
  static readonly preferenceName: string = 'vm_pref'
  static readonly keepScreenOn: string = 'appKeepScreenOn'
  static readonly terminalFontSize: string = 'terminalFontSize'
  static readonly terminalCursorBlink: string = 'terminalCursorBlink'
  static readonly terminalCursorShape: string = 'terminalCursorShape'
  static readonly terminalTheme: string = 'terminalTheme'
  static readonly terminalFont: string = 'terminalFont'
  static readonly customTheme: string = 'customTheme'
  static readonly customFont: string = 'customFont'
  static readonly autoSnapshotOnExit: string = 'autoSnapshotOnExit'
  static readonly performanceProfile: string = 'performanceProfile'
  static readonly appTempDir: string = 'appTempDir'
  static readonly appFilesDir: string = 'appFilesDir'
  static readonly vmBaseDir: string = 'vmBaseDir'
  static readonly rootfsBaseDir: string = 'rootfsBaseDir'
  static readonly sharedGuest: string = 'sharedGuest'
  static readonly sharedHost: string = 'sharedHost'
  static readonly kernel: string = 'kernel'
  static readonly portUsedByOthers: string = 'portUsedByOthers'
  static readonly emulators: string = 'emulators'
  static readonly rootFilesystems: string = 'rootFilesystems'
  static readonly defaultStartEmulator: string = 'defaultStartEmulator'
  static readonly currentRunningEmulator: string = 'currentRunningEmulator'
  static readonly currentEmulatorStatus: string = 'currentEmulatorStatus'
  static readonly bundleInfo: string = 'bundleInfo'
  static readonly temporaryStartEmulator: string = 'temporaryStartEmulator'
  static readonly serialChannel: string = 'serialChannel'
  static readonly lastResourceVersion: string = 'lastResourceVersion'
  static readonly runningInBackground: string = 'runningInBackground'
  static readonly displayStatusBar: string = 'displayStatusBar'
  static readonly showVirtKey: string = 'showVirtKey'
  static readonly isPowerManagementOpen: string = 'isPowerManagementOpen'
  static readonly vncEnabled: string = 'vncEnabled'
  static readonly vncPortMode: string = 'vncPortMode'
  static readonly vncPort: string = 'vncPort'
  static readonly qemuImgTaskRunning: string = 'qemuImgTaskRunning'
  static readonly qemuImgTaskDescription: string = 'qemuImgTaskDescription'
  static readonly isQgaConnected: string = 'isQgaConnected'
}

let cachedPref: preference.Preferences | null = null
let debounceTimer: number | null = null
const pendingWrites = new Map<string, object | string | boolean | number>()

async function getPref(context: UIContext): Promise<preference.Preferences> {
  if (cachedPref === null) {
    const appContext = context.getHostContext()!!.getApplicationContext()
    cachedPref = await preference.getPreferences(appContext, AppOption.preferenceName)
  }
  return cachedPref
}

function flushWrites(): void {
  if (debounceTimer !== null || pendingWrites.size === 0) {
    return
  }
  // 收集 50ms 内的所有写入，批量 flush
  debounceTimer = setTimeout(async () => {
    debounceTimer = null
    if (cachedPref === null || pendingWrites.size === 0) {
      return
    }
    // 使用 for...of 替代 forEach，确保异步写入顺序执行并等待完成
    for (const entry of pendingWrites.entries()) {
      const key = entry[0]
      const value = entry[1]
      if (value instanceof Object) {
        await cachedPref.put(key, JSON.stringify(value))
      } else {
        await cachedPref.put(key, value as string | boolean | number)
      }
    }
    pendingWrites.clear()
    await cachedPref.flush()
  }, 50)
}

/**
 * 取消待执行的 flush 定时器（用于组件销毁时清理）
 */
function cancelFlushWrites(): void {
  if (debounceTimer !== null) {
    clearTimeout(debounceTimer)
    debounceTimer = null
  }
}

/**
 * 清除缓存的 Preferences 实例（用于应用热重载等场景）
 */
function clearCachedPref(): void {
  cachedPref = null
  cancelFlushWrites()
}

async function savePreference(key: string, value: object | string | boolean | number, context: UIContext) {
  await getPref(context)
  pendingWrites.set(key, value)
  flushWrites()
}

export default AppOption

export { savePreference, CursorShape, cancelFlushWrites, clearCachedPref }