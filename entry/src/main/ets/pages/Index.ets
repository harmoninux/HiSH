import util from '@ohos.util';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import napi from 'libentry.so';
import { webview } from '@kit.ArkWeb';
import { deviceInfo } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;

function stringToArrayBuffer(str: string, encoding: buffer.BufferEncoding = 'utf-8'): ArrayBuffer {
  const buf = buffer.from(str, encoding);
  return buf.buffer;
}

class NativeProxy {
  controller: webview.WebviewController;

  constructor(controller: WebviewController) {
    this.controller = controller;
  }

  sendInput(data: string): void {
    hilog.info(DOMAIN, 'WebTerminal', 'sendInput, data: %{public}s', data);
    let buffer = stringToArrayBuffer(data, 'utf-8');
    napi.send(buffer)
  }

  async load(): Promise<void> {
    hilog.info(DOMAIN, 'WebTerminal', 'load')
    this.controller.runJavaScript('exports.setFocused(true)')
    napi.startVM((d: ArrayBuffer) => this.onData(d), () => this.onClose())
  }

  private onData(ab: ArrayBuffer) {
    let dec = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    let s: string = dec.decodeToString(new Uint8Array(ab));
    hilog.info(DOMAIN, 'WebTerminal', 'write, data: %{public}s', s);
    this.controller.runJavaScript('exports.write("' + s + '")');
  }

  setCtrlPressed(b: boolean) {
    this.controller.runJavaScript('exports.setCtrlPressed(' + b + ')')
  }

  private onClose() {
  }

  async resize(): Promise<void> {
  }

  getFontSize(): number | null {
    if (deviceInfo.deviceType === 'phone'
      || deviceInfo.deviceType === 'default') {
      return 13;
    }
    return null;
  }
}

@Entry
@Component
struct Index {
  @Require webviewController: WebviewController = new webview.WebviewController()
  @Require native: NativeProxy = new NativeProxy(this.webviewController)
  @Require showVirtKey: boolean = deviceInfo.deviceType !== '2in1'
  @Require ctrlPressed: boolean = false

  onData(a: ArrayBuffer) {
    let dec = util.TextDecoder.create('utf-8', { ignoreBOM: true })
    let s: string = dec.decodeToString(new Uint8Array(a))
    hilog.info(DOMAIN, 'WebTerminal', 'write, data: %{public}s', s)
  }

  aboutToAppear(): void {
    webview.WebviewController.setWebDebuggingAccess(true)
  }

  onExit() {
  }

  build() {
    Column() {
      Web({
        src: $rawfile('term/term.html'),
        controller: this.webviewController
      })
        .javaScriptProxy({
          object: this.native,
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
      if (this.showVirtKey) {
        Row() {
          Button('TAB')
            .height(28)
            .margin({ left: 5 })
            .onClick(() => {
              this.send('\t');
            })
          Toggle({ type: ToggleType.Button, isOn: this.ctrlPressed }) {
            Text('CTRL')
              .height(20)
          }
          .height(28)
          .margin({ left: 5 })
          .onClick(() => this.toggleCtrl())
          Button('ESC')
            .height(28)
            .margin({ left: 5 })
            .onClick(() => {
              this.send('\x1b');
            })

          Row().layoutWeight(1)

          Button('↑')
            .height(28)
            .margin({ right: 5 })
            .onClick(() => {
              this.send('\x1b[A');
            })
          Button('↓')
            .height(28)
            .margin({ right: 5 })
            .onClick(() => {
              this.send('\x1b[B');
            })
          Button('←')
            .height(28)
            .margin({ right: 5 })
            .onClick(() => {
              this.send('\x1b[D');
            })
          Button('→')
            .height(28)
            .margin({ right: 5 })
            .onClick(() => {
              this.send('\x1b[C');
            })
        }
        .margin(5)
      }
    }
    .height('100%')
  }

  private toggleCtrl() {
    this.ctrlPressed = !this.ctrlPressed;
    this.native.setCtrlPressed(this.ctrlPressed);
  }

  private send(b: string) {
    this.native.sendInput(b);
  }
}
