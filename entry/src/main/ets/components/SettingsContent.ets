import { CustomContentDialog, window } from '@kit.ArkUI';
import { bundleManager, common, Want } from '@kit.AbilityKit';
import preference from '@ohos.data.preferences';
import appOption, { savePreference } from '../model/appOption';
import { OpenSourceContent } from './OpenSourceContent';
import { BlockTitle, LinkItem, SettingBlockStyle, SettingItem } from './SettingsBase';

const fontSizeOptions: SelectOption[] = [{
  value: '9'
}, {
  value: '10'
}, {
  value: '11'
}, {
  value: '12'
}, {
  value: '13'
}, {
  value: '14'
}, {
  value: '15'
}, {
  value: '16'
}, {
  value: '17'
}, {
  value: '18'
}]

@Component
export default struct SettingsContent {
  @Watch('saveKeepScreenOn') @StorageProp(appOption.keepScreenOn) keepScreenOn: boolean = false
  @Watch('saveTermFontSize') @StorageProp(appOption.terminalFontSize) terminalFontSize: number = 12
  @StorageProp('bundleInfo') bundleInfo?: bundleManager.BundleInfo = undefined
  @StorageProp('versionCode') versionCode: number = 0
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
  blockStyle: SettingBlockStyle = new SettingBlockStyle()

  async saveKeepScreenOn() {
    await savePreference(appOption.keepScreenOn, this.keepScreenOn, this.getUIContext())

    const mainWindow = AppStorage.get('mainWindow') as window.Window
    if (mainWindow) {
      mainWindow.setWindowKeepScreenOn(this.keepScreenOn)
    }
  }

  @Builder
  private keepScreenSetting() {
    Checkbox()
      .select(this.keepScreenOn)
      .onChange((value: boolean) => {
        AppStorage.setOrCreate(appOption.keepScreenOn, value)
      })
  }

  @Builder
  private buildTerminalFontSize() {
    Select(fontSizeOptions)
      .width(80)
      .value(this.terminalFontSize.toString())
      .onSelect((_i, value) => AppStorage.setOrCreate(appOption.terminalFontSize, parseInt(value)))
  }

  build() {
    Column() {
      Scroll() {
        Column() {

          BlockTitle({ content: $r("app.string.setting_block_display") })
          Column() {
            SettingItem({
              title: $r('app.string.setting_keep_screen_on'),
              subTitle: $r('app.string.setting_keep_screen_on_desc'),
              content: () => {
                this.keepScreenSetting()
              }
            }).onClick(() => {
              AppStorage.setOrCreate(appOption.keepScreenOn, !this.keepScreenOn)
            })

            SettingItem({
              title: '终端字体大小',
              subTitle: '设置终端字体大小',
              content: () => {
                this.buildTerminalFontSize()
              }
            })
          }
          .attributeModifier(this.blockStyle)

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
          .attributeModifier(this.blockStyle)
        }
        .margin(10)
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .scrollBarWidth(1)
      .layoutWeight(1)
      .align(Alignment.Top)
    }
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

  async saveTermFontSize() {
    await savePreference(appOption.terminalFontSize, this.terminalFontSize, this.getUIContext())
  }
}