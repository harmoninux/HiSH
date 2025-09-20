import { CustomContentDialog } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { LinkItem } from "./LinkItem"
import { common, Want } from '@kit.AbilityKit';

@Component
export default struct SettingsContent {
  
  webController: webview.WebviewController = new webview.WebviewController()
  
  openSourceController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.open_source_license'),
      contentBuilder: () => {
        this.buildOpenSourceView();
      },
      buttons: [{
        value: $r('app.string.SettingComplete_label'),
        buttonStyle: ButtonStyleMode.TEXTUAL,
        action: () => {
          this.openSourceController.close();
        }
      }]
    })
  })
  
  aboutController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.about_me'),
      contentBuilder: () => {
        this.buildAboutMe();
      },
      buttons: [{
        value: $r('app.string.SettingComplete_label'),
        buttonStyle: ButtonStyleMode.TEXTUAL,
        action: () => {
          this.aboutController.close();
        }
      }]
    })
  })
  

  aboutToAppear(): void {
  }

  build() {
    Scroll() {
      Column() {

        LinkItem({
          icon: $r('sys.symbol.doc_text_badge_checkmark'),
          title: $r('app.string.open_source_license'),
          click: () => {
            this.openSourceController.open();
          }
        })

        LinkItem({
          icon: $r('sys.symbol.info_circle'),
          title: $r('app.string.about_me'),
          click: () => {
            this.aboutController.open();
          }
        })
      }
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .scrollBarWidth(1)
  }

  @Builder
  buildOpenSourceView() {
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
  }

  @Builder
  buildAboutMe() {
    Column() {

      Image($r('app.media.startIcon'))
        .width(50)

      Text($r('app.string.app_name'))
        .margin({ top: 10 })
    }
    .width('100%')
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