import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import preference from '@ohos.data.preferences';
import fs from '@ohos.file.fs';
import { deviceInfo } from '@kit.BasicServicesKit';
import bundleManager from '@ohos.bundle.bundleManager';
import appOption from '../model/appOption'
import napi from 'libentry.so';
import { startVm } from '../lib/startVm';
import { defaultEmulator, defaultRootfs, Emulator, PortMapping, RootFilesystem } from '../model/Emulator';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
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

    await this.startDefaultEmulator(appContext);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');

      let mainWindow = windowStage.getMainWindowSync();
      mainWindow.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      mainWindow.setWindowKeepScreenOn(AppStorage.get(appOption.keepScreenOn) as boolean);

      AppStorage.setOrCreate('mainWindow', mainWindow)

      if (canIUse('SystemCapability.Window.SessionManager')
        && deviceInfo.deviceType === '2in1') {
        mainWindow.setWindowDecorVisible(false);
        mainWindow.setWindowDecorHeight(48);
      }
    });
  }

  private async startDefaultEmulator(appContext: common.ApplicationContext) {

    const defaultStart: string | undefined = AppStorage.get(appOption.defaultStartEmulator) as string

    const emulators = AppStorage.get(appOption.emulators) as Emulator[]

    const defaultEmulator = emulators.find(it => it.id === defaultStart)

    if (!defaultEmulator) {
      return
    }

    const cpuCount = defaultEmulator.cpu;
    const memSize = defaultEmulator.memory;
    const rootFilesystem = defaultEmulator.rootFilesystem
    const sharedFolderReadonly = defaultEmulator.sharedFolderReadonly
    const portMappingRaw = defaultEmulator.portMapping
    const init = defaultEmulator.init

    const sharedFolder = AppStorage.get(appOption.sharedHost) as string

    const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string
    const kernelFile = AppStorage.get(appOption.kernel) as string

    const portMapping: PortMapping[] = []
    const portUsed: number[] = []
    const candidates = portMappingRaw
    for (let i = 0; i < candidates.length; i++) {
      let item = candidates[i];
      let port: number = item.host!!;
      const used = napi.checkPortUsed(port)
      if (!used) {
        portMapping.push(item)
      } else {
        portUsed.push(port)
        hilog.info(DOMAIN, 'testTag', 'host port %{public}d of PortMapping is used by others', port)
      }
    }

    AppStorage.setOrCreate(appOption.portUsedByOthers, portUsed)

    hilog.info(DOMAIN, 'testTag', 'startVM with cpu: %{public}d, mem: %{public}dMB, portMapping: %{public}s',
      cpuCount, memSize, portMapping)

    const serialUnixSocket = appContext.tempDir + '/serial_socket'

    AppStorage.setOrCreate(appOption.currentRunningEmulator, defaultEmulator.id)

    startVm({
      baseDir: vmBaseDir,
      cpu: cpuCount,
      memory: memSize,
      portMapping: portMapping,
      kernel: kernelFile,
      rootFilesystem,
      sharedFolder,
      serialUnixSocket,
      sharedFolderReadonly,
      init
    })
  }

  private async loadPreferences(appContext: common.ApplicationContext) {

    const appPref: preference.Preferences = await preference.getPreferences(appContext, appOption.preferenceName);

    const keepScreenOn = await appPref.get(appOption.keepScreenOn, false) as boolean;
    AppStorage.setOrCreate(appOption.keepScreenOn, keepScreenOn);

    defaultRootfs.path = defaultRootfs.path.startsWith('/')
      ? defaultRootfs.path
      : appContext.filesDir + '/' + defaultRootfs.path
    defaultEmulator.rootFilesystem = defaultEmulator.rootFilesystem.startsWith('/')
      ? defaultEmulator.rootFilesystem
      : appContext.filesDir + '/' + defaultEmulator.rootFilesystem

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

    hilog.info(DOMAIN, 'testTag',
      'extractResourcesForVM, filesDir: %{public}s, tempDir: %{public}s',
      appContext.filesDir, appContext.tempDir);

    const vmBaseDir = appContext.filesDir + "/vm";
    const rootfsBaseDir = appContext.filesDir + "/roots";

    const sharedGuest = '/mnt/share'
    const sharedHost = appContext.filesDir + '/' + 'share'
    const rootFilesystem = vmBaseDir + '/' + 'rootfs_aarch64.qcow2'
    AppStorage.setOrCreate(appOption.vmBaseDir, vmBaseDir)
    AppStorage.setOrCreate(appOption.rootfsBaseDir, rootfsBaseDir)
    AppStorage.setOrCreate(appOption.sharedGuest, sharedGuest)
    AppStorage.setOrCreate(appOption.sharedHost, sharedHost)
    AppStorage.setOrCreate(appOption.rootFilesystem, rootFilesystem)
    AppStorage.setOrCreate(appOption.kernel, vmBaseDir + '/kernel_aarch64')

    if (!fs.accessSync(vmBaseDir, fs.AccessModeType.EXIST)) {
      fs.mkdirSync(vmBaseDir);
    }
    if (!fs.accessSync(rootfsBaseDir, fs.AccessModeType.EXIST)) {
      fs.mkdirSync(rootfsBaseDir);
    }

    this.extractVmResourceFile(appContext, 'vm/rootfs_aarch64.qcow2', 'roots/rootfs_aarch64.qcow2');
    this.extractVmResourceFile(appContext, 'vm/kernel_aarch64', 'vm/kernel_aarch64');
    this.extractVmResourceFile(appContext, 'vm/efi-virtio.rom', 'vm/efi-virtio.rom');
    this.extractVmResourceFile(appContext, 'vm/rootfs_aarch64.qcow2', 'vm/rootfs_aarch64.qcow2');
  }

  private extractVmResourceFile(appContext: common.ApplicationContext, filename: string, toFileName: string) {
    let filePath = appContext.filesDir + "/" + toFileName;
    if (!fs.accessSync(filePath, fs.AccessModeType.EXIST)) {
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

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}