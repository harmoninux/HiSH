import { CustomContentDialog, window } from '@kit.ArkUI';
import { LinkItem } from "./LinkItem"
import { bundleManager, common, Want } from '@kit.AbilityKit';
import preference from '@ohos.data.preferences';
import appOption from '../model/appOption';
import { SharedFolderContent } from './SharedFolderContent';
import { PortMappingContent } from './PortMappingContent';
import { OpenSourceContent } from './OpenSourceContent';

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

  build() {
    Scroll() {
      Column() {

        Text($r("app.string.setting_block_system"))
          .margin({ bottom: 10, left: 20 })
          .width('100%')
        Column() {
          Row() {
            Column() {
              Text($r('app.string.setting_cpu'))
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.font_primary'))
              Text($r('app.string.setting_cpu_desc'))
                .fontSize($r('sys.float.Body_M'))
                .fontColor($r('sys.color.font_tertiary'))
            }
            .flexGrow(1)
            .alignItems(HorizontalAlign.Start)

            Select([{ value: '1' }, { value: '2' }, { value: '4' }])
              .width(100)
              .value(this.vmCpuCount.toString())
              .onSelect((_i, value) => AppStorage.setOrCreate(appOption.cpuCountName, parseInt(value)))
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .height(56)
          .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })

          Row() {
            Column() {
              Text($r('app.string.setting_mem_size'))
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.font_primary'))
              Text($r('app.string.setting_mem_size_desc'))
                .fontSize($r('sys.float.Body_M'))
                .fontColor($r('sys.color.font_tertiary'))
            }
            .flexGrow(1)
            .alignItems(HorizontalAlign.Start)

            Select([{ value: '512' }, { value: '1024' }, { value: '2048' }, { value: '4096' }])
              .width(100)
              .value(this.vmMemSize.toString())
              .onSelect((_i, value) => AppStorage.setOrCreate(appOption.memSizeName, parseInt(value)))
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .height(56)
          .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })

          Row() {
            Column() {
              Text($r('app.string.setting_port_mapping'))
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.font_primary'))
              Text($r('app.string.setting_port_mapping_desc'))
                .fontSize($r('sys.float.Body_M'))
                .fontColor($r('sys.color.font_tertiary'))
            }
            .flexGrow(1)
            .alignItems(HorizontalAlign.Start)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontColor([$r('sys.color.icon_secondary')])
              .fontSize('24vp')
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .height(56)
          .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })
          .onClick(async () => {
            this.portMappingController.open()
          })

          Row() {
            Column() {
              Text($r('app.string.setting_reset_linux'))
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.font_primary'))
              Text($r('app.string.setting_port_mapping_desc'))
                .fontSize($r('sys.float.Body_M'))
                .fontColor($r('sys.color.font_tertiary'))
            }
            .flexGrow(1)
            .alignItems(HorizontalAlign.Start)

            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontColor([$r('sys.color.icon_secondary')])
              .fontSize('24vp')
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .height(56)
          .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })
          .onClick(() => this.openResetLinuxDialog())
        }
        .borderRadius(20)
        .backgroundColor($r('app.color.setting_block_background'))

        Text($r("app.string.setting_shared_folder"))
          .margin({ top: 20, bottom: 10, left: 20 })
          .width('100%')
        Column() {
          Row() {
            Column() {
              Text($r('app.string.setting_shared_folder'))
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.font_primary'))
              Text($r('app.string.setting_shared_folder_desc'))
                .fontSize($r('sys.float.Body_M'))
                .fontColor($r('sys.color.font_tertiary'))
            }
            .flexGrow(1)
            .alignItems(HorizontalAlign.Start)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontColor([$r('sys.color.icon_secondary')])
              .fontSize('24vp')
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .height(56)
          .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })
          .onClick(async () => {
            this.sharedFolderController.open()
          })
        }
        .borderRadius(20)
        .backgroundColor($r('app.color.setting_block_background'))

        Text($r("app.string.setting_block_display"))
          .margin({ top: 20, bottom: 10, left: 20 })
          .width('100%')
        Column() {
          Row() {
            Column() {
              Text($r('app.string.setting_keep_screen_on'))
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.font_primary'))
              Text($r('app.string.setting_keep_screen_on_desc'))
                .fontSize($r('sys.float.Body_M'))
                .fontColor($r('sys.color.font_tertiary'))
            }
            .flexGrow(1)
            .alignItems(HorizontalAlign.Start)

            Checkbox()
              .select(this.keepScreenOn)
              .onChange((value: boolean) => {
                AppStorage.setOrCreate(appOption.keepScreenOn, value)
              })
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .height(56)
          .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })
        }
        .borderRadius(20)
        .backgroundColor($r('app.color.setting_block_background'))

        Text($r('app.string.setting_block_about'))
          .margin({ top: 20, bottom: 10, left: 20 })
          .width('100%')
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
        .borderRadius(20)
        .backgroundColor($r('app.color.setting_block_background'))
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