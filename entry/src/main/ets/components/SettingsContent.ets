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

const themeOptions: SelectOption[] = [
  { value: 'Dark (Default)' },
  { value: 'Dracula' },
  { value: 'Solarized Dark' },
  { value: 'Solarized Light' },
  { value: 'Monokai' },
  { value: 'Nord' },
  { value: 'Gruvbox Dark' },
  { value: '自定义 (Custom)' }
]

const fontOptions: SelectOption[] = [
  { value: 'CodeNewRoman NF Mono' },
  { value: 'Source Code Pro' },
  { value: 'Monospace' },
  { value: '自定义 (Custom)' }
]

const profileOptions: SelectOption[] = [
  { value: '均衡 (Balanced)' },
  { value: '省电 (Power Saving)' },
  { value: '性能 (Performance)' }
]

const vncPortModeOptions: SelectOption[] = [
  { value: $r('app.string.setting_vnc_port_mode_local') },
  { value: $r('app.string.setting_vnc_port_mode_lan') }
]

@Component
export default struct SettingsContent {
  @Watch('saveKeepScreenOn') @StorageProp(appOption.keepScreenOn) keepScreenOn: boolean = false
  @Watch('saveTermFontSize') @StorageProp(appOption.terminalFontSize) terminalFontSize: number = 12
  @Watch('saveTermCursorShape') @StorageProp(appOption.terminalCursorShape) termCursorShape: CursorShape = 'BLOCK'
  @Watch('saveTermCursorBlink') @StorageProp(appOption.terminalCursorBlink) termCursorBlink: boolean = false
  @Watch('saveRunningInBackground') @StorageProp(appOption.runningInBackground) runningInBackground: boolean = false
  @Watch('saveKeepAwake') @StorageProp(appOption.keepAwake) keepAwake: boolean = true
  @Watch('saveDisplayStatusBar') @StorageProp(appOption.displayStatusBar) displayStatusBar: boolean = false
  @Watch('saveVncEnabled') @StorageProp(appOption.vncEnabled) vncEnabled: boolean = true
  @Watch('saveVncPortMode') @StorageProp(appOption.vncPortMode) vncPortMode: string = 'local'
  @Watch('saveVncPort') @StorageProp(appOption.vncPort) vncPort: number = 5900
  @Watch('saveTerminalTheme') @StorageProp(appOption.terminalTheme) terminalTheme: string = 'dark'
  @Watch('saveTerminalFont') @StorageProp(appOption.terminalFont) terminalFont: string = 'CodeNewRoman NF Mono'
  @Watch('saveAutoSnapshot') @StorageProp(appOption.autoSnapshotOnExit) autoSnapshotOnExit: boolean = false
  @Watch('savePerformanceProfile') @StorageProp(appOption.performanceProfile) performanceProfile: string = 'balanced'
  @Watch('saveShowLauncher') @StorageProp(appOption.showLauncher) showLauncher: boolean = true
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
  /** 自定义主题编辑器状态 */
  @State customBg: string = '#1a1a2e'
  @State customFg: string = '#ffffff'
  @State customCursor: string = '#ffffff'
  @State customBlack: string = '#1a1a2e'
  @State customRed: string = '#e06c75'
  @State customGreen: string = '#98c379'
  @State customYellow: string = '#e5c07b'
  @State customBlue: string = '#61afef'
  @State customMagenta: string = '#c678dd'
  @State customCyan: string = '#56b6c2'
  @State customWhite: string = '#abb2bf'
  @State customSelectionBg: string = '#ffffff44'
  /** 自定义字体输入 */
  @State customFontFamily: string = ''

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
  private setKeepAwake() {
    Toggle({ type: ToggleType.Switch, isOn: this.keepAwake })
      .selectedColor('#4FC3F7')
      .onChange((isOn: boolean) => {
        AppStorage.setOrCreate(appOption.keepAwake, isOn)
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

  // Map display names to internal theme IDs
  private themeIdMap: Record<string, string> = {
    'Dark (Default)': 'dark',
    'Dracula': 'dracula',
    'Solarized Dark': 'solarized-dark',
    'Solarized Light': 'solarized-light',
    'Monokai': 'monokai',
    'Nord': 'nord',
    'Gruvbox Dark': 'gruvbox-dark',
    '自定义 (Custom)': 'custom'
  }

  /** 判断当前主题是否为自定义模式 */
  private isThemeCustom(): boolean {
    return this.terminalTheme !== 'dark' &&
      this.terminalTheme !== 'dracula' &&
      this.terminalTheme !== 'solarized-dark' &&
      this.terminalTheme !== 'solarized-light' &&
      this.terminalTheme !== 'monokai' &&
      this.terminalTheme !== 'nord' &&
      this.terminalTheme !== 'gruvbox-dark'
  }

  @Builder
  private buildTerminalTheme() {
    Select(themeOptions)
      .width(160)
      .value(this.isThemeCustom() ? '自定义 (Custom)' :
        this.terminalTheme === 'dark' ? 'Dark (Default)' :
        this.terminalTheme === 'dracula' ? 'Dracula' :
        this.terminalTheme === 'solarized-dark' ? 'Solarized Dark' :
        this.terminalTheme === 'solarized-light' ? 'Solarized Light' :
        this.terminalTheme === 'monokai' ? 'Monokai' :
        this.terminalTheme === 'nord' ? 'Nord' :
        this.terminalTheme === 'gruvbox-dark' ? 'Gruvbox Dark' : 'Dark (Default)')
      .onSelect((_i, value) => {
        const themeId = this.themeIdMap[value] || 'dark'
        if (themeId === 'custom') {
          this.terminalTheme = 'custom'
          // 尝试从现有 JSON 解析已保存的自定义配色
          this.loadCustomThemeFromStored()
        } else {
          AppStorage.setOrCreate(appOption.terminalTheme, themeId)
        }
      })
  }

  /**
   * 尝试从当前 terminalTheme 值解析自定义主题 JSON
   * 若 terminalTheme 是合法 JSON 则填充编辑器字段，否则用默认 dark 配色
   */
  private loadCustomThemeFromStored() {
    try {
      const stored = this.terminalTheme as string
      if (stored.startsWith('{')) {
        const parsed: Record<string, string> = JSON.parse(stored) as Record<string, string>
        this.customBg = parsed['background'] || '#1a1a2e'
        this.customFg = parsed['foreground'] || '#ffffff'
        this.customCursor = parsed['cursor'] || '#ffffff'
        this.customBlack = parsed['black'] || '#1a1a2e'
        this.customRed = parsed['red'] || '#e06c75'
        this.customGreen = parsed['green'] || '#98c379'
        this.customYellow = parsed['yellow'] || '#e5c07b'
        this.customBlue = parsed['blue'] || '#61afef'
        this.customMagenta = parsed['magenta'] || '#c678dd'
        this.customCyan = parsed['cyan'] || '#56b6c2'
        this.customWhite = parsed['white'] || '#abb2bf'
        this.customSelectionBg = parsed['selectionBackground'] || '#ffffff44'
        return
      }
    } catch (_e) {
      // JSON 解析失败，使用默认值
    }
    // 回退：用 dark 主题默认值
    this.customBg = '#1a1a2e'; this.customFg = '#ffffff'; this.customCursor = '#ffffff'
    this.customBlack = '#1a1a2e'; this.customRed = '#e06c75'; this.customGreen = '#98c379'
    this.customYellow = '#e5c07b'; this.customBlue = '#61afef'; this.customMagenta = '#c678dd'
    this.customCyan = '#56b6c2'; this.customWhite = '#abb2bf'; this.customSelectionBg = '#ffffff44'
  }

  /**
   * 自定义主题编辑器 —— 11 个配色字段 + 实时预览
   */
  @Builder
  private buildCustomThemeEditor() {
    Column() {
      Text('自定义配色方案')
        .fontSize(13).fontColor('#888888').padding({ bottom: 8 })

      // 基础色：背景 / 前景 / 光标 / 选区
      Row() { this.colorFieldRow('背景', this.customBg, (v: string) => { this.customBg = v }) }
      Row() { this.colorFieldRow('前景', this.customFg, (v: string) => { this.customFg = v }) }
      Row() { this.colorFieldRow('光标', this.customCursor, (v: string) => { this.customCursor = v }) }
      Row() { this.colorFieldRow('选区', this.customSelectionBg, (v: string) => { this.customSelectionBg = v }) }

      // ANSI 16 色（基础 8 色）
      Divider().margin({ top: 8, bottom: 8 })
      Row() { this.colorFieldRow('黑', this.customBlack, (v: string) => { this.customBlack = v }) }
      Row() { this.colorFieldRow('红', this.customRed, (v: string) => { this.customRed = v }) }
      Row() { this.colorFieldRow('绿', this.customGreen, (v: string) => { this.customGreen = v }) }
      Row() { this.colorFieldRow('黄', this.customYellow, (v: string) => { this.customYellow = v }) }
      Row() { this.colorFieldRow('蓝', this.customBlue, (v: string) => { this.customBlue = v }) }
      Row() { this.colorFieldRow('紫', this.customMagenta, (v: string) => { this.customMagenta = v }) }
      Row() { this.colorFieldRow('青', this.customCyan, (v: string) => { this.customCyan = v }) }
      Row() { this.colorFieldRow('白', this.customWhite, (v: string) => { this.customWhite = v }) }

      // 预览区
      Divider().margin({ top: 8, bottom: 8 })
      Text('预览')
        .fontSize(12).fontColor('#888888').padding({ bottom: 6 })
        .alignSelf(ItemAlign.Start)
      Column() {
        Text('\\x1b[30mBlack  \\x1b[31mRed  \\x1b[32mGreen  \\x1b[33mYellow')
          .fontSize(12).fontFamily('monospace')
        Text('\\x1b[34mBlue  \\x1b[35mMagenta  \\x1b[36mCyan  \\x1b[37mWhite')
          .fontSize(12).fontFamily('monospace').margin({ top: 4 })
      }
      .width('100%').padding(10)
      .backgroundColor('#0d0d1a').borderRadius(6)

      // 应用按钮
      Button('应用自定义主题')
        .width('100%').margin({ top: 12 })
        .onClick(() => {
          this.applyCustomTheme()
        })

      // 重置为预设
      Button('重置为 Dark 默认')
        .width('100%').margin({ top: 6 })
        .backgroundColor('#333333')
        .onClick(() => {
          AppStorage.setOrCreate(appOption.terminalTheme, 'dark')
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#111122')
    .borderRadius(8)
    .margin({ top: 6 })
  }

  @Builder
  private colorFieldRow(label: string, color: string, onChange: (v: string) => void) {
    Text(label)
      .fontSize(12).fontColor('#bbbbbb').width(30)
    Circle()
      .width(14).height(14)
      .fill(color)
      .stroke('#444444').strokeWidth(1)
      .margin({ left: 4, right: 6 })
    TextInput({ placeholder: '#RRGGBB', text: color })
      .fontSize(11).fontFamily('monospace')
      .width(90).height(28)
      .backgroundColor('#222233')
      .borderRadius(4)
      .onChange((value: string) => {
        onChange(value)
      })
  }

  /**
   * 将编辑器中的颜色值序列化为主题 JSON，写入 AppStorage
   */
  private applyCustomTheme() {
    const themeObj: Record<string, string> = {
      'background': this.customBg,
      'foreground': this.customFg,
      'cursor': this.customCursor,
      'cursorAccent': '#1a1a2e',
      'selectionBackground': this.customSelectionBg,
      'black': this.customBlack, 'red': this.customRed, 'green': this.customGreen,
      'yellow': this.customYellow, 'blue': this.customBlue, 'magenta': this.customMagenta,
      'cyan': this.customCyan, 'white': this.customWhite,
      'brightBlack': '#5c6370', 'brightRed': this.customRed, 'brightGreen': this.customGreen,
      'brightYellow': this.customYellow, 'brightBlue': this.customBlue,
      'brightMagenta': this.customMagenta, 'brightCyan': this.customCyan, 'brightWhite': '#ffffff'
    }
    const json = JSON.stringify(themeObj)
    AppStorage.setOrCreate(appOption.terminalTheme, json)
  }

  /** 判断当前字体是否为预设之一 */
  private isFontCustom(): boolean {
    const presets = ['CodeNewRoman NF Mono', 'Source Code Pro', 'Monospace']
    return presets.indexOf(this.terminalFont) < 0
  }

  @Builder
  private buildTerminalFont() {
    Select(fontOptions)
      .width(160)
      .value(this.isFontCustom() ? '自定义 (Custom)' : this.terminalFont)
      .onSelect((_i, value) => {
        if (value === '自定义 (Custom)') {
          this.customFontFamily = this.isFontCustom() ? this.terminalFont : ''
        } else {
          AppStorage.setOrCreate(appOption.terminalFont, value)
        }
      })
  }

  @Builder
  private buildCustomFontEditor() {
    Column() {
      Text('自定义字体')
        .fontSize(13).fontColor('#888888').padding({ bottom: 8 })

      Text('输入任意 CSS font-family 值，如 "Iosevka Term", monospace')
        .fontSize(11).fontColor('#666666').padding({ bottom: 8 })

      Row() {
        TextInput({ placeholder: '例: "Iosevka", monospace', text: this.customFontFamily })
          .fontSize(12).fontFamily('monospace')
          .layoutWeight(1).height(32)
          .backgroundColor('#222233')
          .borderRadius(4)
          .onChange((value: string) => {
            this.customFontFamily = value
          })
      }
      .width('100%')

      // 预览
      if (this.customFontFamily.length > 0) {
        Column() {
          Text('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
            .fontSize(14).fontFamily(this.customFontFamily).fontColor('#ffffff')
          Text('abcdefghijklmnopqrstuvwxyz')
            .fontSize(14).fontFamily(this.customFontFamily).fontColor('#aaaaaa').margin({ top: 4 })
          Text('0123456789  !@#$%^&*()')
            .fontSize(14).fontFamily(this.customFontFamily).fontColor('#888888').margin({ top: 4 })
        }
        .width('100%').padding(10)
        .backgroundColor('#0d0d1a').borderRadius(6)
        .margin({ top: 8, bottom: 8 })
      }

      Button('应用自定义字体')
        .width('100%')
        .onClick(() => {
          if (this.customFontFamily.length > 0) {
            AppStorage.setOrCreate(appOption.terminalFont, this.customFontFamily)
          }
        })

      Button('重置为默认字体')
        .width('100%').margin({ top: 6 })
        .backgroundColor('#333333')
        .onClick(() => {
          AppStorage.setOrCreate(appOption.terminalFont, 'CodeNewRoman NF Mono')
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#111122')
    .borderRadius(8)
    .margin({ top: 6 })
  }

  @Builder
  private buildPerformanceProfile() {
    Select(profileOptions)
      .width(140)
      .value(this.performanceProfile === 'balanced' ? '均衡 (Balanced)' :
        this.performanceProfile === 'powersave' ? '省电 (Power Saving)' : '性能 (Performance)')
      .onSelect((_i, _value) => {
        const profile = _i === 0 ? 'balanced' : _i === 1 ? 'powersave' : 'performance'
        AppStorage.setOrCreate(appOption.performanceProfile, profile)
      })
  }

  @Builder
  private buildAutoSnapshot() {
    Checkbox()
      .select(this.autoSnapshotOnExit)
      .onChange((value: boolean) => {
        AppStorage.setOrCreate(appOption.autoSnapshotOnExit, value)
      })
  }

  @Builder
  private buildShowLauncherToggle() {
    Toggle({ type: ToggleType.Switch, isOn: this.showLauncher })
      .selectedColor('#4FC3F7')
      .onChange((isOn: boolean) => {
        AppStorage.setOrCreate(appOption.showLauncher, isOn)
      })
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

            SettingItem({
              title: '主题配色',
              subTitle: '选择终端配色方案',
              content: () => {
                this.buildTerminalTheme()
              }
            })

            if (this.isThemeCustom()) {
              this.buildCustomThemeEditor()
            }

            SettingItem({
              title: '字体',
              subTitle: '选择终端字体（需重启生效）',
              content: () => {
                this.buildTerminalFont()
              }
            })

            if (this.isFontCustom()) {
              this.buildCustomFontEditor()
            }
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
              title: $r('app.string.keep_awake'),
              subTitle: $r('app.string.keep_awake_desc'),
              content: () => {
                this.setKeepAwake()
              }
            }).onClick(() => {
              AppStorage.setOrCreate(appOption.keepAwake, !this.keepAwake)
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

            SettingItem({
              title: '性能预设',
              subTitle: '均衡/省电/性能，重启 VM 生效',
              content: () => {
                this.buildPerformanceProfile()
              }
            })

            SettingItem({
              title: '退出时自动快照',
              subTitle: '退出 VM 前自动保存快照，下次恢复状态',
              content: () => {
                this.buildAutoSnapshot()
              }
            })

            SettingItem({
              title: '启动时显示固件选择',
              subTitle: '关闭后直接启动上次使用的模拟器',
              content: () => {
                this.buildShowLauncherToggle()
              }
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

  async saveTermCursorShape() {
    await savePreference(appOption.terminalCursorShape, this.termCursorShape, this.getUIContext())
  }

  async saveTermCursorBlink() {
    await savePreference(appOption.terminalCursorBlink, this.termCursorBlink, this.getUIContext())
  }

  async saveRunningInBackground() {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (this.runningInBackground) {
      const success = await backgroundRunningManager.startBackground(context)
      if (!success) {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.failed_to_force_background'),
          duration: 5000
        })
      }
    }
    await savePreference(appOption.runningInBackground, this.runningInBackground, this.getUIContext())
  }

  async saveKeepAwake() {
    await savePreference(appOption.keepAwake, this.keepAwake, this.getUIContext())
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

  async saveTerminalTheme() {
    await savePreference(appOption.terminalTheme, this.terminalTheme, this.getUIContext())
  }

  async saveTerminalFont() {
    await savePreference(appOption.terminalFont, this.terminalFont, this.getUIContext())
  }

  async saveAutoSnapshot() {
    await savePreference(appOption.autoSnapshotOnExit, this.autoSnapshotOnExit, this.getUIContext())
  }

  async savePerformanceProfile() {
    await savePreference(appOption.performanceProfile, this.performanceProfile, this.getUIContext())
  }

  async saveShowLauncher() {
    await savePreference(appOption.showLauncher, this.showLauncher, this.getUIContext())
  }
}
