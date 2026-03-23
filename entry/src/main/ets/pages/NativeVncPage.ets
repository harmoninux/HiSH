import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import NativeVncViewer from '../components/NativeVncViewer';

const DOMAIN = 0x0002;

interface NativeVncPageParams {
  vncPort?: number
}

@Entry
@Component
struct NativeVncPage {
  @State vncPort: number = 5900; // 默认 VNC 端口
  @State connected: boolean = false
  @State errorMessage: string = ''

  aboutToAppear() {
    const params = router.getParams() as NativeVncPageParams;
    if (params && params.vncPort) {
      this.vncPort = params.vncPort;
    }
    hilog.info(DOMAIN, 'NativeVncPage', 'Page appeared with port: %{public}d', this.vncPort);
  }

  onConnectionFailed() {
    this.errorMessage = 'Connection failed. Please check if VNC server is running.';
    hilog.error(DOMAIN, 'NativeVncPage', 'VNC connection failed');
  }

  build() {
    Column() {
      // 顶部工具栏
      Row() {
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
        }
        .onClick(() => {
          router.back();
        })

        Text('Native VNC')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        // 占位，保持标题居中
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(24)
            .fontColor([Color.Transparent])
        }
        .visibility(Visibility.Hidden)
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 8 })
      .backgroundColor($r('sys.color.background_primary'))

      // VNC 查看器
      Column() {
        if (this.errorMessage) {
          Text(this.errorMessage)
            .fontSize(16)
            .fontColor(Color.Red)
            .textAlign(TextAlign.Center)
            .padding(20)
            .margin({ top: 20 })

          Button('Retry')
            .onClick(() => {
              this.errorMessage = '';
            })
        } else {
          NativeVncViewer({
            address: '127.0.0.1',
            port: this.vncPort,
            password: '',
            connected: this.connected,
            onConnectionFailed: () => this.onConnectionFailed()
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }
}
