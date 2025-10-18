import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import preference from '@ohos.data.preferences';
import fs from '@ohos.file.fs';
import { deviceInfo } from '@kit.BasicServicesKit';
import bundleManager from '@ohos.bundle.bundleManager';
import appOption, { PortMapping } from '../model/appOption'

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

    const appContext = this.context.getApplicationContext();
    const appPref: preference.Preferences = await preference.getPreferences(appContext, appOption.preferenceName);

    await this.extractResourcesForVM(appContext, appPref);

    await this.loadPreferences(appPref);

    const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
    AppStorage.setOrCreate('versionCode', bundleInfo.versionCode)
    AppStorage.setOrCreate('versionName', bundleInfo.versionName)

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

  private async loadPreferences(appPref: preference.Preferences) {
    const vmCpuCount = await appPref.get(appOption.cpuCountName, 1);
    const vmMemSize = await appPref.get(appOption.memSizeName, 512);
    const keepScreenOn = await appPref.get(appOption.keepScreenOn, false) as boolean;
    const portMappingEnabled = await appPref.get(appOption.portMappingEnabled, false) as boolean;
    const portMapping = JSON.parse(await appPref.get(appOption.portMapping, '[]') as string) as PortMapping[];
    AppStorage.setOrCreate(appOption.cpuCountName, vmCpuCount);
    AppStorage.setOrCreate(appOption.memSizeName, vmMemSize);
    AppStorage.setOrCreate(appOption.keepScreenOn, keepScreenOn);
    AppStorage.setOrCreate(appOption.portMappingEnabled, portMappingEnabled);
    AppStorage.setOrCreate(appOption.portMapping, portMapping);
  }

  private async extractResourcesForVM(appContext: common.ApplicationContext, appPref: preference.Preferences) : Promise<void> {

    const reset: boolean = await this.getResetFlag(appPref)

    hilog.info(DOMAIN, 'testTag',
      'extractResourcesForVM, filesDir: %{public}s, tempDir: %{public}s, reset: %{public}s',
      appContext.filesDir, appContext.tempDir, reset);

    let bundleVmDir = appContext.filesDir + "/vm";
    if (!fs.accessSync(bundleVmDir, fs.AccessModeType.EXIST)) {
      fs.mkdirSync(bundleVmDir);
    }
    for (let filename of ["vm/rootfs_aarch64.qcow2", "vm/kernel_aarch64", "vm/efi-virtio.rom"]) {

      let filePath = appContext.filesDir + "/" + filename;
      if (fs.accessSync(filePath, fs.AccessModeType.EXIST) && !reset) {
        continue;
      }

      let value: Uint8Array = appContext.resourceManager.getRawFileContentSync(filename);
      let file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.writeSync(file.fd, value.buffer);
      fs.closeSync(file);
      hilog.info(DOMAIN, 'testTag', 'Extract resource file: %{public}s', filePath);
    }
  }

  private async getResetFlag(appPref: preference.Preferences): Promise<boolean> {
    const flag = await appPref.get(appOption.resetLinuxFlag, false) as boolean
    await appPref.delete(appOption.resetLinuxFlag)
    await appPref.flush()
    return flag
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