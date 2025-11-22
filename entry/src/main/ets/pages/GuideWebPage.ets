import { webview } from '@kit.ArkWeb'

@Entry
@Component
struct GuideWebPage {
  page: string = (this.getUIContext().getRouter().getParams() as Record<string, string>)['page']!!
  controller: WebviewController = new webview.WebviewController()

  build() {
    Column() {
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
          methodList: [],
          controller: this.controller
        })
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.black'))
    }
    .height('100%')
  }
}