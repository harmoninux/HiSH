import { hilog } from '@kit.PerformanceAnalysisKit';
import { ComposeTitleBar } from '@kit.ArkUI'
import napi from 'libentry.so';
import { button2rfb } from '../utils/KeyMap';
import deviceInfo from '@ohos.deviceInfo';

const DOMAIN = 0x0001;
const LOG_TAG = 'NativeVnc';

interface VncPollResult {
  status: number;
  fbWidth: number;
  fbHeight: number;
}

@Entry
@Component
struct VncPage {
  @State port: number = 5900
  @State connected: boolean = false
  @State isConnected: boolean = false
  @State errorMessage: string = ''
  @State statusMessage: string = ''

  private xComponentController: XComponentController = new XComponentController();
  private mouseX: number = -1
  private mouseY: number = -1
  private mouseStat: number = 0
  private vncWidth: number = 0
  private vncHeight: number = 0
  private surfaceWidth: number = 0
  private surfaceHeight: number = 0
  private leftShift: number = 0
  private upShift: number = 0
  private windowScale: number = 1
  private surfaceReady: boolean = false
  private vncConnected: boolean = false
  private updateLoopStarted: boolean = false
  private reconnectTimer: number = -1
  private reconnectAttempts: number = 0

  aboutToAppear() {
    this.connectVnc();
  }

  aboutToDisappear() {
    this.cancelReconnect();
    this.disconnectVnc();
  }

  private connectVnc() {
    try {
      this.statusMessage = 'Connecting to VNC server...';
      const result = napi.vncInit('127.0.0.1', this.port, '');

      if (result) {
        this.vncConnected = true;
        this.isConnected = true;
        this.reconnectAttempts = 0;
        this.statusMessage = 'Connected! Waiting for surface...';
      } else {
        this.errorMessage = 'Connection failed';
        this.statusMessage = 'Connection failed';
      }
    } catch (e) {
      this.errorMessage = 'Error: ' + JSON.stringify(e);
      this.statusMessage = 'Error: ' + JSON.stringify(e);
    }
  }

  private handleVncResize(fbWidth: number, fbHeight: number) {
    if (fbWidth <= 0 || fbHeight <= 0) return;
    if (fbWidth === this.vncWidth && fbHeight === this.vncHeight) return;
    this.vncWidth = fbWidth;
    this.vncHeight = fbHeight;
    this.updateScaling();
  }

