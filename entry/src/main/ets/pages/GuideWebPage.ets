import { webview } from '@kit.ArkWeb'
import { ComposeTitleBar } from '@kit.ArkUI'

@Entry
@Component
struct GuideWebPage {
  page: string = (this.getUIContext().getRouter().getParams() as Record<string, string>)['page']!!
  title?: string = (this.getUIContext().getRouter().getParams() as Record<string, string>)['title']
  controller: WebviewController = new webview.WebviewController()

  build() {
    Column() {
      if (this.title) {
        ComposeTitleBar({
          title: this.title
        })
      }
      Web({
        src: $rawfile(this.page),
        controller: this.controller
      })
        .javaScriptProxy({
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
          }`,
          object: this,
          name: 'native',
          methodList: ['setTitle'],
          controller: this.controller
        })
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('sys.color.black'))
    }
    .height('100%')
  }

  setTitle(title: string) {
    this.title = title
  }
}