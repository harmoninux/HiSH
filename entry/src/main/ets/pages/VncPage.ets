import { webview } from '@kit.ArkWeb';
import { router, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import appOption from '../model/appOption';

const DOMAIN = 0x0000;

interface VncPageParams {
  vncPort?: number
}

// Class for JS Bridge to handle fullscreen
class NativeBridge {
  private page: VncPage;

  constructor(page: VncPage) {
    this.page = page;
  }

  async enterFullscreen(): Promise<void> {
    hilog.info(DOMAIN, 'VncPage', 'enterFullscreen called from JS');
    try {
      const win = await window.getLastWindow(this.page.getUIContext().getHostContext()!!);
      
      // First maximize the window
      await win.maximize();
      hilog.info(DOMAIN, 'VncPage', 'Window maximized');
      
      // Set full screen layout
      await win.setWindowLayoutFullScreen(true);
      hilog.info(DOMAIN, 'VncPage', 'Window layout full screen enabled');
      
      // Use setSpecificSystemBarEnabled to hide system bars (API 11+)
      try {
        await win.setSpecificSystemBarEnabled('status', false);
        hilog.info(DOMAIN, 'VncPage', 'Status bar hidden via setSpecificSystemBarEnabled');
      } catch (e) {
        hilog.warn(DOMAIN, 'VncPage', 'setSpecificSystemBarEnabled(status) failed: %{public}s', JSON.stringify(e));
      }
      
      try {
        await win.setSpecificSystemBarEnabled('navigationIndicator', false);
        hilog.info(DOMAIN, 'VncPage', 'Navigation indicator hidden via setSpecificSystemBarEnabled');
      } catch (e) {
        hilog.warn(DOMAIN, 'VncPage', 'setSpecificSystemBarEnabled(navigationIndicator) failed: %{public}s', JSON.stringify(e));
      }
      
      // Try to hide window decoration (title bar and borders)
      try {
        await win.setWindowDecorVisible(false);
        hilog.info(DOMAIN, 'VncPage', 'Window decoration hidden');
      } catch (e) {
        hilog.warn(DOMAIN, 'VncPage', 'setWindowDecorVisible failed: %{public}s', JSON.stringify(e));
      }
      
      this.page.setFullscreen(true);
      hilog.info(DOMAIN, 'VncPage', 'Entered fullscreen successfully');
    } catch (e) {
      hilog.error(DOMAIN, 'VncPage', 'Failed to enter fullscreen: %{public}s', JSON.stringify(e));
    }
  }

  async exitFullscreen(): Promise<void> {
    hilog.info(DOMAIN, 'VncPage', 'exitFullscreen called from JS');
    try {
      const win = await window.getLastWindow(this.page.getUIContext().getHostContext()!!);
      
      // Exit full screen layout
      await win.setWindowLayoutFullScreen(false);
      
      // NOTE: Do NOT restore window decoration here!
      // The app is designed to be borderless (setWindowDecorVisible(false) in EntryAbility)
      // Calling setWindowDecorVisible(true) would override that setting
      
      // Restore system bars
      try {
        await win.setSpecificSystemBarEnabled('status', true);
        await win.setSpecificSystemBarEnabled('navigationIndicator', true);
      } catch (e) {
        hilog.warn(DOMAIN, 'VncPage', 'setSpecificSystemBarEnabled restore failed: %{public}s', JSON.stringify(e));
      }
      
      this.page.setFullscreen(false);
      hilog.info(DOMAIN, 'VncPage', 'Exited fullscreen successfully');
    } catch (e) {
      hilog.error(DOMAIN, 'VncPage', 'Failed to exit fullscreen: %{public}s', JSON.stringify(e));
    }
  }

  isFullscreen(): boolean {
    const result = this.page.getFullscreen();
    hilog.info(DOMAIN, 'VncPage', 'isFullscreen called, returning: %{public}s', String(result));
    return result;
  }

  getTerminalScreensaver(): number {
    return this.page.termScreensaver;
  }

  getTerminalEffectType(): string {
    return this.page.termEffectType;
  }
}

@Entry
@Component
struct VncPage {
  controller: webview.WebviewController = new webview.WebviewController();
  @State vncPort: number = 60000;
  @State isFullscreenState: boolean = false;
  @Watch('onTermScreensaverChanged') @StorageProp(appOption.terminalScreensaver) termScreensaver: number = 0
  @Watch('onTermEffectTypeChanged') @StorageProp(appOption.terminalEffectType) termEffectType: string = 'random'
  private nativeBridge: NativeBridge = new NativeBridge(this);

  onTermScreensaverChanged() {
    try {
      this.controller.runJavaScript(`window.setScreensaverTimeout(${this.termScreensaver})`)
    } catch (error) {
      hilog.warn(DOMAIN, 'VncPage', 'onTermScreensaverChanged failed: %{public}s', JSON.stringify(error));
    }
  }

  onTermEffectTypeChanged() {
    try {
      this.controller.runJavaScript(`window.setEffectType('${this.termEffectType}')`)
    } catch (error) {
      hilog.warn(DOMAIN, 'VncPage', 'onTermEffectTypeChanged failed: %{public}s', JSON.stringify(error));
    }
  }

  setFullscreen(value: boolean): void {
    this.isFullscreenState = value;
  }

  getFullscreen(): boolean {
    return this.isFullscreenState;
  }

  aboutToAppear() {
    const params = router.getParams() as VncPageParams;
    if (params && params.vncPort) {
      this.vncPort = params.vncPort;
    }
  }

  onPageShow() {
    try {
      hilog.info(DOMAIN, 'VncPage', 'onPageShow: refreshing VNC WebView and registering avoidAreaChange listener');
      this.controller.refresh();
      
      // 监听窗口避让区域变化（如软键盘弹出/收起）
      window.getLastWindow(this.getUIContext().getHostContext()!!).then((win) => {
        win.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
          if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
            const height = data.area.bottomRect.height;
            hilog.info(DOMAIN, 'VncPage', 'Keyboard avoid area changed, height: %{public}d', height);
            if (height === 0) {
              // 复用全屏切换时验证有效的 forceViewportUpdate 逻辑
              // 多次延迟触发以确保布局稳定后正确刷新
              hilog.info(DOMAIN, 'VncPage', 'Keyboard closed, triggering forceViewportUpdate');
              const callForceViewportUpdate = () => {
                try {
                  this.controller.runJavaScript('window.forceViewportUpdate && window.forceViewportUpdate()');
                } catch (e) {
                  hilog.warn(DOMAIN, 'VncPage', 'forceViewportUpdate failed: %{public}s', JSON.stringify(e));
                }
              };
              // 立即触发一次，并多次延迟触发，确保在动画不同阶段都能捕捉到正确尺寸
              callForceViewportUpdate();
              setTimeout(callForceViewportUpdate, 100);
              setTimeout(callForceViewportUpdate, 300);
              setTimeout(callForceViewportUpdate, 600);
              setTimeout(callForceViewportUpdate, 1000);
            }
          }
        });
      });
    } catch (error) {
      // 捕获 "The WebviewController must be associated with a Web component" 错误
      hilog.warn(DOMAIN, 'VncPage', 'onPageShow failed: %{public}s', JSON.stringify(error));
    }
  }

  onPageHide() {
    try {
      hilog.info(DOMAIN, 'VncPage', 'onPageHide: unregistering avoidAreaChange listener');
      window.getLastWindow(this.getUIContext().getHostContext()!!).then((win) => {
        win.off('avoidAreaChange');
      });
    } catch (error) {
      hilog.warn(DOMAIN, 'VncPage', 'onPageHide failed: %{public}s', JSON.stringify(error));
    }
  }

  build() {
    Column() {
      // 顶部工具栏 (全屏时隐藏)
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
      .visibility(this.isFullscreenState ? Visibility.None : Visibility.Visible)

      // noVNC WebView
      Web({ src: 'http://localhost/vnc.html?autoconnect=true&resize=scale&encrypt=false&path=&host=127.0.0.1&port=' + this.vncPort, controller: this.controller })
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .mixedMode(MixedMode.All)
        .javaScriptProxy({
          object: this.nativeBridge,
          name: 'native',
          methodList: ['enterFullscreen', 'exitFullscreen', 'isFullscreen', 'getTerminalScreensaver', 'getTerminalEffectType'],
          controller: this.controller
        })
        .backgroundColor('#000000')
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
              const context = this.getUIContext().getHostContext()!!;
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
    .backgroundColor('#000000')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
