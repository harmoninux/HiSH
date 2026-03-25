import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { display } from '@kit.ArkUI';
import { ArkTSUtils } from '@kit.ArkTS';
import napi from 'libentry.so';

const DOMAIN = 0x0001;
const LOG_TAG = 'NativeVnc';

@Component
export default struct NativeVncViewer {
  @Prop address: string = '127.0.0.1'
  @Prop port: number = 5900
  @Prop password: string = ''
  @Prop connected: boolean = false

  @State isConnected: boolean = false
  @State errorMessage: string = ''
  @State statusMessage: string = ''

  private canvasSize: Size = display.getDefaultDisplaySync()
  private settings: RenderingContextSettings = new RenderingContextSettings(false)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)
  private updateInterval?: number = undefined
  private checkVncUpdateFlag: boolean = false
  private checkVncUpdateLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock()

  // VNC frame buffer and rendering state
  private pixelArray: Uint8Array = new Uint8Array([])
  private vncWidth: number = 0
  private vncHeight: number = 0
  private leftShift: number = -1
  private upShift: number = -1
  private windowScale: number = 1
  private mouseX: number = -1
  private mouseY: number = -1
  private mouseStat: number = 0

  aboutToAppear() {
    hilog.info(DOMAIN, LOG_TAG, 'NativeVncViewer initializing: %{public}s:%{public}d', this.address, this.port);
    this.connectVnc();
  }

  aboutToDisappear() {
    this.disconnectVnc();
  }

  onConnectedChanged() {
    if (!this.connected) {
      this.disconnectVnc();
    }
  }

  private connectVnc() {
    try {
      this.statusMessage = 'Connecting to VNC server...';
      const result = napi.vncInit(this.address, this.port, this.password);

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
      const srcStart = ((y) * this.vncWidth + x + i * this.vncWidth) * bitsPerPixel;
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

          hilog.debug(DOMAIN, LOG_TAG, 'VNC update: %{public}dx%{public}d at (%{public}d,%{public}d), %{public}dx%{public}d',
                    width, height, x, y, w, h);

          // Update VNC dimensions on resize
          if (width !== this.vncWidth || height !== this.vncHeight ||
              this.leftShift === -1 || this.upShift === -1) {
            this.vncWidth = width;
            this.vncHeight = height;

            // Calculate scale to fit canvas
            this.windowScale = Math.min(this.canvasSize.width / width, this.canvasSize.height / height);
            hilog.info(DOMAIN, LOG_TAG, 'window_scale: %{public}f, vncSize: %{public}dx%{public}d',
                     this.windowScale, width, height);

            // Center of VNC display
            this.leftShift = (this.canvasSize.width - width * this.windowScale) / 2;
            this.upShift = (this.canvasSize.height - height * this.windowScale) / 2;

            hilog.info(DOMAIN, LOG_TAG, 'Canvas transform: scale=%{public}f, leftShift=%{public}d, upShift=%{public}d',
                     this.windowScale, this.leftShift, this.upShift);
          }

          // Get PixelMap for updated region
          const pixelMap = this.getUpdatePixelMap(x, y, w, h);
          if (pixelMap) {
            // Draw updated region with px2vp conversion
            this.context.drawImage(pixelMap, px2vp(x + this.leftShift), px2vp(y + this.upShift));
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
    Stack() {
      Canvas(this.context)
        .onReady(() => {
          hilog.info(DOMAIN, LOG_TAG, 'Canvas ready: %{public}dx%{public}d',
                   this.canvasSize.width, this.canvasSize.height);
        })
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)

      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(16)
          .fontColor(Color.Red)
          .padding(20)
          .backgroundColor(Color.Transparent)
      }
    }
    .width('100%')
    .height('100%')
  }
}
