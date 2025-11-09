import { webview } from "@kit.ArkWeb";

@Component
export struct SimpleWebView {
  @Require url: string
  webController = new webview.WebviewController()

  build() {
    Web({
      src: $rawfile(this.url),
      controller: this.webController
    }).javaScriptProxy({
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
      controller: this.webController
    })
      .width('100%')
      .height('100%')
      .backgroundColor('#000000');
  }
}