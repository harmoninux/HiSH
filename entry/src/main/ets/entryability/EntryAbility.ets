import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
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

const DOMAIN = 0x0000;

interface StartResult {
  portsSkipped: number[]
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    // 杀死 QEMU 子进程（PC 模式下）
    try {
      napi.killQemuProcess();
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
      qgaUnixSocket
    })

    return { portsSkipped: portUsed }
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

    // ARM 架构检测和内核选择
    const cpuArchVersion = napi.getCpuArchVersion();
    AppStorage.setOrCreate(appOption.cpuArchVersion, cpuArchVersion);
    hilog.info(DOMAIN, 'HiSH', '=== ARM CPU Feature Detection ===');
    hilog.info(DOMAIN, 'HiSH', 'CPU Arch Version: %{public}s', cpuArchVersion);

    // 根据架构版本选择内核
    const kernelResourcePath = cpuArchVersion === 'v85' ? 'vm/kernel_aarch64' : 'vm/kernel_aarch64_v82';
    hilog.info(DOMAIN, 'HiSH', 'Kernel: %{public}s', kernelResourcePath);
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
    // 使用根据架构版本选择的内核
    this.extractVmResourceFile(appContext, kernelResourcePath, 'vm/kernel_aarch64', forceOverride);
    this.extractVmResourceFile(appContext, 'vm/efi-virtio.rom', 'vm/efi-virtio.rom', forceOverride);
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