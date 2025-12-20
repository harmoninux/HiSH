import { webview } from '@kit.ArkWeb'
import { ComposeTitleBar } from '@kit.ArkUI'
import { common, Want } from '@kit.AbilityKit'

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
        .onOverrideUrlLoading((r: WebResourceRequest) => {
          const url = r.getRequestUrl()
          this.toWebBrowser(url)
          return true
        })
    }
    .height('100%')
  }

  setTitle(title: string) {
    this.title = title
  }

  private async toWebBrowser(url: string): Promise<void> {
    let context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    let want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url,
      parameters: {
        bundleName: context.abilityInfo.bundleName
      }
    };
    await context.startAbility(want);
  }
}