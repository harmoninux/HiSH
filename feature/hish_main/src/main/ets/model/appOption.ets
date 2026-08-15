import preference from '@ohos.data.preferences';

type CursorShape = 'BLOCK' | 'BEAM' | 'UNDERLINE'

/**
 * 用户上传的自定义终端字体
 * name: 显示名称（取自原文件名）
 * file: 字体文件的绝对路径（位于应用 filesDir 下）
 */
interface UserFont {
  name: string
  file: string
}

/**
 * 传给 WebView 的字体数据（内容为 base64 data URL）
 */
interface UserFontData {
  name: string
  dataUrl: string
}

class appOption {
  static preferenceName = 'vm_pref'
  static keepScreenOn = 'appKeepScreenOn'
  static terminalFontSize = 'terminalFontSize'
  static terminalFontFamily = 'terminalFontFamily'    // Current font family selection
  static availableFontFamilies = 'availableFontFamilies' // Detected available monospace fonts
  static terminalCursorBlink = 'terminalCursorBlink'
  static terminalCursorShape = 'terminalCursorShape'
  static terminalLigatures = 'terminalLigatures'   // 连字开关
  static terminalItalic = 'terminalItalic'         // 斜体开关
  static terminalBackgroundColor = 'terminalBackgroundColor'   // 终端背景色 (如 '#000000')
  static terminalBackgroundImage = 'terminalBackgroundImage' // 背景图片文件名 (位于 filesDir/terminal_bg 下)
  static terminalBackgroundBlur = 'terminalBackgroundBlur'   // 背景高斯模糊半径 (px)
  static terminalUserFonts = 'terminalUserFonts'   // 用户上传字体列表 (JSON: UserFont[])
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
  static displayStatusBar = 'displayStatusBar';
  static showVirtKey = 'showVirtKey';
  static isPowerManagementOpen = 'isPowerManagementOpen';
  static vncEnabled = 'vncEnabled';
  static vncPortMode = 'vncPortMode'; // 'local' | 'lan'
  static vncPort = 'vncPort';         // VNC port number (e.g. 5900)
  // qemu-img 后台任务状态
  static qemuImgTaskRunning = 'qemuImgTaskRunning';
  static qemuImgTaskDescription = 'qemuImgTaskDescription';
  // QGA 连接状态 (Global Truth)
  static isQgaConnected = 'isQgaConnected';
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

export { savePreference, CursorShape, UserFont, UserFontData }