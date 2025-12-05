import UserGuide from '../components/UserGuide'
import { ComposeTitleBar } from '@kit.ArkUI'

@Entry
@Component
struct UserGuidePage {
  build() {
    Column() {
      ComposeTitleBar({
        title: $r('app.string.user_guide')
      })
      UserGuide({
        openPage: (title: string, url: string) => {
          this.getUIContext().getRouter().pushUrl({
            url: 'pages/GuideWebPage',
            params: { page: url, title: title }
          })
        }
      }).layoutWeight(1)
    }
  }
}