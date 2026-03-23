import { image } from '@kit.ArkGraphics2D';
import { hilog } from '@kit.PerformanceAnalysisKit';
import napi from 'libentry.so';
import { Canvas, CanvasRenderingContext2D, ImageData } from '@kit.ArkGraphics2D';
import { pointer, PointerType, HoverType } from '@kit.ArkUI';
import { keyboard, KeyCode, KeyType } from '@kit.ArkUI';

const DOMAIN = 0x0001;
const LOG_TAG = 'NativeVnc';

// RFB 按钮掩码
const RFB_BUTTON1 = 0x01; // 左键
const RFB_BUTTON2 = 0x02; // 中键
const RFB_BUTTON3 = 0x04; // 右键
const RFB_BUTTON4 = 0x08; // 滚轮上
const RFB_BUTTON5 = 0x10; // 滚轮下

// RFB 按键码定义 (X11 keysym)
const RFB_KEY_A = 0x0061;
const RFB_KEY_B = 0x0062;
const RFB_KEY_C = 0x0063;
const RFB_KEY_D = 0x0064;
const RFB_KEY_E = 0x0065;
const RFB_KEY_F = 0x0066;
const RFB_KEY_G = 0x0067;
const RFB_KEY_H = 0x0068;
const RFB_KEY_I = 0x0069;
const RFB_KEY_J = 0x006a;
const RFB_KEY_K = 0x006b;
const RFB_KEY_L = 0x006c;
const RFB_KEY_M = 0x006d;
const RFB_KEY_N = 0x006e;
const RFB_KEY_O = 0x006f;
const RFB_KEY_P = 0x0070;
const RFB_KEY_Q = 0x0071;
const RFB_KEY_R = 0x0072;
const RFB_KEY_S = 0x0073;
const RFB_KEY_T = 0x0074;
const RFB_KEY_U = 0x0075;
const RFB_KEY_V = 0x0076;
const RFB_KEY_W = 0x0077;
const RFB_KEY_X = 0x0078;
const RFB_KEY_Y = 0x0079;
const RFB_KEY_Z = 0x007a;
const RFB_KEY_0 = 0x0030;
const RFB_KEY_1 = 0x0031;
const RFB_KEY_2 = 0x0032;
const RFB_KEY_3 = 0x0033;
const RFB_KEY_4 = 0x0034;
const RFB_KEY_5 = 0x0035;
const RFB_KEY_6 = 0x0036;
const RFB_KEY_7 = 0x0037;
const RFB_KEY_8 = 0x0038;
const RFB_KEY_9 = 0x0039;
const RFB_KEY_SPACE = 0x0020;
const RFB_KEY_ENTER = 0xff0d;
const RFB_KEY_TAB = 0xff09;
const RFB_KEY_ESC = 0xff1b;
const RFB_KEY_BACKSPACE = 0xff08;
const RFB_KEY_DELETE = 0xffff;
const RFB_KEY_HOME = 0xff50;
const RFB_KEY_END = 0xff57;
const RFB_KEY_UP = 0xff52;
const RFB_KEY_DOWN = 0xff54;
const RFB_KEY_LEFT = 0xff51;
const RFB_KEY_RIGHT = 0xff53;
const RFB_KEY_PAGE_UP = 0xff55;
const RFB_KEY_PAGE_DOWN = 0xff56;
const RFB_KEY_SHIFT_L = 0xffe1;
const RFB_KEY_SHIFT_R = 0xffe2;
const RFB_KEY_CONTROL_L = 0xffe3;
const RFB_KEY_CONTROL_R = 0xffe4;
const RFB_KEY_ALT_L = 0xffe9;
const RFB_KEY_ALT_R = 0xffea;
const RFB_KEY_F1 = 0xffbe;
const RFB_KEY_F2 = 0xffbf;
const RFB_KEY_F3 = 0xffc0;
const RFB_KEY_F4 = 0xffc1;
const RFB_KEY_F5 = 0xffc2;
const RFB_KEY_F6 = 0xffc3;
const RFB_KEY_F7 = 0xffc4;
const RFB_KEY_F8 = 0xffc5;
const RFB_KEY_F9 = 0xffc6;
const RFB_KEY_F10 = 0xffc7;
const RFB_KEY_F11 = 0xffc8;
const RFB_KEY_F12 = 0xffc9;

