import util from '@ohos.util';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import napi from 'libentry.so';
import { webview } from '@kit.ArkWeb';
import { pasteboard, deviceInfo } from '@kit.BasicServicesKit'
import appOption, { CursorShape, savePreference } from '../model/appOption';
import { common } from '@kit.AbilityKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import stringToArrayBuffer from '../lib/stringToArrayBuffer';

const DOMAIN = 0x0000;

// 根据设备类型调整虚拟按键尺寸
const isPhone = deviceInfo.deviceType === 'phone';
const VKeyMargin = isPhone ? 1 : 2;
const VKeyPadding = isPhone ? 2 : 4;
const VKeyHeight = 28;
const VKeyWidth = isPhone ? 48 : 60;
const VKeyFontSize = isPhone ? 11 : 14;
const VKeyRadius = 5;

@Component
export default struct WebTerminal {
  @Require virtKeyEnabled: boolean
  @State ctrlPressed: boolean = false
  @State shiftPressed: boolean = false
  @Watch('onFontSizeChanged') @StorageProp(appOption.terminalFontSize) fontSize: number | null = null
  @Watch('onCursorShapeChanged') @StorageProp(appOption.terminalCursorShape) cursorShape: CursorShape | null = null
  @Watch('onCursorBlinkChanged') @StorageProp(appOption.terminalCursorBlink) cursorBlink: boolean | null = null
  @Watch('saveShowVirtKey') @StorageProp(appOption.showVirtKey) showVirtKey: boolean = true
  @StorageProp(appOption.vncEnabled) vncEnabled: boolean = true
  webviewController: WebviewController = new webview.WebviewController()
  utf8Decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
  resizeTimeout?: number = undefined
  applicationMode: boolean = false
  ports?: webview.WebMessagePort[] = undefined

  @Builder
  contextMenu(webController: WebviewController) {
    Flex({
      direction: FlexDirection.Column
    }) {
      MenuItem({ content: $r('app.string.copy_text') })
        .width('100%')
        .onClick(async () => {
          const selection = await webController.runJavaScript('exports.copy()')
          if (selection !== '""') {
            let text: string = JSON.parse(selection);
            const board = pasteboard.getSystemPasteboard()
            const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
            board.setData(pasteData)
          }
        })
      MenuItem() {
        PasteButton({ buttonType: ButtonType.ROUNDED_RECTANGLE })
          .onClick(async (event: ClickEvent, result: PasteButtonOnClickResult) => {
            if (PasteButtonOnClickResult.SUCCESS === result) {
              let board = pasteboard.getSystemPasteboard();
              const data = await board.getData()
              const text = data.getPrimaryText()
              const array = util.TextEncoder.create().encodeInto(text)
              const base64 = new util.Base64Helper().encodeToStringSync(array)
              webController.runJavaScript(`exports.paste(atob('${base64}'))`)
            }
          })
          .width('100%')
          .align(Alignment.Start)
          .backgroundColor('#292b2e')
      }
    }
    .width('160vp')
  }

  /**
   * @param appCode code used in application mode
   */
  @Builder
  buildVKey(name: string, value: string, appCode?: string) {
    Button(name, { buttonStyle: ButtonStyleMode.TEXTUAL })
      .height(VKeyHeight)
      .width(VKeyWidth)
      .borderRadius(VKeyRadius)
      .fontSize(VKeyFontSize)
      .fontColor($r('sys.color.white'))
      .margin(VKeyMargin)
      .padding({ left: VKeyPadding, right: VKeyPadding })
      .onClick(() => {
        if (this.applicationMode && appCode) {
          this.sendInput(appCode);
        } else {
          this.sendInput(value)
        }
      })
  }

  @Builder
  toggleCtrlKey(name: string, action: () => void) {
    Toggle({ type: ToggleType.Button, isOn: this.ctrlPressed }) {
      Text(name).fontSize(VKeyFontSize).fontWeight(FontWeight.Medium)
    }
    .height(VKeyHeight)
    .width(VKeyWidth)
    .borderRadius(VKeyRadius)
    .margin(VKeyMargin)
    .backgroundColor($r('sys.color.black'))
    .selectedColor($r('sys.color.interactive_active'))
    .onClick(() => action())
  }

  @Builder
  toggleShiftKey(name: string, action: () => void) {
    Toggle({ type: ToggleType.Button, isOn: this.shiftPressed }) {
      Text(name).fontSize(VKeyFontSize).fontWeight(FontWeight.Medium)
    }
    .height(VKeyHeight)
    .width(VKeyWidth)
    .borderRadius(VKeyRadius)
    .margin(VKeyMargin)
    .backgroundColor($r('sys.color.black'))
    .selectedColor($r('sys.color.interactive_active'))
    .onClick(() => action())
  }

