import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { ComposeTitleBar } from '@kit.ArkUI'
import { ArkTSUtils } from '@kit.ArkTS';
import napi from 'libentry.so';
import { button2rfb } from '../utils/KeyMap';
import deviceInfo from '@ohos.deviceInfo';

const DOMAIN = 0x0001;
const LOG_TAG = 'NativeVnc';

@Entry
@Component
struct VncPage {
  @State port: number = 5900

  @State connected: boolean = false
  @State isConnected: boolean = false
  @State errorMessage: string = ''
  @State statusMessage: string = ''

  @State canvasWidth: number = 0
  @State canvasHeight: number = 0

  private settings: RenderingContextSettings = new RenderingContextSettings(false)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)
  private updateInterval?: number = undefined
  private transformNeedsReset: boolean = false
  private checkVncUpdateFlag: boolean = false
  private checkVncUpdateLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock()

  // VNC frame buffer and rendering state
  private pixelArray: Uint8Array = new Uint8Array([])
  private vncWidth: number = 0
  private vncHeight: number = 0
  private leftShift: number = -1
  private upShift: number = -1
  private windowScale: number = 1
  private scaleInitialized: boolean = false
  private mouseX: number = -1
  private mouseY: number = -1
  private mouseStat: number = 0
  private needsFullRedraw: boolean = false

  aboutToAppear() {
    this.connectVnc();
  }

  aboutToDisappear() {
    this.disconnectVnc();
  }

  private connectVnc() {
    try {
      this.statusMessage = 'Connecting to VNC server...';
      const result = napi.vncInit('127.0.0.1', this.port, '');

      // vncInit returns Uint8Array (framebuffer) or null
      if (result && result instanceof Uint8Array) {
        this.pixelArray = result;
        this.isConnected = true;
        this.statusMessage = 'Connected! Waiting for VNC updates...';
        hilog.info(DOMAIN, LOG_TAG, 'VNC connected successfully, framebuffer size: %{public}d', result.length);
        this.startUpdateLoop();
      } else {
        this.errorMessage = 'Connection failed';
        this.statusMessage = 'Connection failed';
        hilog.error(DOMAIN, LOG_TAG, 'VNC init failed, result: %{public}s', JSON.stringify(result));
      }
    } catch (e) {
      this.errorMessage = 'Error: ' + JSON.stringify(e);
      this.statusMessage = 'Error: ' + JSON.stringify(e);
      hilog.error(DOMAIN, LOG_TAG, 'VNC connection error: %{public}s', JSON.stringify(e));
    }
  }

  private disconnectVnc() {
    if (this.isConnected) {
      try {
        napi.vncClose();
        this.isConnected = false;
        this.stopUpdateLoop();
        this.statusMessage = 'Disconnected';
        hilog.info(DOMAIN, LOG_TAG, 'VNC disconnected');
      } catch (e) {
        hilog.error(DOMAIN, LOG_TAG, 'Error disconnecting VNC: %{public}s', JSON.stringify(e));
      }
    }
  }

  private getUpdatePixelMap(x: number, y: number, w: number, h: number): image.PixelMap | null {
    // RGB565: 2 bytes per pixel
    const bitsPerPixel = 2;
    let freshAreaArray = new Uint8Array(h * w * bitsPerPixel);

    for (let i = 0; i < h; i++) {
      const srcStart = ((y + i) * this.vncWidth + x) * bitsPerPixel;
      const srcEnd = srcStart + w * bitsPerPixel;
      const desStart = (i * w) * bitsPerPixel;

      if (srcEnd <= this.pixelArray.length && srcStart >= 0) {
        freshAreaArray.set(this.pixelArray.subarray(srcStart, srcEnd), desStart);
      }
    }

    let opts: image.InitializationOptions = {
      alphaType: image.AlphaType.OPAQUE,
      size: { height: h, width: w },
      srcPixelFormat: image.PixelMapFormat.RGB_565,
      scaleMode: image.ScaleMode.CENTER_CROP,
      pixelFormat: image.PixelMapFormat.RGB_565,
      editable: false
    }

    try {
      return image.createPixelMapSync(freshAreaArray.buffer, opts);
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'Failed to create PixelMap: %{public}s', JSON.stringify(e));
      return null;
    }
  }

  private redrawFullCanvas() {
    if (this.vncWidth <= 0 || this.vncHeight <= 0 || this.pixelArray.length === 0) {
      hilog.warn(DOMAIN, LOG_TAG, 'Cannot redraw: invalid VNC dimensions or empty buffer');
      return;
    }

    hilog.info(DOMAIN, LOG_TAG, 'Performing full canvas redraw: %{public}dx%{public}d', this.vncWidth, this.vncHeight);

    const pixelMap = this.getUpdatePixelMap(0, 0, this.vncWidth, this.vncHeight);
    if (pixelMap) {
      // Reset transform and apply scale
      this.context.resetTransform();
      this.context.scale(this.windowScale, this.windowScale);

      // Draw full VNC screen with centering offset
      const vncLeftShift = this.leftShift / this.windowScale;
      const vncUpShift = this.upShift / this.windowScale;
      this.context.drawImage(pixelMap, px2vp(vncLeftShift), px2vp(vncUpShift));

      this.needsFullRedraw = false;
      hilog.info(DOMAIN, LOG_TAG, 'Full canvas redraw completed');
    } else {
      hilog.error(DOMAIN, LOG_TAG, 'Failed to create PixelMap for full redraw');
    }
  }

  private checkVncUpdate() {
    try {
      const result = napi.vncUpdate(
        // First callback: receives updated framebuffer (Uint8Array)
        (framebuffer: Uint8Array) => {
          this.pixelArray = framebuffer;
        },
        // Second callback: receives update info (RfbUpdateInfo)
        (updateInfo: Uint8Array) => {
          const view = new DataView(updateInfo.buffer);
          const width = view.getInt32(0, true);
          const height = view.getInt32(4, true);
          const x = view.getInt32(8, true);
          const y = view.getInt32(12, true);
          const w = view.getInt32(16, true);
          const h = view.getInt32(20, true);

          // hilog.debug(DOMAIN, LOG_TAG, 'VNC update: %{public}dx%{public}d at (%{public}d,%{public}d), %{public}dx%{public}d',
          //   width, height, x, y, w, h);

          // Update VNC dimensions on onResize
          if (width !== this.vncWidth || height !== this.vncHeight ||
            !this.scaleInitialized || this.transformNeedsReset) {
            this.vncWidth = width;
            this.vncHeight = height;

            // Only calculate scale if canvas dimensions are valid
            if (this.canvasWidth > 0 && this.canvasHeight > 0) {
              // Calculate scale to fit canvas
              this.windowScale = Math.min(this.canvasWidth / width, this.canvasHeight / height);
              hilog.info(DOMAIN, LOG_TAG, 'window_scale: %{public}d, vncSize: %{public}dx%{public}d, canvasSize: %{public}dx%{public}d',
                this.windowScale, width, height, this.canvasWidth, this.canvasHeight);

              // Center offset in screen pixels
              const scaledWidth = width * this.windowScale;
              const scaledHeight = height * this.windowScale;
              this.leftShift = (this.canvasWidth - scaledWidth) / 2;
              this.upShift = (this.canvasHeight - scaledHeight) / 2;

              hilog.info(DOMAIN, LOG_TAG, 'Canvas transform: scale=%{public}d, scaledSize: %{public}dx%{public}d, leftShift=%{public}d, upShift=%{public}d',
                this.windowScale, scaledWidth, scaledHeight, this.leftShift, this.upShift);

              // Reset transform and apply scale on context
              this.context.resetTransform();
              this.context.scale(this.windowScale, this.windowScale);
              this.scaleInitialized = true;
            } else {
              hilog.warn(DOMAIN, LOG_TAG, 'Canvas not ready yet, skipping scale calculation. canvasSize: %{public}dx%{public}d',
                this.canvasWidth, this.canvasHeight);
            }
            this.transformNeedsReset = false;
          }

          // Check if we need a full redraw (e.g., after screen rotation)
          if (this.needsFullRedraw) {
            this.redrawFullCanvas();
            return;
          }

          // Get PixelMap for updated region
          const pixelMap = this.getUpdatePixelMap(x, y, w, h);
          if (pixelMap) {
            // Draw at VNC coordinate + center offset (in VNC coordinate space)
            // leftShift/upShift are screen pixels, convert to VNC pixels by dividing by scale
            const vncLeftShift = this.leftShift / this.windowScale;
            const vncUpShift = this.upShift / this.windowScale;
            hilog.debug(DOMAIN, LOG_TAG, 'Draw: VNC pos(%{public}d,%{public}d), size(%{public}d,%{public}d), offset(%{public}d,%{public}d)',
              x, y, w, h, vncLeftShift, vncUpShift);
            this.context.drawImage(pixelMap, px2vp(x + vncLeftShift), px2vp(y + vncUpShift));
          }
        }
      );

      // Check for connection error
      if (result < 0) {
        hilog.error(DOMAIN, LOG_TAG, 'VNC connection error');
        this.isConnected = false;
        this.stopUpdateLoop();
      }
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'VNC update error: %{public}s', JSON.stringify(e));
      this.errorMessage = 'Update error: ' + JSON.stringify(e);
      this.isConnected = false;
      this.stopUpdateLoop();
    }
  }

  private startUpdateLoop() {
    this.checkVncUpdateFlag = true;

    // 60 FPS update loop
    this.updateInterval = setInterval(() => {
      if (this.checkVncUpdateFlag) {
        this.checkVncUpdateLock.lockAsync(() => {
          this.checkVncUpdateFlag = false;
          this.checkVncUpdate();
          this.checkVncUpdateFlag = true;
        })
      }
    }, 1000 / 60);
  }

  private stopUpdateLoop() {
    if (this.updateInterval !== undefined) {
      clearInterval(this.updateInterval);
      this.updateInterval = undefined;
    }
    this.checkVncUpdateFlag = false;
  }

  build() {
    Column() {
      if (deviceInfo.deviceType === '2in1') {
        ComposeTitleBar({
          title: $r('app.string.vnc_console_title')
        })
      }
      Canvas(this.context)
        .onReady(() => {
          hilog.info(DOMAIN, LOG_TAG, 'Canvas ready: %{public}dx%{public}d',
            this.canvasWidth, this.canvasHeight);
        })
        .onAreaChange((oldArea: Area, newArea: Area) => {
          this.canvasWidth = vp2px(Number(newArea.width));
          this.canvasHeight = vp2px(Number(newArea.height));
          hilog.info(DOMAIN, LOG_TAG, 'Canvas area changed: %{public}dx%{public}d',
            this.canvasWidth, this.canvasHeight);
          // Trigger scale recalculation and full redraw
          if (this.vncWidth > 0 && this.vncHeight > 0) {
            this.transformNeedsReset = true;
            this.needsFullRedraw = true;
          }
        })
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        .focusable(true)
        .defaultFocus(true)
        .onMouse((event: MouseEvent) => {
          event.stopPropagation();
          let x = vp2px(event.displayX) / this.windowScale;
          let y = vp2px(event.displayY) / this.windowScale;

          if (event.displayX !== 0 || event.displayY !== 0 || event.action === MouseAction.Move) {
            this.mouseX = x - this.leftShift;
            this.mouseY = y - this.upShift;
          }

          // Handle mouse buttons (except left which is handled by touch)
          if (event.button !== MouseButton.Left) {
            if (event.action === MouseAction.Press) {
              this.mouseStat |= button2rfb.get(event.button) ?? 0;
            } else if (event.action === MouseAction.Release) {
              this.mouseStat &= ~(button2rfb.get(event.button) ?? 0);
            }
            this.sendMouseEvent();
          }
        })
        .onTouch((event: TouchEvent) => {
          event.stopPropagation();
          let equivalentMouseBtn = MouseButton.None;

          let x = vp2px(event.touches[0].displayX) / this.windowScale;
          let y = vp2px(event.touches[0].displayY) / this.windowScale;

          if (event.touches[0].displayX !== 0 || event.touches[0].displayY !== 0 ||
            event.touches[0].type === TouchType.Move) {
            this.mouseX = x - this.leftShift;
            this.mouseY = y - this.upShift;
          }

          // Map touch to mouse button
          switch (event.touches.length) {
            case 1:
              equivalentMouseBtn = MouseButton.Left;
              break;
            case 2:
              equivalentMouseBtn = MouseButton.Right;
              break;
            case 3:
              equivalentMouseBtn = MouseButton.Middle;
              break;
            default:
              equivalentMouseBtn = MouseButton.None;
              break;
          }

          // Handle touch events
          switch (event.type) {
            case TouchType.Down:
              this.mouseStat |= button2rfb.get(equivalentMouseBtn) ?? 0;
              break;
            case TouchType.Up:
              this.mouseStat &= ~(button2rfb.get(equivalentMouseBtn) ?? 0);
              break;
          }

          this.sendMouseEvent();
        })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .onKeyEvent((event: KeyEvent) => {
      hilog.info(DOMAIN, LOG_TAG, 'Key event: keyCode=%{public}d, type=%{public}d, keyText=%{public}s',
        event.keyCode, event.type, event.keyText);
      this.sendKeyEvent(event.keyCode, event.type === KeyType.Down);
    })
  }

  // Send mouse event to VNC server
  private sendMouseEvent() {
    try {
      napi.vncMouseEvent(this.mouseX, this.mouseY, this.mouseStat);
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'Mouse event error: %{public}s', JSON.stringify(e));
    }
  }

  // Send key event to VNC server
  private sendKeyEvent(keyCode: number, down: boolean) {
    try {
      napi.vncKeyEvent(keyCode, down);
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'Key event error: %{public}s', JSON.stringify(e));
    }
  }
}
