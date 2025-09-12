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

@Entry
@Component
struct Index {
  @Require webviewController: WebviewController = new webview.WebviewController()
  @Require showVirtKey: boolean = deviceInfo.deviceType !== '2in1'
  @Require @State ctrlPressed: boolean = false

  aboutToAppear(): void {
    // webview.WebviewController.setWebDebuggingAccess(true)
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
      if (this.showVirtKey) {
        Row() {
          Button('TAB')
            .height(28)
            .margin({ left: 5 })
            .padding({ left: 10, right: 10})
            .onClick(() => {
              this.sendInput('\t');
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
            .padding({ left: 10, right: 10})
            .onClick(() => {
              this.sendInput('\x1b');
            })

          Row().layoutWeight(1)

          Button('↑')
            .height(28)
            .margin({ right: 5 })
            .padding({ left: 10, right: 10})
            .onClick(() => {
              this.sendInput('\x1b[A');
            })
          Button('↓')
            .height(28)
            .margin({ right: 5 })
            .padding({ left: 10, right: 10})
            .onClick(() => {
              this.sendInput('\x1b[B');
            })
          Button('←')
            .height(28)
            .margin({ right: 5 })
            .padding({ left: 10, right: 10})
            .onClick(() => {
              this.sendInput('\x1b[D');
            })
          Button('→')
            .height(28)
            .margin({ right: 5 })
            .padding({ left: 10, right: 10})
            .onClick(() => {
              this.sendInput('\x1b[C');
            })
        }
        .margin(5)
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
    napi.send(buffer)

    if (this.ctrlPressed) {
      this.toggleCtrl()
    }
  }

  async load(): Promise<void> {
    hilog.info(DOMAIN, 'WebTerminal', 'load')
    this.webviewController.runJavaScript('exports.setFocused(true)')
    napi.startVM((d: ArrayBuffer) => this.onData(d), () => this.onClose())
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

  private onData(ab: ArrayBuffer) {
    let dec = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    let s: string = dec.decodeToString(new Uint8Array(ab));
    hilog.info(DOMAIN, 'WebTerminal', 'write, data: %{public}s', s);
    this.webviewController.runJavaScript('exports.write("' + s + '")');
  }

  private onClose() {
  }
}
