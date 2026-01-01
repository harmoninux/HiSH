import { CustomContentDialog, window } from '@kit.ArkUI';
import { common, Want, bundleManager } from '@kit.AbilityKit';
import preference from '@ohos.data.preferences';
import appOption, { CursorShape, savePreference } from '../model/appOption';
import { OpenSourceContent } from './OpenSourceContent';
import { BlockTitle, LinkItem, SettingBlockStyle, SettingItem } from './SettingsBase';
import deviceInfo from '@ohos.deviceInfo';
import { backgroundRunningManager } from '../lib/backgroundRunningManager';

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

const cursorShapeOptions: SelectOption[] = [{ value: 'BLOCK' }, { value: 'BEAM' }, { value: 'UNDERLINE' }]

@Component
export default struct SettingsContent {
  @Watch('saveKeepScreenOn') @StorageProp(appOption.keepScreenOn) keepScreenOn: boolean = false
  @Watch('saveTermFontSize') @StorageProp(appOption.terminalFontSize) terminalFontSize: number = 12
  @Watch('saveTermCursorShape') @StorageProp(appOption.terminalCursorShape) termCursorShape: CursorShape = 'BLOCK'
  @Watch('saveTermCursorBlink') @StorageProp(appOption.terminalCursorBlink) termCursorBlink: boolean = false
  @Watch('saveRunningInBackground') @StorageProp(appOption.runningInBackground) runningInBackground: boolean = false
  @Watch('saveVncEnabled') @StorageProp(appOption.vncEnabled) vncEnabled: boolean = true
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

  @Builder
  private buildTerminalCursorBlink() {
    Checkbox()
      .select(this.termCursorBlink)
      .onChange((value: boolean) => {
        AppStorage.setOrCreate(appOption.terminalCursorBlink, value)
      })
  }

  @Builder
  private setRunningInBackground() {
    Checkbox()
      .select(this.runningInBackground)
      .onChange((value: boolean) => {
        AppStorage.setOrCreate(appOption.runningInBackground, value)
      })
  }

  @Builder
  private buildVncEnabled() {
    Checkbox()
      .select(this.vncEnabled)
      .onChange((value: boolean) => {
        AppStorage.setOrCreate(appOption.vncEnabled, value)
      })
  }

  @Builder
  private buildTerminalCursorShape() {
    Select(cursorShapeOptions)
      .width(160)
      .value(this.termCursorShape.toString())
      .onSelect((_i, value) => AppStorage.setOrCreate(appOption.terminalCursorShape, value))
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
          }
          .attributeModifier(this.blockStyle)

          BlockTitle({ content: $r("app.string.setting_terminal") })
          Column() {
            SettingItem({
              title: $r('app.string.setting_font_size'),
              subTitle: $r('app.string.setting_font_size_desc'),
              content: () => {
                this.buildTerminalFontSize()
              }
            })

            SettingItem({
              title: $r('app.string.setting_cursor_style'),
              subTitle: $r('app.string.setting_cursor_style_desc'),
              content: () => {
                this.buildTerminalCursorShape()
              }
            })

            SettingItem({
              title: $r('app.string.setting_cursor_blink'),
              subTitle: $r('app.string.setting_cursor_blink_desc'),
              content: () => {
                this.buildTerminalCursorBlink()
              }
            }).onClick(() => {
              AppStorage.setOrCreate(appOption.terminalCursorBlink, !this.termCursorBlink)
            })
          }
          .attributeModifier(this.blockStyle)

          BlockTitle({ content: $r('app.string.setting_vnc') })
          Column() {
            SettingItem({
              title: $r('app.string.setting_enable_novnc'),
              subTitle: $r('app.string.setting_vnc_restart_hint'),
              content: () => {
                this.buildVncEnabled()
              }
            }).onClick(() => {
              AppStorage.setOrCreate(appOption.vncEnabled, !this.vncEnabled)
            })
          }
          .attributeModifier(this.blockStyle)

          BlockTitle({ content: $r('app.string.setting_running') })
          Column() {
            SettingItem({
              title: $r('app.string.force_run_in_background'),
              subTitle: $r('app.string.force_background_desc'),
              content: () => {
                this.setRunningInBackground()
              }
            }).onClick(() => {
              AppStorage.setOrCreate(appOption.runningInBackground, !this.runningInBackground)
            })
          }
          .attributeModifier(this.blockStyle)

          BlockTitle({ content: $r('app.string.setting_block_help') })
          Column() {

            if (deviceInfo.deviceType !== '2in1') {
              LinkItem({
                icon: $r('sys.symbol.book_pages'),
                title: $r('app.string.user_guide_title'),
                click: () => {
                  this.getUIContext().getRouter().pushUrl({
                    url: 'pages/UserGuidePage'
                  })
                }
              })
            }

            if (!this.bundleInfo?.name.startsWith('dev.hackeris')) {
              LinkItem({
                icon: $r('sys.symbol.star'),
                title: $r('app.string.like_this_app'),
                click: () => {
                  const want: Want = {
                    uri: `store://appgallery.huawei.com/app/detail?id=${this.bundleInfo?.name}`
                  };
                  const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
                  context.startAbility(want)
                }
              })
              LinkItem({
                icon: $r('sys.symbol.fast_forward'),
                title: $r('app.string.fast_code_jit'),
                click: () => {
                  this.getUIContext().getRouter().pushUrl({
                    url: 'pages/GuideWebPage',
                    params: { page: 'guide/Z1_Jit.html', title: $r('app.string.guide_jit_title') }
                  })
                }
              })
            }

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

  async saveTermCursorShape() {
    await savePreference(appOption.terminalCursorShape, this.termCursorShape, this.getUIContext())
  }

  async saveTermCursorBlink() {
    await savePreference(appOption.terminalCursorBlink, this.termCursorBlink, this.getUIContext())
  }

  async saveRunningInBackground() {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (this.runningInBackground) {
      const success = await backgroundRunningManager.grantLocationPermission(context)
      if (!success) {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.failed_to_force_background'),
          duration: 3000
        })
      }
    }
    await savePreference(appOption.runningInBackground, this.runningInBackground, this.getUIContext())
  }

  async saveVncEnabled() {
    await savePreference(appOption.vncEnabled, this.vncEnabled, this.getUIContext())
  }
}
