import util from '@ohos.util';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import napi from 'libentry.so';
import { webview } from '@kit.ArkWeb';
import { deviceInfo } from '@kit.BasicServicesKit';
import vmOption from '../model/vmOption'

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
  openSettings?: () => void
  @StorageProp(vmOption.cpuCountName) vmCpuCount: number = 1
  @StorageProp(vmOption.memSizeName) vmMemSize: number = 512
  @State ctrlPressed: boolean = false
  webviewController: WebviewController = new webview.WebviewController()
  utf8Decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })

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
          if (this.openSettings) {
            Button() {
              Image($r('app.media.gearshape'))
                .width(16)
            }
            .height(VKeyHeight)
            .margin({ right: VKeyMargin })
            .padding({ left: VKeyPadding, right: VKeyPadding })
            .onClick(() => {
              this.openSettings!()
            })
          }
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
    hilog.info(DOMAIN, 'WebTerminal', 'startVM with cpu: %{public}d, mem: %{public}dMB', this.vmCpuCount,
      this.vmMemSize)
    this.webviewController.runJavaScript('exports.setFocused(true)')
    napi.startVM({
      cpuCount: this.vmCpuCount,
      memSize: this.vmMemSize,
      onData: (d: ArrayBuffer) => this.onData(d),
      onExit: () => this.onClose()
    })
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
    let s: string = this.utf8Decoder.decodeToString(new Uint8Array(ab), { stream: true });
    hilog.info(DOMAIN, 'WebTerminal', 'write, data: %{public}s', s);
    this.webviewController.runJavaScript('exports.write("' + s + '")');
  }

  private onClose() {
  }
}
