import util from '@ohos.util';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import napi from 'libentry.so';
import { webview } from '@kit.ArkWeb';
import { deviceInfo } from '@kit.BasicServicesKit';
import appOption, { PortMapping } from '../model/appOption'

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
  @Require showVirtKey: boolean = false
  openSettings?: () => void
  @StorageProp(appOption.cpuCountName) vmCpuCount: number = 1
  @StorageProp(appOption.memSizeName) vmMemSize: number = 512
  @StorageProp(appOption.portMappingEnabled) portMappingEnabled: boolean = false
  @StorageProp(appOption.portMapping) portMapping: PortMapping[] = []
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
    napi.sendInput(buffer)

    if (this.ctrlPressed) {
      this.toggleCtrl()
    }
  }

  async load(): Promise<void> {
    this.webviewController.runJavaScript('exports.setFocused(true)')
    const appContext = this.getUIContext().getHostContext()?.getApplicationContext()!
    //  hostfwd=tcp::8080-:80,hostfwd=tcp::2222-:22
    const portMapping = this.portMappingEnabled
      ? this.portMapping.map(it => `hostfwd=tcp::${it.host}-:${it.guest}`).join(',')
      : '';
    hilog.info(DOMAIN, 'WebTerminal', 'startVM with cpu: %{public}d, mem: %{public}dMB, portMapping: %{public}s',
      this.vmCpuCount, this.vmMemSize, portMapping)
    const options: napi.appOptions = {
      bundleCodeDir: appContext.bundleCodeDir,
      tempDir: appContext.tempDir,
      filesDir: appContext.filesDir,
      cpuCount: this.vmCpuCount,
      memSize: this.vmMemSize,
      portMapping: portMapping,
      onData: (d: ArrayBuffer) => this.onData(d),
      onExit: () => this.onClose()
    }
    napi.startVM(options)
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
