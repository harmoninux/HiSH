import { hilog } from '@kit.PerformanceAnalysisKit';
import { ComposeTitleBar } from '@kit.ArkUI'
import napi from 'libentry.so';
import { button2rfb } from '../utils/KeyMap';
import deviceInfo from '@ohos.deviceInfo';
import appOption from '../model/appOption';

const DOMAIN = 0x0001;
const LOG_TAG = 'NativeVnc';

interface VncPollResult {
  status: number;
  fbWidth: number;
  fbHeight: number;
}

// Fn 功能键键盘布局
const KEYBOARD_LAYOUT_FN = [
  ['Esc', 'F1', 'F2', 'F3', 'F4', 'F5', 'F6'],
  ['Tab', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12'],
  ['Shift', 'End', 'PgUp', 'PgDn', '↑', 'Ins', 'Del'],
  ['Ctrl', 'Win', 'Alt', '←', '↓', '→', 'Enter']
];

// 键位代码
const KEY_CODE_MAP: Record<string, number> = {
  'Esc': 2070,
  'Tab': 2049,
  'F1': 2090,
  'F2': 2091,
  'F3': 2092,
  'F4': 2093,
  'F5': 2094,
  'F6': 2095,
  'F7': 2096,
  'F8': 2097,
  'F9': 2098,
  'F10': 2099,
  'F11': 2100,
  'F12': 2102,
  'Home': 2036,
  'End': 2035,
  'PgUp': 2033,
  'PgDn': 2034,
  'Ins': 2083,
  'Del': 2046,
  '←': 2014,
  '↑': 2012,
  '↓': 2013,
  '→': 2015,
  '⌫': 2055,
  'Enter': 2054,
  'Space': 2050
};

@Entry
@Component
struct VncPage {
  @StorageProp(appOption.vncPort) vncPort: number = 5900
  @State isConnected: boolean = false
  @State errorMessage: string = ''
  @State statusMessage: string = ''
  // Fn 键盘显示状态
  @State showFnKeyboard: boolean = false
  // 修饰键粘滞状态
  @State shiftOn: boolean = false
  @State ctrlOn: boolean = false
  @State altOn: boolean = false
  @State winOn: boolean = false
  // 系统键盘输入文本
  @State systemInputText: string = ''
  // 缩放相关状态
  @State scaleFactor: number = 1.0
  @State isScaling: boolean = false
  @State initialDistance: number = 0
  private xComponentController: XComponentController = new XComponentController();
  private systemInputController: TextInputController = new TextInputController();
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
  private vncConnected: boolean = false
  private updateLoopStarted: boolean = false
  // 缩放限制
  private readonly MIN_SCALE: number = 0.5
  private readonly MAX_SCALE: number = 3.0
  private readonly SCALE_SENSITIVITY: number = 0.01

  aboutToAppear() {
    hilog.info(DOMAIN, LOG_TAG, 'initialize VncPage');
    this.connectVnc();
  }

  aboutToDisappear() {
    this.disconnectVnc();
  }

  private connectVnc() {
    try {
      this.statusMessage = 'Connecting to VNC server...';
      const result = napi.vncInit('127.0.0.1', this.vncPort, '');

      if (result) {
        this.vncConnected = true;
        this.isConnected = true;
        this.statusMessage = 'Connected! Waiting for surface...';
      } else {
        this.errorMessage = 'Connection failed';
        this.statusMessage = 'Connection failed';
      }
    } catch (e) {
      this.errorMessage = 'Error: ' + JSON.stringify(e);
      this.statusMessage = 'Error: ' + JSON.stringify(e);
      hilog.error(DOMAIN, LOG_TAG, 'connect error: %{public}s', JSON.stringify(e));
    }
  }

  private handleVncResize(fbWidth: number, fbHeight: number) {
    if (fbWidth <= 0 || fbHeight <= 0) {
      return;
    }
    if (fbWidth === this.vncWidth && fbHeight === this.vncHeight) {
      return;
    }
    this.vncWidth = fbWidth;
    this.vncHeight = fbHeight;
    this.updateScaling();
  }

  private startUpdateLoop() {
    if (!this.vncConnected || this.updateLoopStarted) {
      return;
    }

    try {
      napi.vncStartUpdateLoop((result: VncPollResult) => {
        if (result.status < 0) {
          this.isConnected = false;
          this.updateLoopStarted = false;
          this.errorMessage = 'Connection lost — reconnecting...';
          this.statusMessage = 'Reconnecting...';
        } else if (result.status === 1) {
          this.handleVncResize(result.fbWidth, result.fbHeight);
        }
      });
      this.statusMessage = 'Connected';
      this.updateLoopStarted = true;
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'Failed to start update loop: %{public}s', JSON.stringify(e));
    }
  }

  private disconnectVnc() {
    if (!this.vncConnected && !this.isConnected) {
      return;
    }

    try {
      napi.vncClose();
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'Error disconnecting: %{public}s', JSON.stringify(e));
    }

    this.isConnected = false;
    this.vncConnected = false;
    this.updateLoopStarted = false;
    this.statusMessage = 'Disconnected';
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
    return Math.round(((clientX - this.leftShift) / this.windowScale) / this.scaleFactor);
  }

  private vncY(clientY: number): number {
    return Math.round(((clientY - this.upShift) / this.windowScale) / this.scaleFactor);
  }

  private calculateDistance(touch1: TouchPoint, touch2: TouchPoint): number {
    const x1 = typeof touch1.x === 'number' ? touch1.x : Number(touch1.x);
    const y1 = typeof touch1.y === 'number' ? touch1.y : Number(touch1.y);
    const x2 = typeof touch2.x === 'number' ? touch2.x : Number(touch2.x);
    const y2 = typeof touch2.y === 'number' ? touch2.y : Number(touch2.y);

    const dx = x1 - x2;
    const dy = y1 - y2;
    return Math.sqrt(dx * dx + dy * dy);
  }

  private handleTouch(event: TouchEvent) {
    event.stopPropagation();

    if (event.touches.length === 2) {
      const touch1 = event.touches[0];
      const touch2 = event.touches[1];
      const currentDistance = this.calculateDistance(touch1, touch2);

      switch (event.type) {
        case TouchType.Down:
          this.initialDistance = currentDistance;
          this.isScaling = true;
          break;

        case TouchType.Move:
          if (this.isScaling && this.initialDistance > 0) {
            const scaleChange = (currentDistance - this.initialDistance) * this.SCALE_SENSITIVITY;
            let newScale = this.scaleFactor + scaleChange;
            newScale = Math.max(this.MIN_SCALE, Math.min(this.MAX_SCALE, newScale));
            this.scaleFactor = newScale;
            this.initialDistance = currentDistance;
          }
          break;

        case TouchType.Up:
          this.isScaling = false;
          this.initialDistance = 0;
          break;
      }
    } else if (event.touches.length === 1) {
      const x = this.vncX(event.touches[0].x);
      const y = this.vncY(event.touches[0].y);

      if (event.touches[0].x !== 0 || event.touches[0].y !== 0 ||
        event.touches[0].type === TouchType.Move) {
        this.mouseX = x;
        this.mouseY = y;
      }

      let btn: MouseButton = MouseButton.None;
      const touchCount = event.touches.length;

      if (touchCount === 1) {
        btn = MouseButton.Left;
      } else if (touchCount === 2) {
        btn = MouseButton.Right;
      } else if (touchCount >= 3) {
        btn = MouseButton.Middle;
      }

      switch (event.type) {
        case TouchType.Down:
          this.mouseStat |= button2rfb.get(btn) ?? 0;
          break;
        case TouchType.Up:
          this.mouseStat &= ~(button2rfb.get(btn) ?? 0);
          break;
      }

      this.sendMouseEvent();
    }
  }

  // 处理 Fn 键盘按键
  private handleKeyPress(key: string) {
    try {
      // 修饰键：切换粘滞状态
      if (key === 'Shift') {
        this.shiftOn = !this.shiftOn;
        this.sendKeyEvent(2047, this.shiftOn);
        return;
      } else if (key === 'Ctrl') {
        this.ctrlOn = !this.ctrlOn;
        this.sendKeyEvent(2072, this.ctrlOn);
        return;
      } else if (key === 'Alt') {
        this.altOn = !this.altOn;
        this.sendKeyEvent(2045, this.altOn);
        return;
      } else if (key === 'win') {
        this.winOn = !this.winOn;
        this.sendKeyEvent(2076, this.winOn);
        return;
      }

      // 普通键：先确保激活的修饰键已发送 down，再发按键，最后释放修饰键
      if (this.shiftOn) {
        this.sendKeyEvent(2047, true);
      }
      if (this.ctrlOn) {
        this.sendKeyEvent(2072, true);
      }
      if (this.altOn) {
        this.sendKeyEvent(2045, true);
      }
      if (this.winOn) {
        this.sendKeyEvent(2076, true);
      }

      if (KEY_CODE_MAP[key] !== undefined) {
        const code = KEY_CODE_MAP[key];
        this.sendKeyEvent(code, true);
        this.sendKeyEvent(code, false);
      }

      // 释放修饰键
      this.releaseModifiers();
    } catch (error) {
      hilog.error(DOMAIN, LOG_TAG, '按键错误: %{public}s', JSON.stringify(error));
    }
  }

  // 释放所有粘滞修饰键
  private releaseModifiers() {
    if (this.shiftOn) {
      this.sendKeyEvent(2047, false);
      this.shiftOn = false;
    }
    if (this.ctrlOn) {
      this.sendKeyEvent(2072, false);
      this.ctrlOn = false;
    }
    if (this.altOn) {
      this.sendKeyEvent(2045, false);
      this.altOn = false;
    }
    if (this.winOn) {
      this.sendKeyEvent(2076, false);
      this.winOn = false;
    }
  }

  // 判断修饰键是否处于激活（粘滞）状态
  private isModifierActive(key: string): boolean {
    if (key === 'Shift') return this.shiftOn;
    if (key === 'Ctrl') return this.ctrlOn;
    if (key === 'Alt') return this.altOn;
    if (key === 'win') return this.winOn;
    return false;
  }

  // 获取按键背景色：修饰键激活时高亮
  private getModifierKeyBg(key: string): string {
    if (this.isModifierActive(key)) {
      return '#0A84FF';
    }
    if (key === 'Shift' || key === 'Ctrl' || key === 'Alt' || key === 'win') {
      return '#5A5A5C';
    }
    return '#4A4A4C';
  }

  build() {
    Column() {
      if (deviceInfo.deviceType === '2in1') {
        ComposeTitleBar({
          title: $r('app.string.vnc_console_title')
        })
          .focusable(false)
      }

      // VNC 画面区域（弹性占满剩余空间）
      Stack() {
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

              if (this.vncConnected && !this.updateLoopStarted) {
                this.startUpdateLoop();
              }
            } catch (e) {
              hilog.error(DOMAIN, LOG_TAG, 'Failed to create surface: %{public}s', JSON.stringify(e));
            }
          })
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)
          .focusable(true)
          .onTouch((event: TouchEvent) => {
            this.handleTouch(event);
          })
          .onAreaChange((oldArea: Area, newArea: Area) => {
            const newWidth = Number(newArea.width);
            const newHeight = Number(newArea.height);
            if (newWidth > 0 && newHeight > 0 &&
              (newWidth !== this.surfaceWidth || newHeight !== this.surfaceHeight)) {
              this.surfaceWidth = newWidth;
              this.surfaceHeight = newHeight;
              this.updateScaling();
              try {
                const surfaceId = this.xComponentController.getXComponentSurfaceId();
                const sid = BigInt(surfaceId);
                napi.vncResizeSurface(sid, this.surfaceWidth, this.surfaceHeight);
              } catch (e) {
                hilog.error(DOMAIN, LOG_TAG, 'Failed to resize surface: %{public}s', JSON.stringify(e));
              }
            }
          })

        // 浮动按钮（Fn / ABC）
        Column() {
          Row() {
            Button('Fn')
              .onClick(() => {
                if (!this.showFnKeyboard) {
                  // 关闭系统键盘
                  this.systemInputController.stopEditing();
                }
                this.showFnKeyboard = !this.showFnKeyboard;
              })
              .fontSize(13)
              .height(34)
              .width(72)
              .backgroundColor(this.showFnKeyboard ? '#0A84FF' : '#3A3A3C')
              .fontColor('#E5E5E5')
              .borderRadius(6)
              .opacity(0.85)

            Button('ABC')
              .onClick(() => {
                this.showFnKeyboard = false;
                this.getUIContext().getFocusController().requestFocus('vncSystemInput');
              })
              .fontSize(13)
              .height(34)
              .width(72)
              .backgroundColor('#3A3A3C')
              .fontColor('#E5E5E5')
              .borderRadius(6)
              .opacity(0.85)
              .margin({ left: 8 })
          }
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .padding({ bottom: 12 })
        .hitTestBehavior(HitTestMode.Transparent)

        // 隐藏的 TextInput，唤起系统默认键盘
        TextInput({ text: this.systemInputText, placeholder: '', controller: this.systemInputController })
          .id('vncSystemInput')
          .type(InputType.Normal)
          .width(1)
          .height(1)
          .opacity(0.01)
          .position({ x: 0, y: 0 })
          .onChange((value: string) => {
            this.systemInputText = '';
          })
          .onKeyEvent((event: KeyEvent) => {
            this.sendKeyEvent(event.keyCode, event.type === KeyType.Down);
            event.stopPropagation();
          })
      }
      .width('100%')
      .layoutWeight(1)

      // Fn 功能键面板（直接作为布局节点，条件渲染）
      if (this.showFnKeyboard) {
        Column() {
          // 工具栏
          Row() {
            Button('ABC')
              .onClick(() => {
                this.showFnKeyboard = false;
                this.getUIContext().getFocusController().requestFocus('vncSystemInput');
              })
              .fontSize(13)
              .height(32)
              .width(64)
              .backgroundColor('#3A3A3C')
              .fontColor('#FFFFFF')
              .borderRadius(6)

            Blank()

            Button('收起')
              .onClick(() => {
                this.showFnKeyboard = false;
                this.releaseModifiers();
              })
              .fontSize(13)
              .height(32)
              .width(72)
              .backgroundColor('#3A3A3C')
              .fontColor('#E5E5E5')
              .borderRadius(6)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 4 })

          // 按键区域
          Column() {
            ForEach(KEYBOARD_LAYOUT_FN, (row: string[]) => {
              Row() {
                ForEach(row, (key: string) => {
                  Button(key)
                    .onClick(() => {
                      this.handleKeyPress(key)
                    })
                    .fontSize(13)
                    .height(38)
                    .margin(2)
                    .width(`${Math.floor(96 / row.length)}%`)
                    .backgroundColor(this.getModifierKeyBg(key))
                    .fontColor(this.isModifierActive(key) ? '#FFFFFF' : '#E5E5E5')
                    .borderRadius(5)
                })
              }
              .justifyContent(FlexAlign.Center)
              .width('100%')
              .margin({ top: 2, bottom: 2 })
            })
          }
          .padding({ left: 8, right: 8, bottom: 8 })
        }
        .width('100%')
        .backgroundColor('#1C1C1E')
      }
    }
    .width('100%')
    .height('100%')
    .onKeyEvent((event: KeyEvent) => {
      if (event.keyCode === 2049) {
        event.stopPropagation();
      }
      this.sendKeyEvent(event.keyCode, event.type === KeyType.Down);
      return true;
    })
  }

  private sendMouseEvent() {
    try {
      napi.vncMouseEvent(this.mouseX, this.mouseY, this.mouseStat);
    } catch (e) {
      // Silently ignore
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
