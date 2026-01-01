import { AbilityConstant, ConfigurationConstant, UIAbility, Want, abilityAccessCtrl } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, KeyboardAvoidMode, PromptAction, UIContext } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import preference from '@ohos.data.preferences';
import fs from '@ohos.file.fs';
import { deviceInfo } from '@kit.BasicServicesKit';
import bundleManager from '@ohos.bundle.bundleManager';
import napi from 'libentry.so';
import appOption, { CursorShape } from '../model/appOption'
import { startVm } from '../lib/startVm';
import { defaultEmulator, defaultRootfs, Emulator, RootFilesystem } from '../model/Emulator';
import { util } from '@kit.ArkTS';
import { fileUri, picker } from '@kit.CoreFileKit';
import { backgroundRunningManager } from '../lib/backgroundRunningManager';
import { startQmpEventListener, stopQmpEventListener, QmpEventType, QmpEventData } from '../lib/QmpEventListener';
import QemuAgent from '../lib/QemuAgent';

const DOMAIN = 0x0000;

// 窗口大小变化防抖定时器
let windowResizeTimer: number = -1;
// resize 专用的 QGA 连接（独立于 QemuAgentManager，避免冲突）
let resizeAgent: QemuAgent | null = null;
// resize 操作锁，避免并发
let isResizing: boolean = false;

interface StartResult {
  portsSkipped: number[]
}

/**
 * 获取一个未被占用的随机端口 (用于 VNC WebSocket)
 * @param min 最小端口号 (包含)
 * @param max 最大端口号 (包含)
 * @returns 可用端口号，如果找不到则返回 undefined
 */
