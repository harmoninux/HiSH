import util from '@ohos.util';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import napi from 'libentry.so';
import { webview } from '@kit.ArkWeb';

const DOMAIN = 0x0000;

function stringToArrayBuffer(str: string, encoding: buffer.BufferEncoding = 'utf-8'): ArrayBuffer {
  const buf = buffer.from(str, encoding);
  return buf.buffer;
}

interface Size {
  width: number,
  height: number
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

    const size: Size = await this.getSize();
    napi.startVM(size.width, size.height,
      (d: ArrayBuffer) => this.onData(d), () => this.onClose())
  }

  private onData(ab: ArrayBuffer) {
    let dec = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    let s: string = dec.decodeToString(new Uint8Array(ab));
    hilog.info(DOMAIN, 'WebTerminal', 'write, data: %{public}s', s);
    this.controller.runJavaScript('exports.write("' + s + '")');
  }

  private onClose() {
  }

  async resize(): Promise<void> {
    const s = await this.getSize();
  }

  private async getSize(): Promise<Size> {
    const ext = await this.controller.runJavaScriptExt('exports.getSize()');
    const arr = ext.getArray();
    return { width: arr[0] as number, height: arr[1] as number };
  }
}

@Entry
@Component
struct Index {
  @State message: string = 'Hello World';
  @State started: boolean = false
  @Require webviewController: WebviewController = new webview.WebviewController()
  @Require native: NativeProxy = new NativeProxy(this.webviewController)

  onData(a: ArrayBuffer) {
    let dec = util.TextDecoder.create('utf-8', { ignoreBOM: true })
    let s: string = dec.decodeToString(new Uint8Array(a))
    hilog.info(DOMAIN, 'WebTerminal', 'write, id: %{public}d, data: %{public}s', this.id, s)
  }

  onExit() {
  }

  build() {
    Row() {
      Web({
        src: $rawfile('term/term.html'),
        controller: this.webviewController
      })
        .javaScriptProxy({
          object: this.native,
          name: 'native',
          methodList: ['sendInput', 'resize', 'load'],
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
        .height('100%')
    }
    .height('100%')
  }
}
