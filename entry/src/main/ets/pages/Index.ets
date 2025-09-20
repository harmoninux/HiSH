import { CustomContentDialog } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { deviceInfo } from '@kit.BasicServicesKit';
import WebTerminal from '../components/WebTerminal'
import SettingsContent from '../components/SettingsContent';

@Entry
@Component
struct Index {
  isPc: boolean = deviceInfo.deviceType === '2in1'
  settingController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.Setting_title'),
      contentBuilder: () => {
        this.buildSettings();
      },
      buttons: [{
        value: $r('app.string.SettingComplete_label'),
        buttonStyle: ButtonStyleMode.TEXTUAL,
        action: () => {
          this.settingController.close()
        }
      }]
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  })

  aboutToAppear(): void {
    // webview.WebviewController.setWebDebuggingAccess(true)
  }

  @Builder
  buildSettings() {
    SettingsContent()
  }

  openSettings() {
    this.settingController.open()
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

          Blank()

          Row() {
            Image($r('app.media.gearshape'))
              .width(28)
              .aspectRatio(1)
              .padding(4)
              .borderRadius(4)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => {
                this.openSettings()
              })
          }
        }
        .width('100%')
        .height(48)
        .padding({
          left: 15,
          right: 150,
        })

        WebTerminal({ showVirtKey: false })
          .layoutWeight(1)
      } else {
        WebTerminal({
          showVirtKey: true,
          openSettings: () => {
            this.openSettings();
          }
        })
      }
    }
    .width("100%")
    .height('100%')
  }
}
