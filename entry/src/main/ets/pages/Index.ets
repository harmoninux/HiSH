import { webview } from '@kit.ArkWeb';
import { deviceInfo } from '@kit.BasicServicesKit';
import WebTerminal from '../components/WebTerminal'

@Entry
@Component
struct Index {
  isPc: boolean = deviceInfo.deviceType === '2in1'

  aboutToAppear(): void {
    webview.WebviewController.setWebDebuggingAccess(true)
  }

  build() {
    Column() {
      if (this.isPc) {
        Row() {
          Row() {
            Image($r('app.media.startIcon'))
              .width(20)
            Text($r('app.string.app_name'))
              .margin({ left: 10 })
          }

          Row().layoutWeight(1)

          Row() {
            Image($r('app.media.settings'))
              .width(28)
              .aspectRatio(1)
              .padding(4)
              .borderRadius(4)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => {

              })
          }
        }
        .width('100%')
        .height(48)
        .padding({
          left: 15,
          right: 150,
        })

        WebTerminal({ showVirtKey: !this.isPc })
          .layoutWeight(1)
      } else {
        WebTerminal({ showVirtKey: !this.isPc })
      }
    }
    .width("100%")
    .height('100%')
  }
}
