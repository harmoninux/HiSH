import util from '@ohos.util';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import napi from 'libentry.so';
import { webview } from '@kit.ArkWeb';
import { pasteboard } from '@kit.BasicServicesKit'
import appOption from '../model/appOption';

const DOMAIN = 0x0000;

const VKeyMargin = 5;
const VKeyPadding = 8;
const VKeyHeight = 28;

function stringToArrayBuffer(str: string, encoding: buffer.BufferEncoding = 'utf-8'): ArrayBuffer {
  const buf = buffer.from(str, encoding);
  return buf.buffer;
}

@Component
export default struct WebTerminal {
  @Require showVirtKey: boolean
  @State ctrlPressed: boolean = false
  @Watch('onFontSizeChanged') @StorageProp(appOption.terminalFontSize) terminalFontSize: number | null = null
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

  build() {
    Column() {
      Web({
        src: $rawfile('term/term.html'),
        controller: this.webviewController
      })
        .javaScriptProxy({
          object: this,
          name: 'native',
          methodList: ['sendInput', 'resize', 'load', 'getFontSize'],
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
      if (this.showVirtKey) {
        Row() {
          Button('Tab')
            .height(VKeyHeight)
            .margin({ left: VKeyMargin })
            .padding({ left: VKeyPadding, right: VKeyPadding })
            .onClick(() => {
              this.sendInput('\t');
            })
          Toggle({ type: ToggleType.Button, isOn: this.ctrlPressed }) {
            Text('Ctrl')
              .height(20)
          }
          .height(VKeyHeight)
          .margin({ left: VKeyMargin })
          .selectedColor($r('sys.color.interactive_active'))
          .onClick(() => this.toggleCtrl())

          Button('Esc')
            .height(VKeyHeight)
            .margin({ left: VKeyMargin })
            .padding({ left: VKeyPadding, right: VKeyPadding })
            .onClick(() => {
              this.sendInput('\x1b');
            })

          Row().layoutWeight(1)

          Button('↑')
            .height(VKeyHeight)
            .margin({ right: VKeyMargin })
            .padding({ left: VKeyPadding, right: VKeyPadding })
            .onClick(() => {
              this.sendInput('\x1b[A');
            })
          Button('↓')
            .height(VKeyHeight)
            .margin({ right: VKeyMargin })
            .padding({ left: VKeyPadding, right: VKeyPadding })
            .onClick(() => {
              this.sendInput('\x1b[B');
            })
          Button('←')
            .height(VKeyHeight)
            .margin({ right: VKeyMargin })
            .padding({ left: VKeyPadding, right: VKeyPadding })
            .onClick(() => {
              this.sendInput('\x1b[D');
            })
          Button('→')
            .height(VKeyHeight)
            .margin({ right: VKeyMargin })
            .padding({ left: VKeyPadding, right: VKeyPadding })
            .onClick(() => {
              this.sendInput('\x1b[C');
            })
        }
        .margin({ left: 5, right: 5 })
      }
    }
    .height('100%')
  }

  private toggleCtrl() {
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
  }

  async resize(): Promise<void> {
  }

  getFontSize(): number | null {
    return this.terminalFontSize
  }

  onFontSizeChanged() {
    this.webviewController.runJavaScript(`exports.setFontSize(${this.terminalFontSize})`)
  }

  private onData(ab: ArrayBuffer) {
    let s: string = this.utf8Decoder.decodeToString(new Uint8Array(ab), { stream: true });
    hilog.info(DOMAIN, 'WebTerminal', 'write, data: %{public}s', s);
    this.webviewController.runJavaScript('exports.write("' + s + '")');
  }

  private onClose() {
  }
}
