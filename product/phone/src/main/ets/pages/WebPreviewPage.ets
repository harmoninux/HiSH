import { WebPreviewPage as Page } from 'hish_main';
import { webview } from '@kit.ArkWeb';

@Entry
@Component
struct Wrapper {
  private controller: webview.WebviewController = new webview.WebviewController()

  onBackPress(): boolean {
    if (this.controller.accessBackward()) {
      this.controller.backward()
      return true
    }
    return false
  }

  build() {
    Column() {
      Page({ controller: this.controller })
    }.width('100%').height('100%')
  }
}
