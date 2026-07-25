import { ComposeTitleBar } from '@kit.ArkUI'
import SettingsContent from '../components/SettingsContent'

@Entry
@Component
export struct SettingsPage {
  build() {
    Column() {
      ComposeTitleBar({
        title: $r('app.string.Setting_title')
      })
      Column() {
        SettingsContent()
      }
    }
    .width('100%')
    .height('100%')
  }
}