  private startUpdateLoop() {
    if (!this.vncConnected || this.updateLoopStarted) return;

    try {
      napi.vncStartUpdateLoop((result: VncPollResult) => {
        if (result.status < 0) {
          // Disconnected — stream desync or connection lost
          this.isConnected = false;
          this.updateLoopStarted = false;
          this.errorMessage = 'Connection lost — reconnecting...';
          this.statusMessage = 'Reconnecting...';
          this.scheduleReconnect();
        } else if (result.status === 1) {
          // Resize — also sent at startup with initial dimensions
          this.handleVncResize(result.fbWidth, result.fbHeight);
        }
        // status=2 (frame update) is handled natively — no JS callback needed
      });
      this.statusMessage = 'Connected';
      this.updateLoopStarted = true;
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'Failed to start update loop: %{public}s', JSON.stringify(e));
    }
  }

  private disconnectVnc() {
    this.cancelReconnect();
    if (!this.vncConnected && !this.isConnected) return;

    try {
      napi.vncClose();
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'Error disconnecting: %{public}s', JSON.stringify(e));
    }

    this.isConnected = false;
    this.vncConnected = false;
    this.surfaceReady = false;
    this.updateLoopStarted = false;
    this.reconnectAttempts = 0;
    this.statusMessage = 'Disconnected';
  }

  private cancelReconnect() {
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
  }

  private scheduleReconnect() {
    this.cancelReconnect();
    this.reconnectAttempts++;
    const attempt = this.reconnectAttempts;
    const delay = Math.min(1000 * attempt, 5000); // 1s, 2s, 3s... up to 5s
    hilog.info(DOMAIN, LOG_TAG, 'Scheduling VNC reconnect attempt %{public}d in %{public}dms', attempt, delay);
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      hilog.info(DOMAIN, LOG_TAG, 'Attempting VNC reconnect #%{public}d...', attempt);
      this.disconnectVnc();
      this.reconnectAttempts = attempt; // restore count cleared by disconnectVnc
      this.connectVnc();
      if (this.vncConnected && this.surfaceReady && !this.updateLoopStarted) {
        this.startUpdateLoop();
        this.reconnectAttempts = 0; // reset on success
      }
    }, delay);
  }

  private updateScaling() {
    if (this.surfaceWidth > 0 && this.surfaceHeight > 0 && this.vncWidth > 0 && this.vncHeight > 0) {
      this.windowScale = Math.min(this.surfaceWidth / this.vncWidth, this.surfaceHeight / this.vncHeight);
      const scaledWidth = this.vncWidth * this.windowScale;
      const scaledHeight = this.vncHeight * this.windowScale;
      this.leftShift = (this.surfaceWidth - scaledWidth) / 2;
      this.upShift = (this.surfaceHeight - scaledHeight) / 2;
    }
  }

  private vncX(clientX: number): number {
    return Math.round((vp2px(clientX) - this.leftShift) / this.windowScale);
  }

  private vncY(clientY: number): number {
    return Math.round((vp2px(clientY) - this.upShift) / this.windowScale);
  }

  build() {
    Column() {
      if (deviceInfo.deviceType === '2in1') {
        ComposeTitleBar({
          title: $r('app.string.vnc_console_title')
        })
          .focusable(false)
      }

      XComponent({
        type: XComponentType.SURFACE,
        controller: this.xComponentController
      })
        .onLoad(() => {
          const surfaceId = this.xComponentController.getXComponentSurfaceId();
          const rect = this.xComponentController.getXComponentSurfaceRect();
          this.surfaceWidth = rect.surfaceWidth;
          this.surfaceHeight = rect.surfaceHeight;

          try {
            const sid = BigInt(surfaceId);
            const created = napi.vncCreateSurface(sid);

            if (created && this.surfaceWidth > 0 && this.surfaceHeight > 0) {
              napi.vncResizeSurface(sid, this.surfaceWidth, this.surfaceHeight);
            }

            this.surfaceReady = true;

            if (this.vncConnected && !this.updateLoopStarted) {
              this.startUpdateLoop();
            }
          } catch (e) {
            hilog.error(DOMAIN, LOG_TAG, 'Failed to create surface: %{public}s', JSON.stringify(e));
          }
        })
        .onDestroy(() => {
          this.surfaceReady = false;
        })
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          const newWidth = Number(newValue.width);
          const newHeight = Number(newValue.height);
          if (newWidth > 0 && newHeight > 0 && this.surfaceReady) {
            const sid = BigInt(this.xComponentController.getXComponentSurfaceId());
            const pxWidth = vp2px(newWidth);
            const pxHeight = vp2px(newHeight);
            if (pxWidth !== this.surfaceWidth || pxHeight !== this.surfaceHeight) {
              this.surfaceWidth = pxWidth;
              this.surfaceHeight = pxHeight;
              napi.vncResizeSurface(sid, pxWidth, pxHeight);
            }
          }
        })
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(Color.Black)
        .focusable(true)
        .defaultFocus(true)
        .onMouse((event: MouseEvent) => {
          event.stopPropagation();
          const x = this.vncX(event.x);
          const y = this.vncY(event.y);

          if (event.x !== 0 || event.y !== 0 || event.action === MouseAction.Move) {
            this.mouseX = x;
            this.mouseY = y;
          }

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

          const x = this.vncX(event.touches[0].x);
          const y = this.vncY(event.touches[0].y);

          if (event.touches[0].x !== 0 || event.touches[0].y !== 0 ||
            event.touches[0].type === TouchType.Move) {
            this.mouseX = x;
            this.mouseY = y;
          }

          // Map touch count to mouse button
          let equivalentMouseBtn = MouseButton.None;
          switch (event.touches.length) {
            case 1: equivalentMouseBtn = MouseButton.Left; break;
            case 2: equivalentMouseBtn = MouseButton.Right; break;
            case 3: equivalentMouseBtn = MouseButton.Middle; break;
          }

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
    }
    .width('100%')
    .height('100%')
    .onKeyEvent((event: KeyEvent) => {
      // Prevent Tab from moving focus out of XComponent (e.g. to ComposeTitleBar)
      if (event.keyCode === 2049) { // KEYCODE_TAB
        event.stopPropagation();
      }
      this.sendKeyEvent(event.keyCode, event.type === KeyType.Down);
      return true; // consume the event
    })
  }

  private sendMouseEvent() {
    try {
      napi.vncMouseEvent(this.mouseX, this.mouseY, this.mouseStat);
    } catch (e) {
      // Silently ignore — mouse events are high-frequency
    }
  }

  private sendKeyEvent(keyCode: number, down: boolean) {
    try {
      napi.vncKeyEvent(keyCode, down);
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'Key event error: %{public}s', JSON.stringify(e));
    }
  }
}
