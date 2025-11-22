import UserGuide from '../components/UserGuide'

@Entry
@Component
struct UserGuidePage {
  build() {
    Column() {
      UserGuide({
        openPage: (title: string, url: string) => {
          this.getUIContext().getRouter().pushUrl({
            url: 'pages/GuideWebPage',
            params: { page: url }
          })
        }
      })
    }
  }
}