function getFreeVncPort(min: number, max: number): number | undefined {
  const range = max - min + 1;
  const maxAttempts = 100; // 最大尝试次数
  
  for (let i = 0; i < maxAttempts; i++) {
    const port = min + Math.floor(Math.random() * range);
    if (!napi.checkPortUsed(port)) {
      return port;
    }
  }
  
  hilog.warn(DOMAIN, 'testTag', 'Could not find a free VNC port after %{public}d attempts', maxAttempts);
  return undefined;
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    
    // 清理窗口大小变化防抖定时器
    if (windowResizeTimer !== -1) {
      clearTimeout(windowResizeTimer);
      windowResizeTimer = -1;
    }
    
    // 断开 resizeAgent 连接
    if (resizeAgent) {
      resizeAgent.disconnect().catch(() => { /* 忽略错误 */ });
      resizeAgent = null;
    }
    
    // 停止 QMP 事件监听器
    stopQmpEventListener().catch((e: Error): void => {
      hilog.warn(DOMAIN, 'testTag', 'Failed to stop QMP event listener: %{public}s', e.message);
    });
    
    // 杀死 QEMU 子进程（PC 模式下）
    try {
      const pidFilePath = this.context.filesDir + '/qemu.pid';
      napi.killQemuProcess(pidFilePath);
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'Failed to kill QEMU process: %{public}s', JSON.stringify(e));
    }
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    const bundleInfo =
      await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
    AppStorage.setOrCreate('bundleInfo', bundleInfo)

    const appContext = this.context.getApplicationContext();

    // 申请剪贴板权限
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      atManager.requestPermissionsFromUser(this.context, ['ohos.permission.READ_PASTEBOARD']).then((data) => {
        hilog.info(DOMAIN, 'testTag', 'requestPermissionsFromUser result: %{public}s', JSON.stringify(data));
      }).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'requestPermissionsFromUser failed: %{public}s', JSON.stringify(err));
      })
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'requestPermissionsFromUser catch err: %{public}s', JSON.stringify(err));
    }

    await this.loadPreferences(appContext);

    await this.extractKernelAndRootFilesystem(appContext);

    windowStage.loadContent('pages/Index', async (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');

      const mainWindow = windowStage.getMainWindowSync();
      const uiContext = mainWindow.getUIContext();
      uiContext.setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      mainWindow.setWindowKeepScreenOn(AppStorage.get(appOption.keepScreenOn) as boolean);

      AppStorage.setOrCreate('mainWindow', mainWindow)

      if (canIUse('SystemCapability.Window.SessionManager')
        && deviceInfo.deviceType === '2in1') {
        mainWindow.setWindowDecorVisible(false);
        mainWindow.setWindowDecorHeight(48);
      }

      // 监听窗口大小变化
      this.registerWindowSizeChangeListener(mainWindow);

      await this.prepareForSharedFolder(appContext)
      const result = this.startDefaultEmulator()

      this.promptRootVdaMessage(uiContext)
      this.promptPortUsedMessage(uiContext, result.portsSkipped)
      this.startRunInBackground(uiContext)
    });
  }

  async prepareForSharedFolder(appContext: common.ApplicationContext) {

    const sharedGuest = '/mnt/share'

    const documentViewPicker = new picker.DocumentViewPicker()
    let documentSaveResult = await documentViewPicker.save({ pickerMode: picker.DocumentPickerMode.DOWNLOAD })
    const sharedHost = new fileUri.FileUri(documentSaveResult[0]).path + '/'

    //  曾经使用 oldSharedHost 作为共享文件夹，现将内容迁移到新的 sharedHost
    const oldSharedHost = appContext.filesDir + '/' + 'share'
    await this.moveToNewSharedFolder(oldSharedHost, sharedHost);

    AppStorage.setOrCreate(appOption.sharedHost, sharedHost)
    AppStorage.setOrCreate(appOption.sharedGuest, sharedGuest)
  }

  private startDefaultEmulator(): StartResult {

    const appTempDir = AppStorage.get(appOption.appTempDir)!!

    const emulatorToStart = this.getEmulatorToStart();

    const cpuCount = emulatorToStart.cpu;
    const memSize = emulatorToStart.memory;
    const rootVda = emulatorToStart.rootVda;
    const rootFilesystem = emulatorToStart.rootFilesystem
    const sharedFolderReadonly = emulatorToStart.sharedFolderReadonly
    const portMappingRaw = emulatorToStart.portMapping
    const init = emulatorToStart.init

    const sharedFolder = AppStorage.get(appOption.sharedHost) as string

    const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string
    const kernelFile = AppStorage.get(appOption.kernel) as string

    const portUsed = portMappingRaw.map(it => it.host!!).filter(p => napi.checkPortUsed(p))
    const portMapping = portMappingRaw.filter(it => portUsed.indexOf(it.host!!) < 0)

    hilog.info(DOMAIN, 'testTag', 'host port %{public}s of PortMapping is used by others', portUsed)
    AppStorage.setOrCreate(appOption.portUsedByOthers, portUsed)

    hilog.info(DOMAIN, 'testTag', 'startVM with cpu: %{public}d, mem: %{public}dMB, portMapping: %{public}s',
      cpuCount, memSize, portMapping)

    const serialUnixSocket = appTempDir + '/serial_socket'
    const qmpUnixSocket = appTempDir + '/qmp_socket'
    const qmpUnixSocketUI = appTempDir + '/qmp_socket_ui'
    const qgaUnixSocket = appTempDir + '/qga_socket'

    AppStorage.setOrCreate(appOption.currentRunningEmulator, emulatorToStart.id)
    AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')

    // 获取随机 VNC 端口 (60000-65000)
    const vncPort = getFreeVncPort(60000, 65000);
    if (vncPort) {
      AppStorage.setOrCreate('vncWebSocketPort', vncPort);
      hilog.info(DOMAIN, 'testTag', 'VNC WebSocket port: %{public}d', vncPort);
    } else {
      hilog.warn(DOMAIN, 'testTag', 'No free VNC port found, VNC will be disabled');
    }

    startVm({
      baseDir: vmBaseDir,
      cpu: cpuCount,
      memory: memSize,
      portMapping: portMapping,
      kernel: kernelFile,
      rootVda,
      rootFilesystem,
      sharedFolder,
      serialUnixSocket,
      sharedFolderReadonly,
      init,
      qmpUnixSocket,
      qmpUnixSocketUI,
      qgaUnixSocket,
      vncWebSocketPort: vncPort
    })

    // 启动 QMP 事件监听器，监控虚拟机状态变化
    this.startQmpEventMonitor(qmpUnixSocketUI)

    return { portsSkipped: portUsed }
  }

  /**
   * 启动 QMP 事件监控
   * 监听虚拟机的 SHUTDOWN、RESET 等事件
   */
  private async startQmpEventMonitor(qmpSocketPath: string): Promise<void> {
    // 延迟启动，等待 QEMU 完成初始化（增加到 5 秒以确保 socket 文件已创建）
    hilog.info(DOMAIN, 'testTag', '准备启动 QMP 事件监听器，socket 路径: %{public}s', qmpSocketPath)
    
    setTimeout(async (): Promise<void> => {
      try {
        hilog.info(DOMAIN, 'testTag', '开始连接 QMP Socket...')
        const started = await startQmpEventListener(qmpSocketPath, 
          (event: QmpEventType, data: QmpEventData | undefined): void => {
            hilog.info(DOMAIN, 'testTag', '===== QMP 事件回调触发 =====')
            this.handleQmpEvent(event, data)
          }
        )
        
        if (started) {
          hilog.info(DOMAIN, 'testTag', '✓ QMP 事件监听器已成功启动')
        } else {
          hilog.warn(DOMAIN, 'testTag', '✗ QMP 事件监听器启动失败，将在后台重试')
        }
      } catch (e) {
        hilog.error(DOMAIN, 'testTag', '启动 QMP 事件监听器异常: %{public}s', JSON.stringify(e))
      }
    }, 5000)  // 增加延迟到 5 秒
  }

  /**
   * 处理 QMP 事件
   */
  private handleQmpEvent(event: QmpEventType, data: QmpEventData | undefined): void {
    hilog.info(DOMAIN, 'testTag', '收到 QMP 事件: %{public}s, 数据: %{public}s', 
               event, JSON.stringify(data))
    
    switch (event) {
      case 'SHUTDOWN':
        // 虚拟机关机
        hilog.info(DOMAIN, 'testTag', '虚拟机已关机 (来源: %{public}s)', 
                   data?.guest ? 'guest' : 'host')
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN')
        // 清除当前运行的模拟器 ID，这样模拟器管理界面会显示为"未运行"
        AppStorage.setOrCreate(appOption.currentRunningEmulator, '')
        break
        
      case 'POWERDOWN':
        // 收到 ACPI 关机信号
        hilog.info(DOMAIN, 'testTag', '收到 ACPI 关机信号')
        // POWERDOWN 事件通常在 SHUTDOWN 之前发送，不需要立即更新状态
        break
        
      case 'RESET':
        // 虚拟机重置
        hilog.info(DOMAIN, 'testTag', '虚拟机正在重置')
        // 断开 resizeAgent 连接，等待下次使用时重新建立
        if (resizeAgent) {
          resizeAgent.disconnect().catch(() => { /* 忽略错误 */ });
          resizeAgent = null;
        }
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'REBOOTING')
        break
        
      case 'STOP':
        // 虚拟机暂停
        hilog.info(DOMAIN, 'testTag', '虚拟机已暂停')
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'PAUSED')
        break
        
      case 'RESUME':
        // 虚拟机恢复运行
        hilog.info(DOMAIN, 'testTag', '虚拟机已恢复运行')
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')
        break
        
      case 'GUEST_PANICKED':
        // 虚拟机内核崩溃
        hilog.error(DOMAIN, 'testTag', '虚拟机内核崩溃!')
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'ABNORMAL')
        // 异常状态也清除运行中标记
        AppStorage.setOrCreate(appOption.currentRunningEmulator, '')
        break
        
      default:
        hilog.info(DOMAIN, 'testTag', '未处理的 QMP 事件: %{public}s', event)
    }
  }

  /**
   * 注册窗口大小变化监听器
   * 当窗口大小变化时，通过 QGA 在虚拟机内执行 resize 命令
   */
  private registerWindowSizeChangeListener(mainWindow: window.Window): void {
    try {
      mainWindow.on('windowSizeChange', (size: window.Size): void => {
        hilog.info(DOMAIN, 'testTag', 'Window size changed: %{public}d x %{public}d', size.width, size.height)
        
        // 防抖处理：避免频繁调用
        if (windowResizeTimer !== -1) {
          clearTimeout(windowResizeTimer)
        }
        
        windowResizeTimer = setTimeout((): void => {
          this.tryQgaResizeOnWindowChange()
        }, 300)  // 300ms 防抖
      })
      
      hilog.info(DOMAIN, 'testTag', 'Window size change listener registered')
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'Failed to register window size change listener: %{public}s', JSON.stringify(e))
    }
  }

  /**
   * 窗口大小变化时尝试通过 QGA 执行 resize 命令
   * 使用独立的 QemuAgent 实例，完全不干扰 QemuAgentManager 管理的连接
   */
  private async tryQgaResizeOnWindowChange(): Promise<void> {
    // 避免并发执行
    if (isResizing) {
      hilog.info(DOMAIN, 'testTag', 'resize 正在进行中，跳过')
      return
    }
    
    // 检查虚拟机状态
    const vmStatus = AppStorage.get(appOption.currentEmulatorStatus) as string
    if (vmStatus !== 'RUNNING') {
      hilog.info(DOMAIN, 'testTag', '虚拟机未运行 (状态: %{public}s)，跳过 resize', vmStatus)
      return
    }
    
    const appTempDir = AppStorage.get(appOption.appTempDir) as string
    if (!appTempDir) {
      hilog.info(DOMAIN, 'testTag', 'appTempDir 未设置，跳过 resize')
      return
    }
    
    isResizing = true
    hilog.info(DOMAIN, 'testTag', '开始尝试 QGA resize...')
    
    try {
      const qgaSocket = appTempDir + '/qga_socket'
      
      // 创建独立的 QemuAgent 实例（不通过 QemuAgentManager）
      resizeAgent = new QemuAgent(qgaSocket)
      
      // 设置较短的连接超时
      const connectPromise = resizeAgent.connect()
      const timeoutPromise: Promise<boolean> = new Promise<boolean>((resolve: (value: boolean) => void): void => {
        setTimeout((): void => resolve(false), 500)
      })
      
      const connected = await Promise.race([connectPromise, timeoutPromise])
      
      if (!connected) {
        hilog.info(DOMAIN, 'testTag', 'QGA 连接超时或失败，跳过 resize')
        if (resizeAgent) {
          try { await resizeAgent.disconnect() } catch (e) { /* 忽略 */ }
          resizeAgent = null
        }
        return
      }
      
      hilog.info(DOMAIN, 'testTag', 'QGA 独立连接成功，执行 resize 命令')
      
      // 直接执行 resize 命令
      const pid = await resizeAgent.exec('/bin/sh', ['-c', 'resize >/dev/null 2>&1'])
      
      if (pid !== null) {
        hilog.info(DOMAIN, 'testTag', 'Resize window!')
      } else {
        hilog.info(DOMAIN, 'testTag', 'resize 命令执行失败 (pid=null)')
      }
      
      // 断开独立连接
      try { await resizeAgent.disconnect() } catch (e) { /* 忽略 */ }
      resizeAgent = null
      
    } catch (e) {
      hilog.info(DOMAIN, 'testTag', '通过 QGA 执行 resize 异常: %{public}s', JSON.stringify(e))
      // 确保断开连接
      if (resizeAgent) {
        try { await resizeAgent.disconnect() } catch (disconnectErr) { /* 忽略 */ }
        resizeAgent = null
      }
    } finally {
      isResizing = false
    }
  }

  private getEmulatorToStart() {
    const temporaryStart: string | undefined = AppStorage.get(appOption.temporaryStartEmulator) as string;
    const defaultStart: string | undefined = temporaryStart || AppStorage.get(appOption.defaultStartEmulator) as string;
    const emulators = AppStorage.get(appOption.emulators) as Emulator[];
    const emulatorToStart = emulators.find(it => it.id === defaultStart)!!;
    return emulatorToStart;
  }

  private async loadPreferences(appContext: common.ApplicationContext) {

    const appTempDir: string = appContext.tempDir;
    const appFilesDir: string = appContext.filesDir;
    AppStorage.setOrCreate(appOption.appTempDir, appTempDir)
    AppStorage.setOrCreate(appOption.appFilesDir, appFilesDir)

    defaultRootfs.path = defaultRootfs.path.startsWith('/')
      ? defaultRootfs.path
      : appFilesDir + '/' + defaultRootfs.path
    defaultEmulator.rootFilesystem = defaultEmulator.rootFilesystem.startsWith('/')
      ? defaultEmulator.rootFilesystem
      : appFilesDir + '/' + defaultEmulator.rootFilesystem

    const appPref: preference.Preferences = await preference.getPreferences(appContext, appOption.preferenceName);

    const temporaryStart = await this.getAndClearTemporaryStartEmulator(appPref)
    if (temporaryStart) {
      AppStorage.setOrCreate(appOption.temporaryStartEmulator, temporaryStart)
    }

    const keepScreenOn = await appPref.get(appOption.keepScreenOn, false) as boolean;
    AppStorage.setOrCreate(appOption.keepScreenOn, keepScreenOn);
    const showVirtKey = await appPref.get(appOption.showVirtKey, true) as boolean;
    AppStorage.setOrCreate(appOption.showVirtKey, showVirtKey);
    const runningInBackground = await appPref.get(appOption.runningInBackground, false) as boolean;
    AppStorage.setOrCreate(appOption.runningInBackground, runningInBackground);
    const terminalFontSize = await appPref.get(appOption.terminalFontSize, this.getDefaultTerminalFontSize()) as number;
    AppStorage.setOrCreate(appOption.terminalFontSize, terminalFontSize);
    const terminalCursorShape = await appPref.get(appOption.terminalCursorShape, 'BLOCK') as CursorShape;
    AppStorage.setOrCreate(appOption.terminalCursorShape, terminalCursorShape);
    const terminalCursorBlink = await appPref.get(appOption.terminalCursorBlink, false) as boolean;
    AppStorage.setOrCreate(appOption.terminalCursorBlink, terminalCursorBlink);

    const defaultStart = await appPref.get(appOption.defaultStartEmulator, undefined) as (string | undefined)
    AppStorage.setOrCreate(appOption.defaultStartEmulator, defaultStart || defaultEmulator.id)

    const emulators =
      JSON.parse(await appPref.get(appOption.emulators, JSON.stringify([defaultEmulator])) as string) as Emulator[]
    AppStorage.setOrCreate(appOption.emulators, emulators)
    const rootFilesystems =
      JSON.parse(await appPref.get(appOption.rootFilesystems,
        JSON.stringify([defaultRootfs])) as string) as RootFilesystem[]
    AppStorage.setOrCreate(appOption.rootFilesystems, rootFilesystems)
  }

  private async extractKernelAndRootFilesystem(appContext: common.ApplicationContext): Promise<void> {

    const filesDir = AppStorage.get(appOption.appFilesDir)!!

    hilog.info(DOMAIN, 'testTag',
      'extractResourcesForVM, filesDir: %{public}s, tempDir: %{public}s',
      appContext.filesDir, appContext.tempDir);

    const vmBaseDir = filesDir + "/vm";
    const rootfsBaseDir = filesDir + "/roots";

    AppStorage.setOrCreate(appOption.vmBaseDir, vmBaseDir)
    AppStorage.setOrCreate(appOption.rootfsBaseDir, rootfsBaseDir)
    AppStorage.setOrCreate(appOption.kernel, vmBaseDir + '/kernel_aarch64')

    if (!fs.accessSync(vmBaseDir, fs.AccessModeType.EXIST)) {
      fs.mkdirSync(vmBaseDir);
    }
    if (!fs.accessSync(rootfsBaseDir, fs.AccessModeType.EXIST)) {
      fs.mkdirSync(rootfsBaseDir);
    }

    const appPref: preference.Preferences = await preference.getPreferences(appContext, appOption.preferenceName);
    const lastResourceVersion = await appPref.get(appOption.lastResourceVersion, undefined) as number | undefined
    const bundleInfo = AppStorage.get('bundleInfo') as bundleManager.BundleInfo
    const forceOverride = lastResourceVersion === undefined
      || lastResourceVersion < bundleInfo.versionCode
      || bundleInfo.name.startsWith('dev.hackeris')
    this.extractVmResourceFile(appContext, 'vm/rootfs_aarch64.qcow2', 'roots/rootfs_aarch64.qcow2', forceOverride);
    this.extractVmResourceFile(appContext, 'vm/kernel_aarch64', 'vm/kernel_aarch64', forceOverride);
    this.extractVmResourceFile(appContext, 'vm/efi-virtio.rom', 'vm/efi-virtio.rom', forceOverride);
    
    // 确保 keymaps 目录存在
    const keymapsDir = vmBaseDir + '/keymaps';
    if (!fs.accessSync(keymapsDir, fs.AccessModeType.EXIST)) {
      fs.mkdirSync(keymapsDir);
    }
    // 尝试提取到 vm/keymaps/en-us (标准路径)
    this.extractVmResourceFile(appContext, 'vm/keymaps/en-us', 'vm/keymaps/en-us', forceOverride);
    // 同时提取到 vm/en-us (备用路径)
    this.extractVmResourceFile(appContext, 'vm/keymaps/en-us', 'vm/en-us', forceOverride);
    
    // 验证文件是否存在及大小
    const keymapPath = vmBaseDir + '/keymaps/en-us';
    const keymapPath2 = vmBaseDir + '/en-us';
    try {
      const stat1 = fs.statSync(keymapPath);
      hilog.info(DOMAIN, 'testTag', 'Keymap check - %{public}s: EXISTS, size=%{public}d', keymapPath, stat1.size);
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'Keymap check - %{public}s: MISSING or ERROR: %{public}s', keymapPath, JSON.stringify(e));
    }
    try {
      const stat2 = fs.statSync(keymapPath2);
      hilog.info(DOMAIN, 'testTag', 'Keymap check - %{public}s: EXISTS, size=%{public}d', keymapPath2, stat2.size);
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'Keymap check - %{public}s: MISSING or ERROR: %{public}s', keymapPath2, JSON.stringify(e));
    }
    await appPref.put(appOption.lastResourceVersion, bundleInfo.versionCode)
    await appPref.flush()

    const defaultStartEmulator = AppStorage.get(appOption.defaultStartEmulator)!! as string
    if (defaultStartEmulator === defaultEmulator.id) {
      this.extractVmResourceFile(appContext, 'vm/rootfs_aarch64.qcow2', defaultEmulator.rootFilesystem);
    }
  }

  private extractVmResourceFile(appContext: common.ApplicationContext, filename: string, toFileName: string,
    forceOverride?: boolean) {
    const filesDir = AppStorage.get(appOption.appFilesDir)!!
    const filePath = toFileName.startsWith('/') ? toFileName : (filesDir + "/" + toFileName);
    if (!fs.accessSync(filePath, fs.AccessModeType.EXIST) || forceOverride) {
      let value: Uint8Array = appContext.resourceManager.getRawFileContentSync(filename);
      let file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.writeSync(file.fd, value.buffer);
      fs.closeSync(file);
      hilog.info(DOMAIN, 'testTag', 'Extract resource file: %{public}s', filePath);
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  async onForeground() {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');

    const runningInBackground = AppStorage.get(appOption.runningInBackground) as boolean || false
    if (runningInBackground) {
      await backgroundRunningManager.stopBackground(this.context)
    }
  }

  async onBackground() {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    const runningInBackground = AppStorage.get(appOption.runningInBackground) as boolean || false
    if (runningInBackground) {
      const success = await backgroundRunningManager.startBackground(this.context)
      if (!success) {
        const window = AppStorage.get('mainWindow')!! as window.Window
        window.getUIContext().getPromptAction().showToast({
          message: $r('app.string.failed_to_force_background'),
          duration: 3000
        })
      }
    }
  }

  private async getAndClearTemporaryStartEmulator(appPref: preference.Preferences) {
    const temporaryStart = await appPref.get(appOption.temporaryStartEmulator, undefined) as string | undefined;
    appPref.deleteSync(appOption.temporaryStartEmulator);
    appPref.flush();
    return temporaryStart;
  }

  private getDefaultTerminalFontSize(): number {
    if (deviceInfo.deviceType === 'phone'
      || deviceInfo.deviceType === 'default') {
      return 11;
    } else if (deviceInfo.deviceType === 'tablet') {
      return 13;
    }
    return 15;
  }

  private promptPortUsedMessage(uiContext: UIContext, portSkipped: number[]) {
    const promptFormat = uiContext.getHostContext()?.resourceManager.getStringByNameSync('port_used_prompt');
    if (portSkipped.length > 0) {
      try {
        const ports = portSkipped.map(i => i.toString()).join(',');
        const prompt = util.format(promptFormat, ports);
        const promptAction: PromptAction = uiContext.getPromptAction();
        promptAction.showToast({
          message: prompt,
          duration: 5000
        });
      } catch (e) {
        hilog.error(DOMAIN, 'testTag', 'showToast error: %{public}s', JSON.stringify(e));
      }
    }
  }

  private promptRootVdaMessage(uiContext: UIContext) {
    const emulatorToStart = this.getEmulatorToStart();
    if (emulatorToStart.rootVda
      && emulatorToStart.rootVda.startsWith('/dev/vda')) {
      try {
        const promptFormat = uiContext.getHostContext()?.resourceManager.getStringByNameSync('root_outdated_prompt');
        const prompt = util.format(promptFormat, emulatorToStart.rootVda)
        const promptAction: PromptAction = uiContext.getPromptAction();
        promptAction.showToast({
          message: prompt,
          duration: 10000
        });
      } catch (e) {
        hilog.error(DOMAIN, 'testTag', 'showToast error: %{public}s', JSON.stringify(e));
      }
    }
  }

  private async moveToNewSharedFolder(oldSharedHost: string, sharedHost: string) {
    try {
      if (await fs.access(oldSharedHost, fs.AccessModeType.EXIST)) {
        const dirEntries = await fs.listFile(oldSharedHost, { recursion: false });
        if (dirEntries.length > 0) {
          for (let i = 0; i < dirEntries.length; i++) {
            const entry = dirEntries[i];
            const src: string = [oldSharedHost, entry].join('/')
            const dst: string = [sharedHost, entry].join('/')
            const s = await fs.stat(src)
            if (s.isFile()) {
              await fs.moveFile(src, dst)
            } else if (s.isDirectory()) {
              await fs.moveDir(src, sharedHost, 2)
            }
          }
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, 'testTag', '迁移共享文件夹失败: %{public}s', JSON.stringify(e))
    }
  }

  private async startRunInBackground(uiContext: UIContext) {
    try {
      const runInBackground = AppStorage.get(appOption.runningInBackground) as boolean
      if (runInBackground) {
        await backgroundRunningManager.grantLocationPermission(uiContext.getHostContext() as common.UIAbilityContext)
      }
    } catch (e) {
      uiContext.getPromptAction().showToast({
        message: $r('app.string.failed_to_force_background'),
        duration: 3000
      })
    }
  }
}