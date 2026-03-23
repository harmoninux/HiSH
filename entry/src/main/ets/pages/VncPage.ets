import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import NativeVncViewer from '../components/NativeVncViewer';

const DOMAIN = 0x0000;

interface VncPageParams {
  vncPort?: number
}

@Entry
@Component
struct VncPage {
  @State vncPort: number = 5900
  @State connected: boolean = false
  @State errorMessage: string = ''

  aboutToAppear() {
    const params = router.getParams() as VncPageParams;
    if (params && params.vncPort) {
      this.vncPort = params.vncPort;
    }
    hilog.info(DOMAIN, 'VncPage', 'Page appeared with port: %{public}d', this.vncPort);
  }

  onConnectionFailed() {
    this.errorMessage = 'VNC connection failed. Please check if VNC server is running.';
    hilog.error(DOMAIN, 'VncPage', 'VNC connection failed');
  }

  build() {
    Column() {
      Button('Back')
        .onClick(() => {
          router.back();
        })

      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(16)
          .fontColor(Color.Red)
          .textAlign(TextAlign.Center)
          .padding(20)

        Button('Retry')
          .onClick(() => {
            this.errorMessage = '';
          })
      } else {
        NativeVncViewer({
          address: '127.0.0.1',
          port: this.vncPort,
          password: '',
          connected: this.connected
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .backgroundColor($r('sys.color.background_primary'))
  }
}
