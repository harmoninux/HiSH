import { CustomContentDialog, window } from '@kit.ArkUI';
import { LinkItem } from "./LinkItem"
import { bundleManager, common, Want } from '@kit.AbilityKit';
import preference from '@ohos.data.preferences';
import appOption from '../model/appOption';
import { SharedFolderContent } from './SharedFolderContent';
import { PortMappingContent } from './PortMappingContent';
import { OpenSourceContent } from './OpenSourceContent';

@Component
struct BlockTitle {
  content?: string | Resource

  build() {
    Text(this.content)
      .margin({ bottom: 10, left: 20 })
      .width('100%')
  }
}

@Extend(Column)
function settingBlockStyle() {
  .borderRadius(20)
  .backgroundColor($r('app.color.setting_block_background'))
  .margin({ bottom: 20 })
}

@Component
struct ItemTitle {
  @Prop title: string | Resource
  @Prop subTitle: string | Resource

  build() {
    Column() {
      Text(this.title).fontSize($r('sys.float.Body_L')).fontColor($r('sys.color.font_primary'))
      Text(this.subTitle).fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_tertiary'))
    }
    .flexGrow(1)
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
struct SettingItem {
  @Prop title: string | Resource
  @Prop subTitle: string | Resource
  @Prop icon: Resource | undefined
  @BuilderParam content?: () => void

  build() {

    Row() {
      ItemTitle({
        title: this.title,
        subTitle: this.subTitle
      })

      if (this.content) {
        this.content()
      }
      if (this.icon) {
        SymbolGlyph(this.icon)
          .fontColor([$r('sys.color.icon_secondary')])
          .fontSize('24vp')
      }
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .height(56)
    .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })
  }
}

@Component
export default struct SettingsContent {
  @Watch('saveVmCpuCount') @StorageProp(appOption.cpuCountName) vmCpuCount: number = 1
  @Watch('saveVmMemSize') @StorageProp(appOption.memSizeName) vmMemSize: number = 512
  @Watch('saveKeepScreenOn') @StorageProp(appOption.keepScreenOn) keepScreenOn: boolean = false
  @StorageProp('bundleInfo') bundleInfo?: bundleManager.BundleInfo = undefined
  @StorageProp('versionCode') versionCode: number = 0
  portMappingController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.setting_port_mapping'),
      contentBuilder: () => {
        this.buildPortMapping();
      }
    })
  })
  sharedFolderController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.setting_shared_folder'),
      contentBuilder: () => {
        this.buildSharedFolder();
      }
    })
  })
  openSourceController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.open_source_license'),
      contentBuilder: () => {
        this.buildOpenSourceView();
      },
      buttons: [{
        value: $r('app.string.SettingComplete_label'),
        buttonStyle: ButtonStyleMode.TEXTUAL,
        action: () => {
          this.openSourceController.close();
        }
      }]
    })
  })
  aboutController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.about_me'),
      contentBuilder: () => {
        this.buildAboutMe();
      },
      buttons: [{
        value: $r('app.string.SettingComplete_label'),
        buttonStyle: ButtonStyleMode.TEXTUAL,
        action: () => {
          this.aboutController.close();
        }
      }]
    })
  })
  context = this.getUIContext().getHostContext() as common.UIAbilityContext
  preferences?: preference.Preferences

  async aboutToAppear(): Promise<void> {
    this.preferences = await preference.getPreferences(this.context.getApplicationContext(), appOption.preferenceName)
  }

  saveVmCpuCount() {
    this.preferences!.put(appOption.cpuCountName, this.vmCpuCount)
    this.preferences!.flush()
  }

  saveVmMemSize() {
    this.preferences!.put(appOption.memSizeName, this.vmMemSize)
    this.preferences!.flush()
  }

  saveKeepScreenOn() {
    this.preferences!.put(appOption.keepScreenOn, this.keepScreenOn)
    this.preferences!.flush()

    const mainWindow = AppStorage.get('mainWindow') as window.Window
    if (mainWindow) {
      mainWindow.setWindowKeepScreenOn(this.keepScreenOn)
    }
  }

  @Builder
  private cpuSetting() {
    Select([{ value: '1' }, { value: '2' }, { value: '4' }])
      .width(100)
      .value(this.vmCpuCount.toString())
      .onSelect((_i, value) => AppStorage.setOrCreate(appOption.cpuCountName, parseInt(value)))
  }

  @Builder
  private memorySetting() {
    Select([{ value: '512' }, { value: '1024' }, { value: '2048' }, { value: '4096' }])
      .width(100)
      .value(this.vmMemSize.toString())
      .onSelect((_i, value) => AppStorage.setOrCreate(appOption.memSizeName, parseInt(value)))
  }

  @Builder
  private keepScreenSetting() {
    Checkbox()
      .select(this.keepScreenOn)
      .onChange((value: boolean) => {
        AppStorage.setOrCreate(appOption.keepScreenOn, value)
      })
  }

  build() {
    Scroll() {
      Column() {

        BlockTitle({ content: $r("app.string.setting_block_system") })
        Column() {
          SettingItem({
            title: $r('app.string.setting_cpu'),
            subTitle: $r('app.string.setting_cpu_desc'),
            content: () => {
              this.cpuSetting()
            }
          })

          SettingItem({
            title: $r('app.string.setting_mem_size'),
            subTitle: $r('app.string.setting_mem_size_desc'),
            content: () => {
              this.memorySetting()
            }
          })

          SettingItem({
            title: $r('app.string.setting_port_mapping'),
            subTitle: $r('app.string.setting_port_mapping_desc'),
            icon: $r('sys.symbol.chevron_right')
          }).onClick(async () => {
            this.portMappingController.open()
          })

          SettingItem({
            title: $r('app.string.setting_reset_linux'),
            subTitle: $r('app.string.setting_reset_linux_desc'),
            icon: $r('sys.symbol.arrow_clockwise')
          }).onClick(async () => {
            this.openResetLinuxDialog()
          })
        }
        .settingBlockStyle()

        BlockTitle({ content: $r("app.string.setting_shared_folder") })
        Column() {
          SettingItem({
            title: $r('app.string.setting_shared_folder'),
            subTitle: $r('app.string.setting_shared_folder_desc'),
            icon: $r('sys.symbol.chevron_right')
          }).onClick(async () => {
            this.sharedFolderController.open()
          })
        }
        .settingBlockStyle()

        BlockTitle({ content: $r("app.string.setting_block_display") })
        Column() {
          SettingItem({
            title: $r('app.string.setting_keep_screen_on'),
            subTitle: $r('app.string.setting_keep_screen_on_desc'),
            content: () => {
              this.keepScreenSetting()
            }
          })
        }
        .settingBlockStyle()

        BlockTitle({ content: $r('app.string.setting_block_about') })
        Column() {
          LinkItem({
            icon: $r('sys.symbol.house'),
            title: $r('app.string.code_repository'),
            click: () => {
              this.toWebBrowser('https://github.com/harmoninux/hish')
            }
          })

          LinkItem({
            icon: $r('sys.symbol.doc_text_badge_checkmark'),
            title: $r('app.string.open_source_license'),
            click: () => {
              this.openSourceController.open();
            }
          })

          LinkItem({
            icon: $r('sys.symbol.info_circle'),
            title: $r('app.string.about_me'),
            click: () => {
              this.aboutController.open();
            }
          })
        }
        .settingBlockStyle()
      }
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .scrollBarWidth(1)
  }

  @Builder
  buildPortMapping() {
    PortMappingContent({
      onSaved: () => {
        this.portMappingController.close()
      }
    })
  }

  @Builder
  buildSharedFolder() {
    SharedFolderContent()
  }

  @Builder
  buildOpenSourceView() {
    OpenSourceContent()
  }

  @Builder
  buildAboutMe() {
    Column() {

      Image($r('app.media.startIcon'))
        .width(50)

      Text($r('app.string.app_name'))
        .margin({ top: 10 })

      Text(`${this.bundleInfo?.versionName}(${this.bundleInfo?.versionCode})`)
        .fontSize(14)
        .fontColor('#ccc')
        .margin({ top: 5 })
    }
    .width('100%')
  }

  private openResetLinuxDialog() {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.setting_reset_linux_title'),
      message: $r('app.string.setting_reset_linux_content'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.setting_generic_cancel'),
          action: () => {
          }
        },
        {
          enabled: true,
          style: DialogButtonStyle.HIGHLIGHT,
          backgroundColor: $r('sys.color.warning'),
          value: $r('app.string.setting_reset_linux_reset'),
          action: async () => {
            await this.markResetLinuxAndRestart();
          }
        }
      ],
    });
  }

  private async toWebBrowser(url: string): Promise<void> {
    let context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    let want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url,
      parameters: {
        bundleName: context.abilityInfo.bundleName
      }
    };
    await context.startAbility(want);
  }

  private async markResetLinuxAndRestart() {
    await this.preferences?.put(appOption.resetLinuxFlag, true);
    await this.preferences?.flush();
    this.restartApp();
  }

  private async restartApp() {
    let applicationContext = this.context.getApplicationContext();
    let want: Want = {
      bundleName: this.bundleInfo?.name,
      abilityName: 'EntryAbility'
    };
    applicationContext.restartApp(want);
  }
}