@Component
export default struct NativeVncViewer {
  @Prop address: string = '127.0.0.1'
  @Prop port: number = 5900
  @Prop password: string = ''
  @Prop @Watch('onConnectedChanged') connected: boolean = false
  @Prop onConnectionFailed?: () => void

  @State canvasWidth: number = 0
  @State canvasHeight: number = 0
  @State isConnected: boolean = false
  @State errorMessage: string = ''

  private frameBuffer?: ArrayBuffer = undefined
  private canvasContext?: CanvasRenderingContext2D = undefined
  private imageBitmap?: image.PixelMap = undefined
  private updateInterval?: number = undefined
  private buttonMask: number = 0

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
      // 调用原生 vncInit 函数
      const result = napi.vncInit(this.address, this.port, this.password);
      if (result) {
        this.frameBuffer = result as ArrayBuffer;
        this.isConnected = true;
        this.connected = true;
        hilog.info(DOMAIN, LOG_TAG, 'VNC connected successfully');
        this.startUpdateLoop();
      } else {
        this.errorMessage = 'Connection failed';
        hilog.error(DOMAIN, LOG_TAG, 'VNC init failed');
        if (this.onConnectionFailed) {
          this.onConnectionFailed();
        }
      }
    } catch (e) {
      this.errorMessage = 'Error: ' + JSON.stringify(e);
      hilog.error(DOMAIN, LOG_TAG, 'VNC connection error: %{public}s', JSON.stringify(e));
      if (this.onConnectionFailed) {
        this.onConnectionFailed();
      }
    }
  }

  private disconnectVnc() {
    if (this.isConnected) {
      try {
        napi.vncClose();
        this.isConnected = false;
        this.stopUpdateLoop();
        hilog.info(DOMAIN, LOG_TAG, 'VNC disconnected');
      } catch (e) {
        hilog.error(DOMAIN, LOG_TAG, 'Error disconnecting VNC: %{public}s', JSON.stringify(e));
      }
    }
  }

  private startUpdateLoop() {
    this.updateInterval = setInterval(() => {
      try {
        const result = napi.vncUpdate(
          (size: number) => {
            // onResize 回调
            hilog.info(DOMAIN, LOG_TAG, 'VNC resize: %{public}d bytes', size);
            // 创建新的 frame buffer
            const newBuffer = new ArrayBuffer(size);
            this.frameBuffer = newBuffer;
            return newBuffer;
          },
          (updateInfo: ArrayBuffer) => {
            // onUpdate 回调
            // 解析更新信息
            const data = new Uint8Array(updateInfo);
            const view = new DataView(updateInfo);
            const width = view.getInt32(0, true);
            const height = view.getInt32(4, true);
            const x = view.getInt32(8, true);
            const y = view.getInt32(12, true);
            const w = view.getInt32(16, true);
            const h = view.getInt32(20, true);

            if (this.canvasWidth !== width || this.canvasHeight !== height) {
              this.canvasWidth = width;
              this.canvasHeight = height;
              hilog.info(DOMAIN, LOG_TAG, 'VNC canvas size: %{public}d x %{public}d', width, height);
            }

            // 标记需要重绘
            if (this.canvasContext) {
              this.renderFrame();
            }
          }
        );
        // 返回值表示消息处理状态
      } as number, 100);
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'VNC update error: %{public}s', JSON.stringify(e));
      this.isConnected = false;
      this.connected = false;
      if (this.onConnectionFailed) {
        this.onConnectionFailed();
      }
    }
  }

  private stopUpdateLoop() {
    if (this.updateInterval !== undefined) {
      clearInterval(this.updateInterval);
      this.updateInterval = undefined;
    }
  }

  private renderFrame() {
    if (!this.frameBuffer || !this.canvasContext) {
      return;
    }

    try {
      // 创建 ImageData
      const buffer = this.frameBuffer as ArrayBuffer;
      const data = new Uint8Array(buffer);

      // VNC 使用 RGB565 格式，转换为 RGBA
      const rgbaData = new Uint8ClampedArray(this.canvasWidth * this.canvasHeight * 4);
      for (let i = 0, j = 0; i < data.length; i += 2, j += 4) {
        // RGB565 解码
        const r5 = (data[i + 1] >> 3) & 0x1f;
        const g6 = ((data[i + 1] & 0x07) << 3) | ((data[i] >> 5) & 0x07);
        const b5 = data[i] & 0x1f;

        // 扩展到 8 位
        const r8 = (r5 << 3) | (r5 >> 2);
        const g8 = (g6 << 2) | (g6 >> 4);
        const b8 = (b5 << 3) | (b5 >> 2);

        rgbaData[j] = r8;     // R
        rgbaData[j + 1] = g8; // G
        rgbaData[j + 2] = b8; // B
        rgbaData[j + 3] = 255; // A
      }

      const imageData = new ImageData(rgbaData, this.canvasWidth, this.canvasHeight);
      this.canvasContext!.putImageData(imageData, 0, 0);
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'Render error: %{public}s', JSON.stringify(e));
    }
  }

  private sendMouseEvent(event: PointerEvent) {
    if (!this.isConnected) {
      return;
    }

    try {
      let newMask = this.buttonMask;

      // 更新按钮掩码
      if (event.type === PointerType.Down) {
        if (event.button === 0) newMask |= RFB_BUTTON1;
        else if (event.button === 1) newMask |= RFB_BUTTON2;
        else if (event.button === 2) newMask |= RFB_BUTTON3;
      } else if (event.type === PointerType.Up) {
        if (event.button === 0) newMask &= ~RFB_BUTTON1;
        else if (event.button === 1) newMask &= ~RFB_BUTTON2;
        else if (event.button === 2) newMask &= ~RFB_BUTTON3;
      } else if (event.type === PointerType.Move) {
        // 移动时保持当前按钮掩码
      }

      // 处理滚轮事件
      if (event.button === -1) {
        // 滚轮
        if (event.pinchActionIndex > 0) {
          newMask |= RFB_BUTTON4; // 向上滚动
        } else {
          newMask |= RFB_BUTTON5; // 向下滚动
        }
      }

      this.buttonMask = newMask;
      napi.vncMouseEvent(Math.round(event.x), Math.round(event.y), this.buttonMask);
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'Mouse event error: %{public}s', JSON.stringify(e));
    }
  }

  private sendKeyEvent(event: KeyEvent)) {
    if (!this.isConnected) {
      return;
    }

    try {
      const rfbKey = this.keyCodeToRfb(event.keyCode);
      if (rfbKey !== 0) {
        const down = (event.type === KeyType.Down);
        napi.vncKeyEvent(rfbKey, down);
      }
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'Key event error: %{public}s', JSON.stringify(e));
    }
  }

  private keyCodeToRfb(keyCode: KeyCode): number {
    switch (keyCode) {
      case KeyCode.KEY_A: return RFB_KEY_A;
      case KeyCode.KEY_B: return RFB_KEY_B;
      case KeyCode.KEY_C: return RFB_KEY_C;
      case KeyCode.KEY_D: return RFB_KEY_D;
      case KeyCode.KEY_E: return RFB_KEY_E;
      case KeyCode.KEY_F: return RFB_KEY_F;
      case KeyCode.KEY_G: return RFB_KEY_G;
      case KeyCode.KEY_H: return RFB_KEY_H;
      case KeyCode.KEY_I: return RFB_KEY_I;
      case KeyCode.KEY_J: return RFB_KEY_J;
      case KeyCode.KEY_K: return RFB_KEY_K;
      case KeyCode.KEY_L: return RFB_KEY_L;
      case KeyCode.KEY_M: return RFB_KEY_M;
      case KeyCode.KEY_N: return RFB_KEY_N;
      case KeyCode.KEY_O: return RFB_KEY_O;
      case KeyCode.KEY_P: return RFB_KEY_P;
      case KeyCode.KEY_Q: return RFB_KEY_Q;
      case KeyCode.KEY_R: return RFB_KEY_R;
      case KeyCode.KEY_S: return RFB_KEY_S;
      case KeyCode.KEY_T: return RFB_KEY_T;
      case KeyCode.KEY_U: return RFB_KEY_U;
      case KeyCode.KEY_V: return RFB_KEY_V;
      case KeyCode.KEY_W: return RFB_KEY_W;
      case KeyCode.KEY_X: return RFB_KEY_X;
      case KeyCode.KEY_Y: return RFB_KEY_Y;
      case KeyCode.KEY_Z: return RFB_KEY_Z;
      case KeyCode.KEY_0: return RFB_KEY_0;
      case KeyCode.KEY_1: return RFB_KEY_1;
      case KeyCode.KEY_2: return RFB_KEY_2;
      case KeyCode.KEY_3: return RFB_KEY_3;
      case KeyCode.KEY_4: return RFB_KEY_4;
      case KeyCode.KEY_5: return RFB_KEY_5;
      case KeyCode.KEY_6: return RFB_KEY_6;
      case KeyCode.KEY_7: return RFB_KEY_7;
      case KeyCode.KEY_8: return RFB_KEY_8;
      case KeyCode.KEY_9: return RFB_KEY_9;
      case KeyCode.KEY_SPACE: return RFB_KEY_SPACE;
      case KeyCode.KEY_ENTER: return RFB_KEY_ENTER;
      case KeyCode.KEY_TAB: return RFB_KEY_TAB;
      case KeyCode.KEY_ESCAPE: return RFB_KEY_ESC;
      case KeyCode.KEY_BACKSPACE: return RFB_KEY_BACKSPACE;
      case KeyCode.KEY_DELETE: return RFB_KEY_DELETE;
      case KeyCode.KEY_HOME: return RFB_KEY_HOME;
      case KeyCode.KEY_END: return RFB_KEY_END;
      case KeyCode.KEY_DPAD_UP: return RFB_KEY_UP;
      case KeyCode.KEY_DPAD_DOWN: return RFB_KEY_DOWN;
      case KeyCode.KEY_DPAD_LEFT: return RFB_KEY_LEFT;
      case KeyCode.KEY_DPAD_RIGHT: return RFB_KEY_RIGHT;
      case KeyCode.KEY_PAGE_UP: return RFB_KEY_PAGE_UP;
      case KeyCode.KEY_PAGE_DOWN: return RFB_KEY_PAGE_DOWN;
      case KeyCode.KEY_LEFT_SHIFT: return RFB_KEY_SHIFT_L;
      case KeyCode.KEY_RIGHT_SHIFT: return RFB_KEY_SHIFT_R;
      case KeyCode.KEY_LEFT_CTRL: return RFB_KEY_CONTROL_L;
      case KeyCode.KEY_RIGHT_CTRL: return RFB_KEY_CONTROL_R;
      case KeyCode.KEY_LEFT_ALT: return RFB_KEY_ALT_L;
      case KeyCode.KEY_RIGHT_ALT: return RFB_KEY_ALT_R;
      case KeyCode.KEY_F1: return RFB_KEY_F1;
      case KeyCode.KEY_F2: return RFB_KEY_F2;
      case KeyCode.KEY_F3: return RFB_KEY_F3;
      case KeyCode.KEY_F4: return RFB_KEY_F4;
      case KeyCode.KEY_F5: return RFB_KEY_F5;
      case KeyCode.KEY_F6: return RFB_KEY_F6;
      case KeyCode.KEY_F7: return RFB_KEY_F7;
      case KeyCode.KEY_F8: return RFB_KEY_F8;
      case KeyCode.KEY_F9: return RFB_KEY_F9;
      case KeyCode.KEY_F10: return RFB_KEY_F10;
      case KeyCode.KEY_F11: return RFB_KEY_F11;
      case KeyCode.KEY_F12: return RFB_KEY_F12;
      default: return 0;
    }
  }

  build() {
    Column() {
      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(16)
          .fontColor(Color.Red)
          .padding(16)
      } else if (!this.isConnected) {
        Text('Connecting...')
          .fontSize(16)
          .padding(16)
      } else {
        // VNC 画布
        Canvas(this.canvasContext)
          .width(this.canvasWidth)
          .height(this.canvasHeight)
          .backgroundColor(Color.Black)
          .onReady(() => {
            this.canvasContext = this.canvasContext;
            hilog.info(DOMAIN, LOG_TAG, 'Canvas ready');
          })
          .onAreaChange((area: Area) => {
            if (area.width > 0 && area.height > 0) {
              this.canvasWidth = area.width;
              this.canvasHeight = area.height;
            }
          })
          .onTouch((x, y, event) => {
            // 转换触摸事件为鼠标事件
            const pointerEvent = new PointerEvent(
              PointerType.Move,
              -1,
              { x: x, y: y }
            );
            this.sendMouseEvent(pointerEvent);
          })
      }
    }
    .width('100%')
    .height('100%')
  }
}
