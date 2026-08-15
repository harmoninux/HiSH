import { CustomContentDialog, window } from '@kit.ArkUI';
import { common, Want, bundleManager } from '@kit.AbilityKit';
import preference from '@ohos.data.preferences';
import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import appOption, { CursorShape, savePreference, UserFont } from '../model/appOption';
import { OpenSourceContent } from './OpenSourceContent';
import { BlockTitle, LinkItem, SettingBlockStyle, SettingItem } from './SettingsBase';
import deviceInfo from '@ohos.deviceInfo';
import { backgroundRunningManager } from '../lib/backgroundRunningManager';
import copyFile from '../lib/copyFile';
import { ImmersiveButtonModifier } from '../lib/immersiveButton';

const DOMAIN = 0x0000;

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

const vncPortModeOptions: SelectOption[] = [
  { value: $r('app.string.setting_vnc_port_mode_local') },
  { value: $r('app.string.setting_vnc_port_mode_lan') }
]

@Component
export default struct SettingsContent {
  @Watch('saveKeepScreenOn') @StorageProp(appOption.keepScreenOn) keepScreenOn: boolean = false
  @Watch('saveTermFontSize') @StorageProp(appOption.terminalFontSize) terminalFontSize: number = 12
  @Watch('saveTermFontFamily') @StorageProp(appOption.terminalFontFamily) terminalFontFamily: string = 'Default'
  @StorageProp(appOption.availableFontFamilies) availableFontFamilies: string[] = ['Default']
  @Watch('saveTermCursorShape') @StorageProp(appOption.terminalCursorShape) termCursorShape: CursorShape = 'BLOCK'
  @Watch('saveTermCursorBlink') @StorageProp(appOption.terminalCursorBlink) termCursorBlink: boolean = false
  @Watch('saveTermLigatures') @StorageProp(appOption.terminalLigatures) termLigatures: boolean = false
  @Watch('saveTermItalic') @StorageProp(appOption.terminalItalic) termItalic: boolean = true
  @Watch('saveTermBackgroundColor') @StorageProp(appOption.terminalBackgroundColor) termBackgroundColor: string =
    '#000000'
  @Watch('saveTermBackgroundImage') @StorageProp(appOption.terminalBackgroundImage) termBackgroundImage: string = ''
  @Watch('saveTermBackgroundBlur') @StorageProp(appOption.terminalBackgroundBlur) termBackgroundBlur: number = 0
  @Watch('saveTermUserFonts') @StorageProp(appOption.terminalUserFonts) userFonts: UserFont[] = []
  @State colorInput: string = ''
  @Watch('saveRunningInBackground') @StorageProp(appOption.runningInBackground) runningInBackground: boolean = false
  @Watch('saveDisplayStatusBar') @StorageProp(appOption.displayStatusBar) displayStatusBar: boolean = false
  @Watch('saveVncEnabled') @StorageProp(appOption.vncEnabled) vncEnabled: boolean = false
  @Watch('saveVncPortMode') @StorageProp(appOption.vncPortMode) vncPortMode: string = 'local'
  @Watch('saveVncPort') @StorageProp(appOption.vncPort) vncPort: number = 5900
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
  colorController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.setting_background_color'),
      contentBuilder: () => {
        this.buildColorPicker();
      },
      buttons: [{
        value: $r('app.string.SettingComplete_label'),
        buttonStyle: ButtonStyleMode.TEXTUAL,
        action: () => {
          this.applyColorInput();
          this.colorController.close();
        }
      }]
    })
  })
  presetColors: string[] = [
    '#000000', '#0C0C0C', '#1E1E1E', '#282C34', '#002B36',
    '#300A24', '#2D2D2D', '#FFFFFF', '#F5F5F5', '#0B0C10'
  ]
  context = this.getUIContext().getHostContext() as common.UIAbilityContext
  preferences?: preference.Preferences
  blockStyle: SettingBlockStyle = new SettingBlockStyle()
  immersiveButton: ImmersiveButtonModifier = new ImmersiveButtonModifier()

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
  private buildTerminalFontFamily() {
    Select(this.buildFontFamilyOptions())
      .width(240)
      .value(this.terminalFontFamily)
      .onSelect((_i, value) => AppStorage.setOrCreate(appOption.terminalFontFamily, value))
  }

  private buildFontFamilyOptions(): SelectOption[] {
    // Prepend 'Default' as the first option, then append detected fonts
    const options: SelectOption[] = [{ value: 'Default' }];
    for (const font of this.availableFontFamilies) {
      // Avoid duplicating 'Default'
      if (font !== 'Default') {
        options.push({ value: font });
      }
    }
    // Append user-uploaded fonts
    for (const userFont of this.userFonts) {
      options.push({ value: userFont.name });
    }
    return options;
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
  private buildTermLigatures() {
    Checkbox()
      .select(this.termLigatures)
      .onChange((value: boolean) => {
        AppStorage.setOrCreate(appOption.terminalLigatures, value)
      })
  }

  @Builder
  private buildTermItalic() {
    Checkbox()
      .select(this.termItalic)
      .onChange((value: boolean) => {
        AppStorage.setOrCreate(appOption.terminalItalic, value)
      })
  }

  @Builder
  private buildBackgroundColorSwatch() {
    Row()
      .width(28)
      .height(28)
      .borderRadius(14)
      .backgroundColor(this.termBackgroundColor)
      .border({ width: 1, color: $r('sys.color.icon_tertiary') })
  }

  @Builder
  private buildColorPicker() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.presetColors, (color: string) => {
          Row()
            .width(36)
            .height(36)
            .margin(6)
            .borderRadius(18)
            .backgroundColor(color)
            .border({
              width: this.termBackgroundColor === color ? 3 : 1,
              color: this.termBackgroundColor === color ?
                $r('sys.color.interactive_active') : $r('sys.color.icon_tertiary')
            })
            .onClick(() => {
              AppStorage.setOrCreate(appOption.terminalBackgroundColor, color)
              this.colorInput = color
            })
        }, (color: string) => color)
      }
      TextInput({ text: this.colorInput, placeholder: '#000000' })
        .margin({ top: 12 })
        .onChange((value: string) => {
          this.colorInput = value
        })
    }
    .width('100%')
  }

  @Builder
  private buildBackgroundImageButtons() {
    Row() {
      Button($r('app.string.setting_choose_file'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .attributeModifier(this.immersiveButton)
        .onClick(() => {
          this.pickBackgroundImage()
        })
      if (this.termBackgroundImage.length > 0) {
        Button($r('app.string.setting_background_image_clear'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .attributeModifier(this.immersiveButton)
          .onClick(() => {
            this.clearBackgroundImage()
          })
      }
    }
  }

  @Builder
  private buildBackgroundBlurSlider() {
    Row() {
      Slider({ value: this.termBackgroundBlur, min: 0, max: 40, step: 1 })
        .width(160)
        .onChange((value: number, mode: SliderChangeMode) => {
          // 拖动结束/点击时才写入，避免拖动过程中频繁刷写偏好与 WebView
          if (mode !== SliderChangeMode.Moving) {
            AppStorage.setOrCreate(appOption.terminalBackgroundBlur, Math.round(value))
          }
        })
      Text(`${this.termBackgroundBlur}px`)
        .fontSize($r('sys.float.Body_M'))
        .fontColor($r('sys.color.font_tertiary'))
        .textAlign(TextAlign.End)
        .width(44)
        .margin({ left: 8 })
    }
  }

  @Builder
  private buildUploadFontButton() {
    Button($r('app.string.setting_choose_file'), { buttonStyle: ButtonStyleMode.TEXTUAL })
        .attributeModifier(this.immersiveButton)
      .onClick(() => {
        this.pickUserFont()
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
  private setDisplayStatusBar() {
    Checkbox()
      .select(this.displayStatusBar)
      .onChange((value: boolean) => {
        AppStorage.setOrCreate(appOption.displayStatusBar, value)
        this.showDisplayStatusBarToast(value)
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
  private buildVncPortMode() {
    Select(vncPortModeOptions)
      .width(100)
      .value(this.vncPortMode === 'lan' ?
        $r('app.string.setting_vnc_port_mode_lan') :
        $r('app.string.setting_vnc_port_mode_local'))
      .onSelect((_i, _value) => {
        const mode = _i === 1 ? 'lan' : 'local'
        AppStorage.setOrCreate(appOption.vncPortMode, mode)
      })
  }

  @Builder
  private buildVncPort() {
    TextInput({ text: this.vncPort.toString(), placeholder: '5900' })
      .width(80)
      .type(InputType.Number)
      .onChange((value) => {
        const port = value ? parseInt(value) : 5900
        const clamped = Math.min(Math.max(port, 5900), 5999)
        AppStorage.setOrCreate(appOption.vncPort, clamped)
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
              title: $r('app.string.setting_font_family'),
              subTitle: $r('app.string.setting_font_family_desc'),
              content: () => {
                this.buildTerminalFontFamily()
              }
            })

            SettingItem({
              title: $r('app.string.setting_upload_font'),
              subTitle: $r('app.string.setting_upload_font_desc'),
              content: () => {
                this.buildUploadFontButton()
              }
            })

            ForEach(this.userFonts, (font: UserFont, index: number) => {
              Row() {
                Text(font.name)
                  .fontSize($r('sys.float.Body_L'))
                  .fontColor($r('sys.color.font_secondary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Button($r('app.string.setting_background_image_clear'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .attributeModifier(this.immersiveButton)
                  .onClick(() => {
                    this.removeUserFont(index)
                  })
              }
              .width('100%')
              .height(56)
              .alignItems(VerticalAlign.Center)
              .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })
            }, (font: UserFont) => font.file)

            SettingItem({
              title: $r('app.string.setting_ligatures'),
              subTitle: $r('app.string.setting_ligatures_desc'),
              content: () => {
                this.buildTermLigatures()
              }
            }).onClick(() => {
              AppStorage.setOrCreate(appOption.terminalLigatures, !this.termLigatures)
            })

            SettingItem({
              title: $r('app.string.setting_italic'),
              subTitle: $r('app.string.setting_italic_desc'),
              content: () => {
                this.buildTermItalic()
              }
            }).onClick(() => {
              AppStorage.setOrCreate(appOption.terminalItalic, !this.termItalic)
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

          BlockTitle({ content: $r('app.string.setting_block_terminal_background') })
          Column() {
            SettingItem({
              title: $r('app.string.setting_background_color'),
              subTitle: $r('app.string.setting_background_color_desc'),
              content: () => {
                this.buildBackgroundColorSwatch()
              }
            }).onClick(() => {
              this.colorInput = this.termBackgroundColor
              this.colorController.open()
            })

            SettingItem({
              title: $r('app.string.setting_background_image'),
              subTitle: $r('app.string.setting_background_image_desc'),
              content: () => {
                this.buildBackgroundImageButtons()
              }
            })

            SettingItem({
              title: $r('app.string.setting_background_blur'),
              subTitle: $r('app.string.setting_background_blur_desc'),
              content: () => {
                this.buildBackgroundBlurSlider()
              }
            })
          }
          .attributeModifier(this.blockStyle)

          BlockTitle({ content: $r('app.string.setting_vnc') })
          Column() {
            SettingItem({
              title: $r('app.string.setting_enable_vnc'),
              subTitle: $r('app.string.setting_vnc_restart_hint'),
              content: () => {
                this.buildVncEnabled()
              }
            }).onClick(() => {
              AppStorage.setOrCreate(appOption.vncEnabled, !this.vncEnabled)
            })
            SettingItem({
              title: $r('app.string.setting_vnc_port_mode'),
              subTitle: $r('app.string.setting_vnc_port_mode_desc'),
              content: () => {
                this.buildVncPortMode()
              }
            })
            SettingItem({
              title: $r('app.string.setting_vnc_port'),
              subTitle: $r('app.string.setting_vnc_port_desc'),
              content: () => {
                this.buildVncPort()
              }
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
            SettingItem({
              title: $r('app.string.display_status_bar'),
              subTitle: $r('app.string.guest_status_bar_desc'),
              content: () => {
                this.setDisplayStatusBar()
              }
            }).onClick(() => {
              const value: boolean = !this.displayStatusBar;
              AppStorage.setOrCreate(appOption.displayStatusBar, value)
              this.showDisplayStatusBarToast(value)
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

            if (this.bundleInfo?.name === 'app.hackeris.hish') {
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
      .padding({ bottom: 50 })
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

  async saveTermFontFamily() {
    await savePreference(appOption.terminalFontFamily, this.terminalFontFamily, this.getUIContext())
  }

  async saveTermCursorShape() {
    await savePreference(appOption.terminalCursorShape, this.termCursorShape, this.getUIContext())
  }

  async saveTermCursorBlink() {
    await savePreference(appOption.terminalCursorBlink, this.termCursorBlink, this.getUIContext())
  }

  async saveTermLigatures() {
    await savePreference(appOption.terminalLigatures, this.termLigatures, this.getUIContext())
  }

  async saveTermItalic() {
    await savePreference(appOption.terminalItalic, this.termItalic, this.getUIContext())
  }

  async saveTermBackgroundColor() {
    await savePreference(appOption.terminalBackgroundColor, this.termBackgroundColor, this.getUIContext())
  }

  async saveTermBackgroundImage() {
    await savePreference(appOption.terminalBackgroundImage, this.termBackgroundImage, this.getUIContext())
  }

  async saveTermBackgroundBlur() {
    await savePreference(appOption.terminalBackgroundBlur, this.termBackgroundBlur, this.getUIContext())
  }

  async saveTermUserFonts() {
    await savePreference(appOption.terminalUserFonts, this.userFonts, this.getUIContext())
  }

  private applyColorInput() {
    const hexReg = new RegExp('^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$')
    const value = this.colorInput.trim()
    if (hexReg.test(value)) {
      AppStorage.setOrCreate(appOption.terminalBackgroundColor, value)
    }
  }

  private async pickUserFont(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['ttf', 'otf', 'woff', 'woff2'];
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris = await documentPicker.select(options);
      if (uris.length === 0) {
        return
      }
      await this.importUserFont(uris[0])
    } catch (e) {
      hilog.error(DOMAIN, 'SettingsContent', 'pickUserFont failed: %{public}s', JSON.stringify(e))
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.setting_font_import_failed') })
    }
  }

  private async importUserFont(uri: string): Promise<void> {
    let rawName = uri.substring(uri.lastIndexOf('/') + 1)
    try {
      rawName = decodeURIComponent(rawName)
    } catch (e) {
      hilog.warn(DOMAIN, 'SettingsContent', 'decode font name failed, use raw: %{public}s', rawName)
    }
    const dotIndex = rawName.lastIndexOf('.')
    if (dotIndex <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.setting_font_import_failed') })
      return
    }
    const ext = rawName.substring(dotIndex + 1).toLowerCase()
    const baseName = rawName.substring(0, dotIndex)
    const filesDir = AppStorage.get<string>(appOption.appFilesDir)!!
    const fontsDir = filesDir + '/fonts'
    if (!fs.accessSync(fontsDir, fs.AccessModeType.EXIST)) {
      fs.mkdirSync(fontsDir)
    }
    const destPath = `${fontsDir}/font_${Date.now()}.${ext}`
    await copyFile(uri, destPath)

    const fonts = this.userFonts.slice()
    const newFont: UserFont = { name: baseName, file: destPath }
    fonts.push(newFont)
    AppStorage.setOrCreate(appOption.terminalUserFonts, fonts)
    this.getUIContext().getPromptAction().showToast({ message: $r('app.string.setting_font_imported') })
  }

  private removeUserFont(index: number) {
    const fonts = this.userFonts.slice()
    const removed = fonts.splice(index, 1)
    if (removed.length > 0) {
      try {
        fs.unlinkSync(removed[0].file)
      } catch (e) {
        hilog.warn(DOMAIN, 'SettingsContent', 'remove font file failed: %{public}s', JSON.stringify(e))
      }
      if (this.terminalFontFamily === removed[0].name) {
        AppStorage.setOrCreate(appOption.terminalFontFamily, 'Default')
      }
    }
    AppStorage.setOrCreate(appOption.terminalUserFonts, fonts)
    this.getUIContext().getPromptAction().showToast({ message: $r('app.string.setting_font_removed') })
  }

  private async pickBackgroundImage(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options = new picker.PhotoSelectOptions();
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const photoPicker = new picker.PhotoViewPicker(context);
      const result = await photoPicker.select(options);
      if (result.photoUris.length === 0) {
        return
      }
      const uri = result.photoUris[0]
      const dotIndex = uri.lastIndexOf('.')
      const ext = dotIndex > 0 ? uri.substring(dotIndex + 1).toLowerCase() : 'jpg'
      const filesDir = AppStorage.get<string>(appOption.appFilesDir)!!
      const bgDir = filesDir + '/terminal_bg'
      if (!fs.accessSync(bgDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(bgDir)
      }
      this.deleteBackgroundImageFile()
      const fileName = `background_${Date.now()}.${ext}`
      await copyFile(uri, `${bgDir}/${fileName}`)
      AppStorage.setOrCreate(appOption.terminalBackgroundImage, fileName)
    } catch (e) {
      hilog.error(DOMAIN, 'SettingsContent', 'pickBackgroundImage failed: %{public}s', JSON.stringify(e))
    }
  }

  private clearBackgroundImage() {
    this.deleteBackgroundImageFile()
    AppStorage.setOrCreate(appOption.terminalBackgroundImage, '')
  }

  private deleteBackgroundImageFile() {
    if (this.termBackgroundImage.length === 0) {
      return
    }
    const filesDir = AppStorage.get<string>(appOption.appFilesDir) ?? ''
    const path = `${filesDir}/terminal_bg/${this.termBackgroundImage}`
    try {
      if (fs.accessSync(path, fs.AccessModeType.EXIST)) {
        fs.unlinkSync(path)
      }
    } catch (e) {
      hilog.warn(DOMAIN, 'SettingsContent', 'remove background image failed: %{public}s', JSON.stringify(e))
    }
  }

  async saveRunningInBackground() {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (this.runningInBackground) {
      const success = await backgroundRunningManager.grantLocationPermission(context)
      if (!success) {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.failed_to_force_background'),
          duration: 5000
        })
      }
    }
    await savePreference(appOption.runningInBackground, this.runningInBackground, this.getUIContext())
  }

  async saveDisplayStatusBar() {
    await savePreference(appOption.displayStatusBar, this.displayStatusBar, this.getUIContext())
  }

  showDisplayStatusBarToast(value: boolean) {
    if(value) {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.guest_status_bar_toast'),
        duration: 5000
      })
    }
  }

  async saveVncEnabled() {
    await savePreference(appOption.vncEnabled, this.vncEnabled, this.getUIContext())
  }

  showVncRestartToast() {
    this.getUIContext().getPromptAction().showToast({
      message: $r('app.string.setting_vnc_restart_hint'),
      duration: 3000
    })
  }

  async saveVncPortMode() {
    await savePreference(appOption.vncPortMode, this.vncPortMode, this.getUIContext())
    this.showVncRestartToast()
  }

  async saveVncPort() {
    await savePreference(appOption.vncPort, this.vncPort, this.getUIContext())
    this.showVncRestartToast()
  }
}
