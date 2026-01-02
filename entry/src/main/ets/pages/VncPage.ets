import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

interface VncPageParams {
  vncPort?: number
}

@Entry
@Component
struct VncPage {
  controller: webview.WebviewController = new webview.WebviewController();
  @State vncPort: number = 60000; // 默认值，实际应从参数获取

  aboutToAppear() {
    const params = router.getParams() as VncPageParams;
    if (params && params.vncPort) {
      this.vncPort = params.vncPort;
    }
  }

  build() {
    Column() {
      // 顶部工具栏
      Row() {
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
        }
        .onClick(() => {
          router.back();
        })

        Text($r('app.string.vnc_console_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        // 占位，保持标题居中
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(24)
            .fontColor([Color.Transparent])
        }
        .visibility(Visibility.Hidden)
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 8 })
      .backgroundColor($r('sys.color.background_primary'))

      // noVNC WebView
      Web({ src: 'http://localhost/vnc.html?autoconnect=true&resize=scale&encrypt=false&path=&host=127.0.0.1&port=' + this.vncPort, controller: this.controller })
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .mixedMode(MixedMode.All)
        .onConsole((event) => {
          if (event) {
            hilog.info(DOMAIN, 'VncPage', 'WebView Console: %{public}s', event.message.getMessage());
          }
          return false;
        })
        .onInterceptRequest((event) => {
          if (event && event.request.getRequestUrl().startsWith('http://localhost/')) {
            const url = event.request.getRequestUrl();
            let path = url.replace('http://localhost/', '');
            if (path.includes('?')) {
              path = path.substring(0, path.indexOf('?'));
            }

            // 映射到 rawfile 路径
            const rawfilePath = 'novnc/' + path;

            // 确定 MIME 类型
            let mimeType = 'text/html';
            if (path.endsWith('.js')) mimeType = 'application/javascript';
            else if (path.endsWith('.css')) mimeType = 'text/css';
            else if (path.endsWith('.svg')) mimeType = 'image/svg+xml';
            else if (path.endsWith('.png')) mimeType = 'image/png';
            else if (path.endsWith('.json')) mimeType = 'application/json';
            else if (path.endsWith('.wasm')) mimeType = 'application/wasm';

            try {
              const context = getContext(this);
              const content = context.resourceManager.getRawFileContentSync(rawfilePath);

              const response = new WebResourceResponse();
              response.setResponseData(content.buffer);
              response.setResponseEncoding('utf-8');
              response.setResponseMimeType(mimeType);
              response.setResponseCode(200);
              response.setReasonMessage('OK');
              response.setResponseHeader([
                { headerKey: 'Access-Control-Allow-Origin', headerValue: '*' },
                { headerKey: 'Cross-Origin-Opener-Policy', headerValue: 'same-origin' },
                { headerKey: 'Cross-Origin-Embedder-Policy', headerValue: 'require-corp' }
              ]);
              return response;
            } catch (e) {
              hilog.error(DOMAIN, 'VncPage', 'Failed to load resource: %{public}s, error: %{public}s', rawfilePath, JSON.stringify(e));
            }
          }
          return null;
        })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }
}
