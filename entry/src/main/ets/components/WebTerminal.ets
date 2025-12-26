import util from '@ohos.util';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import napi from 'libentry.so';
import { webview } from '@kit.ArkWeb';
import { pasteboard } from '@kit.BasicServicesKit'
import appOption, { CursorShape, savePreference } from '../model/appOption';
import { common } from '@kit.AbilityKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';

const DOMAIN = 0x0000;

const VKeyMargin = 2;
const VKeyPadding = 8;
const VKeyHeight = 28;
const VKeyWidth = 50;
const VKeyRadius = 5;

function stringToArrayBuffer(str: string, encoding: buffer.BufferEncoding = 'utf-8'): ArrayBuffer {
  const buf = buffer.from(str, encoding);
  return buf.buffer;
}

@Component
export default struct WebTerminal {
  @Require virtKeyEnabled: boolean
  @State ctrlPressed: boolean = false
  @Watch('onFontSizeChanged') @StorageProp(appOption.terminalFontSize) fontSize: number | null = null
  @Watch('onCursorShapeChanged') @StorageProp(appOption.terminalCursorShape) cursorShape: CursorShape | null = null
  @Watch('onCursorBlinkChanged') @StorageProp(appOption.terminalCursorBlink) cursorBlink: boolean | null = null
  @Watch('saveShowVirtKey') @StorageProp(appOption.showVirtKey) showVirtKey: boolean = true
  webviewController: WebviewController = new webview.WebviewController()
  utf8Decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })

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

  @Builder
  buildVKey(name: string, value: string) {
    Button(name, { buttonStyle: ButtonStyleMode.TEXTUAL })
      .height(VKeyHeight)
      .width(VKeyWidth)
      .borderRadius(VKeyRadius)
      .fontColor($r('sys.color.white'))
      .margin(VKeyMargin)
      .padding({ left: VKeyPadding, right: VKeyPadding })
      .onClick(() => {
        this.sendInput(value);
      })
  }

  @Builder
  toggleVKey(name: string, action: () => void) {
    Toggle({ type: ToggleType.Button, isOn: this.ctrlPressed }) {
      Text(name).height(28).fontWeight(FontWeight.Medium)
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
    .bindMenu([{
      value: '模拟器管理',
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.more')).fontSize($r('sys.float.Title_S')),
      action: () => this.getUIContext().getRouter().pushUrl({ url: 'pages/EmulatorManagementPage' })
    }, {
      value: '共享文件夹',
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.folder')).fontSize($r('sys.float.Title_S')),
      action: () => this.getUIContext().getRouter().pushUrl({ url: 'pages/SharedFolderPage' })
    }, {
      value: '设置',
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.gearshape')).fontSize($r('sys.float.Title_S')),
      action: () => this.getUIContext().getRouter().pushUrl({ url: 'pages/SettingsPage' })
    }])
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
            'getFontSize', 'getCursorShape', 'getCursorBlink'],
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
    Row() {
      this.buildVKey('ESC', '\x1b');

      Row().layoutWeight(1);

      this.buildVKey('PGUP', '\x1b[5~');
      this.buildVKey('HOME', '\x1b[H');
      this.buildVKey('↑', '\x1b[A');
      this.buildVKey('END', '\x1b[F');
      this.settingsButton();
    }
    .margin({ left: 5, right: 5 })

    Row() {
      this.buildVKey('TAB', '\t');
      this.toggleVKey('CTRL', () => this.toggleCtrl());

      Row().layoutWeight(1);

      this.buildVKey('PGDN', '\x1b[6~');
      this.buildVKey('←', '\x1b[D');
      this.buildVKey('↓', '\x1b[B');
      this.buildVKey('→', '\x1b[C');
      this.hideVKeyButton();
    }
    .margin({ left: 5, right: 5 })
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
    this.webviewController.runJavaScript('exports.setCtrlPressed(' + this.ctrlPressed + ')')
  }

  //  ============== for javascript in ArkWeb ================

  sendInput(data: string): void {
    hilog.info(DOMAIN, 'WebTerminal', 'sendInput, data: %{public}s', data);
    let buffer = stringToArrayBuffer(data, 'utf-8');
    napi.sendInput(buffer)

    if (this.ctrlPressed) {
      this.toggleCtrl()
    }
  }

  async load(): Promise<void> {
    this.webviewController.runJavaScript('exports.setFocused(true)')
    napi.onData((d: ArrayBuffer) => this.onData(d))
    napi.onShutdown(() => this.onShutdown())
  }

  async resize(width: number, height: number): Promise<void> {
    hilog.info(DOMAIN, "WebTerminal", 'on resize: %{public}d, %{public}d', width, height)
    // this.sendInput('\x1b' + `SR${height},${width}` + '\n')
    //  or
    this.sendInput('\x1b' + `[8;${height};${width}t` + '\n')
  }

  private onData(ab: ArrayBuffer) {
    let s: string = this.utf8Decoder.decodeToString(new Uint8Array(ab), { stream: true });
    hilog.info(DOMAIN, 'WebTerminal', 'write, data: %{public}s', s);
    if (s.startsWith('\\x1b[H\\x1b[J')) {
      this.webviewController.runJavaScript('exports.clear()');
    }
    this.webviewController.runJavaScript('exports.write("' + s + '")');
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

  onFontSizeChanged() {
    this.webviewController.runJavaScript(`exports.setFontSize(${this.fontSize})`)
  }

  onCursorShapeChanged() {
    this.webviewController.runJavaScript(`exports.setCursorShape('${this.cursorShape}')`)
  }

  onCursorBlinkChanged() {
    this.webviewController.runJavaScript(`exports.setCursorBlink(${this.cursorBlink})`)
  }
}