  @Builder
  settingsButton() {
    Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image($r('app.media.gearshape')).width(16).height(16).padding(0)
    }
    .height(VKeyHeight)
    .width(VKeyHeight)
    .borderRadius(VKeyRadius)
    .margin(VKeyMargin)
    .bindMenu(this.settingsButtonOptions())
  }

  private settingsButtonOptions(): MenuElement[] {
    const vncOptions: MenuElement[] = this.vncEnabled ? [{
      value: $r('app.string.vnc_console_title'),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.display')).fontSize($r('sys.float.Title_S')),
      action: () => {
        const vncPort = AppStorage.get<number>('vncWebSocketPort');
        if (vncPort) {
          this.getUIContext().getRouter().pushUrl({
            url: 'pages/VncPage',
            params: { vncPort: vncPort }
          });
        } else {
          this.getUIContext().getPromptAction().showToast({ message: $r('app.string.vnc_service_not_started') });
        }
      }
    }] : []
    const regularOptions: MenuElement[] = [{
      value: $r('app.string.menu_emulator_management'),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.more')).fontSize($r('sys.float.Title_S')),
      action: () => this.getUIContext().getRouter().pushUrl({ url: 'pages/EmulatorManagementPage' })
    }, {
      value: $r('app.string.menu_shared_folder'),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.folder')).fontSize($r('sys.float.Title_S')),
      action: () => this.getUIContext().getRouter().pushUrl({ url: 'pages/SharedFolderPage' })
    }, {
      value: $r('app.string.menu_settings'),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.gearshape')).fontSize($r('sys.float.Title_S')),
      action: () => this.getUIContext().getRouter().pushUrl({ url: 'pages/SettingsPage' })
    }]
    return [...vncOptions, ...regularOptions];
  }

  @Builder
  hideVKeyButton() {
    Button('▼', { buttonStyle: ButtonStyleMode.TEXTUAL })
      .height(VKeyHeight)
      .width(VKeyHeight)
      .borderRadius(VKeyRadius)
      .margin(VKeyMargin)
      .padding({ left: VKeyPadding, right: VKeyPadding })
      .fontColor($r('sys.color.white'))
      .onClick(() => {
        this.showVirtKey = false
      })
  }

  build() {
    Column() {
      Web({
        src: $rawfile('term/term.html'),
        controller: this.webviewController
      })
        .javaScriptProxy({
          object: this,
          name: 'native',
          methodList: ['sendInput', 'resize', 'load',
            'getFontSize', 'getCursorShape', 'getCursorBlink',
            'setApplicationMode'],
          controller: this.webviewController,
          asyncMethodList: [],
          permission: `{
          "javascriptProxyPermission": {
            "urlPermissionList": [
              {
                "scheme": "resource",
                "host": "rawfile",
                "port": "",
                "path": ""
              }
            ]
          }
        }`
        })
        .backgroundColor('#000')
        .layoutWeight(1)
        .bindContextMenu(this.contextMenu(this.webviewController), ResponseType.RightClick)
      if (this.virtKeyEnabled) {
        if (this.showVirtKey) {
          this.buildVirtualKeys()
        } else {
          this.buildShowVirtualKeysButton()
        }
      }
    }
    .height('100%')
  }

  @Builder
  buildShowVirtualKeysButton() {
    Column() {
      Button('▲', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .width(120)
        .height(16)
        .fontSize(16)
        .borderRadius(VKeyRadius)
        .fontColor('#444')
        .padding({ left: VKeyPadding, right: VKeyPadding })
        .onClick(() => {
          this.showVirtKey = true
        })
    }
    .width('100%')
  }

  @Builder
  buildVirtualKeys() {
    Column() {
      Row() {
        this.buildVKey('ESC', '\x1b');
        this.toggleShiftKey('SHIFT', () => this.toggleShift());

        Row().layoutWeight(1);

        this.buildVKey('PGUP', '\x1b[5~');
        this.buildVKey('HOME', '\x1b[H');
        this.buildVKey('↑', '\x1b[A', '\x1bOA');
        this.buildVKey('END', '\x1b[F');

        this.settingsButton();
      }
      .margin({ left: 5, right: 5 })

      Row() {
        this.buildVKey('TAB', '\t');
        this.toggleCtrlKey('CTRL', () => this.toggleCtrl());

        Row().layoutWeight(1);

        this.buildVKey('PGDN', '\x1b[6~');
        this.buildVKey('←', '\x1b[D', '\x1bOD');
        this.buildVKey('↓', '\x1b[B', '\x1bOB');
        this.buildVKey('→', '\x1b[C', '\x1bOC');
        this.hideVKeyButton();
      }
      .margin({ left: 5, right: 5 })
    }
  }

  async saveShowVirtKey() {
    await savePreference(appOption.showVirtKey, this.showVirtKey, this.getUIContext())
    if (!this.showVirtKey) {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.hide_virtual_key_toast'),
        duration: 5000
      })
    }
  }

  private toggleCtrl(): void {
    this.ctrlPressed = !this.ctrlPressed;
  }

  private toggleShift(): void {
    this.shiftPressed = !this.shiftPressed;
  }

  //  ============== for javascript in ArkWeb ================

  sendInput(data: string): void {
    hilog.info(DOMAIN, 'WebTerminal', 'sendInput, data: %{public}s', data);

    // 处理 Ctrl 状态：将小写字母转换为控制字符（一次性，发送后自动重置）
    if (this.ctrlPressed && data.length === 1) {
      const char = data.charAt(0);
      if (char >= 'a' && char <= 'z') {
        data = String.fromCharCode(char.charCodeAt(0) - 'a'.charCodeAt(0) + 1);
        hilog.info(DOMAIN, 'WebTerminal', 'sendInput with Ctrl, converted to control char');
      }
      // 一次性发送后自动重置 Ctrl 状态
      this.toggleCtrl()
    }

    // 处理 Shift 状态：将小写字母转换为大写
    if (this.shiftPressed && data.length === 1) {
      const char = data.charAt(0);
      if (char >= 'a' && char <= 'z') {
        data = char.toUpperCase();
        hilog.info(DOMAIN, 'WebTerminal', 'sendInput with Shift, converted to: %{public}s', data);
      }
    }

    let buffer = stringToArrayBuffer(data, 'utf-8');
    napi.sendInput(buffer)

    // Ctrl: 一次性模式，发送后自动重置 | Shift: 状态保持，需要用户手动点击取消
  }

  async load(): Promise<void> {
    this.webviewController.runJavaScript('exports.setFocused(true)')

    this.ports = this.webviewController.createWebMessagePorts()
    this.ports![1].onMessageEvent((r) => {
      console.log(r.toString())
    })
    this.webviewController.postMessage('__init_port__', [this.ports[0]], '*')

    napi.onData((d: ArrayBuffer) => this.onData(d))
    napi.onShutdown(() => this.onShutdown())
  }

  async resize(width: number, height: number): Promise<void> {
    hilog.info(DOMAIN, "WebTerminal", 'on resize: %{public}d, %{public}d', width, height)

    if (this.resizeTimeout !== undefined) {
      clearTimeout(this.resizeTimeout!!)
    }
    this.resizeTimeout = setTimeout(() => this.sendInput('\x1b' + `[8;${height};${width}t`), 100)
  }

  private onData(ab: ArrayBuffer) {
    let s: string = this.utf8Decoder.decodeToString(new Uint8Array(ab), { stream: true });
    hilog.info(DOMAIN, 'WebTerminal', 'write, data: %{public}s', s);
    if (s.startsWith('\x1b[H\x1b[J')) {
      this.ports![1].postMessageEvent('\x1b[3J')
    }
    this.ports![1].postMessageEvent(s)
  }

  private async onShutdown() {
    hilog.info(DOMAIN, 'WebTerminal', 'qemu system exited');
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    await context?.terminateSelf()
  }

  getFontSize(): number | null {
    return this.fontSize
  }

  getCursorShape(): string | null {
    return this.cursorShape
  }

  getCursorBlink(): boolean | null {
    return this.cursorBlink
  }

  getDeviceType(): string {
    return deviceInfo.deviceType;
  }

  onFontSizeChanged() {
    this.webviewController.runJavaScript(`exports.setFontSize(${this.fontSize})`)
  }

  onCursorShapeChanged() {
    this.webviewController.runJavaScript(`exports.setCursorShape('${this.cursorShape}')`)
  }

  onCursorBlinkChanged() {
    this.webviewController.runJavaScript(`exports.setCursorBlink(${this.cursorBlink})`)
  }

  setApplicationMode(mode: boolean) {
    this.applicationMode = mode
    hilog.info(DOMAIN, 'WebTerminal', 'set applicationMode to %{public}s', this.applicationMode);
  }
}
