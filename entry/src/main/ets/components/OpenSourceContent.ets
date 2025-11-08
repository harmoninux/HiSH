import { webview } from '@kit.ArkWeb';
import { common, Want } from '@kit.AbilityKit';


@Component
export struct OpenSourceContent {
  webController: webview.WebviewController = new webview.WebviewController()

  build() {
    Web({ src: $rawfile('pages/osl.html'), controller: this.webController })
      .onLoadIntercept((e: OnLoadInterceptEvent) => {
        let url = e.data.getRequestUrl();
        if (url.startsWith('http')) {
          this.toWebBrowser(e.data.getRequestUrl());
          return true;
        } else {
          return false;
        }
      })
      .backgroundColor('#000000')
  }

  async toWebBrowser(url: string): Promise<void> {
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