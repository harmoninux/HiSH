import util from '@ohos.util';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import napi from 'libentry.so';
import { webview } from '@kit.ArkWeb';
import { pasteboard, deviceInfo } from '@kit.BasicServicesKit'
import appOption, { CursorShape, savePreference } from '../model/appOption';
import { common } from '@kit.AbilityKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';

const DOMAIN = 0x0000;

// 根据设备类型调整虚拟按键尺寸
const isPhone = deviceInfo.deviceType === 'phone';
const isTablet = deviceInfo.deviceType === 'tablet';
// 手机：最紧凑 | 平板：中等 | PC/2in1：最大
const VKeyMargin = isPhone ? 1 : 2;
const VKeyPadding = isPhone ? 2 : (isTablet ? 4 : 8);
const VKeyHeight = isPhone ? 24 : 28;
const VKeyWidth = isPhone ? 36 : 50; // 平板和PC用同样大小
const VKeyModWidth = isPhone ? 48 : 60; // CTRL/SHIFT 更宽
const VKeyFontSize = isPhone ? 10 : 14; // 平板和PC用同样大小
const VKeyRadius = 5;

function stringToArrayBuffer(str: string, encoding: buffer.BufferEncoding = 'utf-8'): ArrayBuffer {
  const buf = buffer.from(str, encoding);
  return buf.buffer;
}

@Component
export default struct WebTerminal {
  @Require virtKeyEnabled: boolean
  @State ctrlPressed: boolean = false
  @State shiftPressed: boolean = false
  @StorageProp(appOption.currentEmulatorStatus) currentStatus: string = 'RUNNING'
  @Watch('onFontSizeChanged') @StorageProp(appOption.terminalFontSize) fontSize: number | null = null
  @Watch('onCursorShapeChanged') @StorageProp(appOption.terminalCursorShape) cursorShape: CursorShape | null = null
  @Watch('onCursorBlinkChanged') @StorageProp(appOption.terminalCursorBlink) cursorBlink: boolean | null = null
  @Watch('saveShowVirtKey') @StorageProp(appOption.showVirtKey) showVirtKey: boolean = true
  webviewController: WebviewController = new webview.WebviewController()
  utf8Decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
  resizeTimeout?: number = undefined

  @Builder
  contextMenu(webController: WebviewController) {
    Flex({
      direction: FlexDirection.Column
    }) {
      MenuItem({ content: $r('app.string.copy_text') })
        .width('100%')
        .onClick(async () => {
          const selection = await webController.runJavaScript('exports.copy()')
          if (selection !== '""') {
            let text: string = JSON.parse(selection);
            const board = pasteboard.getSystemPasteboard()
            const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
            board.setData(pasteData)
          }
        })
      MenuItem() {
        PasteButton({ buttonType: ButtonType.ROUNDED_RECTANGLE })
          .onClick(async (event: ClickEvent, result: PasteButtonOnClickResult) => {
            if (PasteButtonOnClickResult.SUCCESS === result) {
              let board = pasteboard.getSystemPasteboard();
              const data = await board.getData()
              const text = data.getPrimaryText()
              const array = util.TextEncoder.create().encodeInto(text)
              const base64 = new util.Base64Helper().encodeToStringSync(array)
              webController.runJavaScript(`exports.paste(atob('${base64}'))`)
            }
          })
          .width('100%')
          .align(Alignment.Start)
          .backgroundColor('#292b2e')
      }
    }
    .width('160vp')
  }

  @Builder
  buildVKey(name: string, value: string) {
    Button(name, { buttonStyle: ButtonStyleMode.TEXTUAL })
      .height(VKeyHeight)
      .width(VKeyWidth)
      .borderRadius(VKeyRadius)
      .fontSize(VKeyFontSize)
      .fontColor($r('sys.color.white'))
      .margin(VKeyMargin)
      .padding({ left: VKeyPadding, right: VKeyPadding })
      .onClick(() => {
        this.sendInput(value);
      })
  }

  @Builder
  toggleCtrlKey(name: string, action: () => void) {
    Toggle({ type: ToggleType.Button, isOn: this.ctrlPressed }) {
      Text(name).fontSize(VKeyFontSize).fontWeight(FontWeight.Medium)
    }
    .height(VKeyHeight)
    .width(VKeyModWidth)
    .borderRadius(VKeyRadius)
    .margin(VKeyMargin)
    .backgroundColor($r('sys.color.black'))
    .selectedColor($r('sys.color.interactive_active'))
    .onClick(() => action())
  }

  @Builder
  toggleShiftKey(name: string, action: () => void) {
    Toggle({ type: ToggleType.Button, isOn: this.shiftPressed }) {
      Text(name).fontSize(VKeyFontSize).fontWeight(FontWeight.Medium)
    }
    .height(VKeyHeight)
    .width(VKeyModWidth)
    .borderRadius(VKeyRadius)
    .margin(VKeyMargin)
    .backgroundColor($r('sys.color.black'))
    .selectedColor($r('sys.color.interactive_active'))
    .onClick(() => action())
  }

  @Builder
  settingsButton() {
    Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Image($r('app.media.gearshape')).width(16).height(16).padding(0)
    }
    .height(VKeyHeight)
    .width(VKeyHeight)
    .borderRadius(VKeyRadius)
    .margin(VKeyMargin)
    .bindMenu([{
      value: $r('app.string.vnc_console_title'),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.display')).fontSize($r('sys.float.Title_S')),
      action: () => {
        const vncPort = AppStorage.get<number>('vncWebSocketPort');
        if (vncPort) {
          this.getUIContext().getRouter().pushUrl({
            url: 'pages/VncPage',
            params: { vncPort: vncPort }
          });
        } else {
          this.getUIContext().getPromptAction().showToast({ message: $r('app.string.vnc_service_not_started') });
        }
      }
    }, {
      value: $r('app.string.menu_emulator_management'),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.more')).fontSize($r('sys.float.Title_S')),
      action: () => this.getUIContext().getRouter().pushUrl({ url: 'pages/EmulatorManagementPage' })
    }, {
      value: $r('app.string.menu_shared_folder'),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.folder')).fontSize($r('sys.float.Title_S')),
      action: () => this.getUIContext().getRouter().pushUrl({ url: 'pages/SharedFolderPage' })
    }, {
      value: $r('app.string.menu_settings'),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.gearshape')).fontSize($r('sys.float.Title_S')),
      action: () => this.getUIContext().getRouter().pushUrl({ url: 'pages/SettingsPage' })
    }])
  }

  @Builder
  hideVKeyButton() {
    Button('▼', { buttonStyle: ButtonStyleMode.TEXTUAL })
      .height(VKeyHeight)
      .width(VKeyHeight)
      .borderRadius(VKeyRadius)
      .margin(VKeyMargin)
      .padding({ left: VKeyPadding, right: VKeyPadding })
      .fontColor($r('sys.color.white'))
      .onClick(() => {
        this.showVirtKey = false
      })
  }

  build() {
    Column() {
      Stack() {
        Web({
          src: $rawfile('term/term.html'),
          controller: this.webviewController
        })
          .javaScriptProxy({
            object: this,
            name: 'native',
            methodList: ['sendInput', 'resize', 'load',
              'getFontSize', 'getCursorShape', 'getCursorBlink',
              'copyToClipboard', 'requestCopy', 'requestPaste', 'resetShift'],
            controller: this.webviewController,
            asyncMethodList: ['pasteFromClipboard'],
            permission: `{
            "javascriptProxyPermission": {
              "urlPermissionList": [
                {
                  "scheme": "resource",
                  "host": "rawfile",
                  "port": "",
                  "path": ""
                }
              ]
            }
          }`
          })
          .backgroundColor('#000')
          .layoutWeight(1)
          .bindContextMenu(this.contextMenu(this.webviewController), ResponseType.RightClick)
          .onKeyEvent((event: KeyEvent) => {
            // 调试：打印所有键盘事件的 keyCode
            // hilog.info(DOMAIN, 'WebTerminal', 'onKeyEvent: keyCode=%{public}d, type=%{public}d', event.keyCode, event.type);

            // 在原生层捕获 Ctrl+Insert (复制) 和 Shift+Insert (粘贴)
            // Insert 键的 keyCode 是 2083
            if (event.keyCode === 2083 && event.type === KeyType.Down) {
              // 使用 getModifierKeyState 方法检测修饰键状态 (API 13+)
              const ctrlPressed = event.getModifierKeyState ? event.getModifierKeyState(['Ctrl']) : false;
              const shiftPressed = event.getModifierKeyState ? event.getModifierKeyState(['Shift']) : false;
              const altPressed = event.getModifierKeyState ? event.getModifierKeyState(['Alt']) : false;

              if (ctrlPressed && !shiftPressed && !altPressed) {
                // Ctrl+Insert: 复制
                hilog.info(DOMAIN, 'WebTerminal', 'onKeyEvent: Ctrl+Insert copy');
                this.handleCopyRequest();
                return;
              }
            }
          })

        if (this.currentStatus === 'PAUSED') {
          Column() {
            Text($r('app.string.status_paused'))
              .fontSize(30)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#80808080')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }

        if (this.currentStatus === 'SHUTDOWN') {
          Column() {
            Text($r('app.string.status_shutdown_exit'))
              .fontSize(24)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#000000')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .layoutWeight(1)

      // 虚拟按键放在 Stack 外部，自然显示在底部
      if (this.virtKeyEnabled) {
        if (this.showVirtKey) {
          this.buildVirtualKeys()
        } else {
          this.buildShowVirtualKeysButton()
        }
      }
    }
  }

  @Builder
  buildShowVirtualKeysButton() {
    Column() {
      Button('▲', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .width(120)
        .height(16)
        .fontSize(16)
        .borderRadius(VKeyRadius)
        .fontColor('#444')
        .padding({ left: VKeyPadding, right: VKeyPadding })
        .onClick(() => {
          this.showVirtKey = true
        })
    }
  }

  @Builder
  buildVirtualKeys() {
    Column() {
      Row() {
        this.buildVKey('ESC', '\x1b');

        Row().layoutWeight(1);

        this.buildVKey('PGUP', '\x1b[5~');
        this.buildVKey('HOME', '\x1b[H');
        this.buildVKey('↑', '\x1b[A');
        this.buildVKey('END', '\x1b[F');

        this.settingsButton();
      }
      .margin({ left: 5, right: 5 })

      Row() {
        this.buildVKey('TAB', '\t');
        this.toggleCtrlKey('CTRL', () => this.toggleCtrl());
        this.toggleShiftKey('SHIFT', () => this.toggleShift());

        Row().layoutWeight(1);

        this.buildVKey('PGDN', '\x1b[6~');
        this.buildVKey('←', '\x1b[D');
        this.buildVKey('↓', '\x1b[B');
        this.buildVKey('→', '\x1b[C');
        this.hideVKeyButton();
      }
      .margin({ left: 5, right: 5 })
    }
  }

  async saveShowVirtKey() {
    await savePreference(appOption.showVirtKey, this.showVirtKey, this.getUIContext())
    if (!this.showVirtKey) {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.hide_virtual_key_toast'),
        duration: 5000
      })
    }
  }

  private toggleCtrl(): void {
    this.ctrlPressed = !this.ctrlPressed;
  }

  private toggleShift(): void {
    this.shiftPressed = !this.shiftPressed;
  }

  // 由 JavaScript 调用，用于自动重置 Shift 状态
  resetShift(): void {
    if (this.shiftPressed) {
      this.shiftPressed = false;
      // 不需要再调用 JS，因为 JS 侧已经重置了
    }
  }

  //  ============== for javascript in ArkWeb ================

  sendInput(data: string): void {
    hilog.info(DOMAIN, 'WebTerminal', 'sendInput, data: %{public}s', data);

    // 处理 Ctrl 状态：将小写字母转换为控制字符
    if (this.ctrlPressed && data.length === 1) {
      const char = data.charAt(0);
      if (char >= 'a' && char <= 'z') {
        data = String.fromCharCode(char.charCodeAt(0) - 'a'.charCodeAt(0) + 1);
        hilog.info(DOMAIN, 'WebTerminal', 'sendInput with Ctrl, converted to control char');
      }
    }

    // 处理 Shift 状态：将小写字母转换为大写
    if (this.shiftPressed && data.length === 1) {
      const char = data.charAt(0);
      if (char >= 'a' && char <= 'z') {
        data = char.toUpperCase();
        hilog.info(DOMAIN, 'WebTerminal', 'sendInput with Shift, converted to: %{public}s', data);
      }
    }

    let buffer = stringToArrayBuffer(data, 'utf-8');
    napi.sendInput(buffer)
    
    // 状态保持：不自动重置 Ctrl 和 Shift，需要用户手动点击取消
  }

  // 处理复制请求 - 使用类似右键菜单的方式
  private async handleCopyRequest(): Promise<void> {
    // hilog.info(DOMAIN, 'WebTerminal', 'handleCopyRequest start');
    try {
      const selection = await this.webviewController.runJavaScript('exports.copy()')
      // hilog.info(DOMAIN, 'WebTerminal', 'handleCopyRequest selection: %{public}s', selection);
      // 检查是否有有效的选中文本（不是空字符串、null、undefined）
      if (selection && selection !== '""' && selection !== 'null' && selection !== 'undefined') {
        let text: string = JSON.parse(selection);
        if (text && text.length > 0) {
          const board = pasteboard.getSystemPasteboard()
          const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
          board.setData(pasteData)
          hilog.info(DOMAIN, 'WebTerminal', 'handleCopyRequest completed, text: %{public}s', text);
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, 'WebTerminal', 'handleCopyRequest error: %{public}s', String(error));
    }
  }

  // 处理粘贴请求 - 使用类似右键菜单的方式
  private async handlePasteRequest(): Promise<void> {
    // hilog.info(DOMAIN, 'WebTerminal', 'handlePasteRequest start');
    try {
      const board = pasteboard.getSystemPasteboard()
      const data = await board.getData()
      const text = data.getPrimaryText()
      // hilog.info(DOMAIN, 'WebTerminal', 'handlePasteRequest text length: %{public}d', text ? text.length : 0);
      if (text) {
        const array = util.TextEncoder.create().encodeInto(text)
        const base64 = new util.Base64Helper().encodeToStringSync(array)
        this.webviewController.runJavaScript(`exports.paste(atob('${base64}'))`)
        hilog.info(DOMAIN, 'WebTerminal', 'handlePasteRequest completed');
      }
    } catch (error) {
      hilog.error(DOMAIN, 'WebTerminal', 'handlePasteRequest error: %{public}s', String(error));
    }
  }

  async load(): Promise<void> {
    this.webviewController.runJavaScript('exports.setFocused(true)')
    napi.onData((d: ArrayBuffer) => this.onData(d))
    napi.onShutdown(() => this.onShutdown())
  }

  async resize(width: number, height: number): Promise<void> {
    hilog.info(DOMAIN, "WebTerminal", 'on resize: %{public}d, %{public}d', width, height)

    if (this.resizeTimeout !== undefined) {
      clearTimeout(this.resizeTimeout!!)
    }
    this.resizeTimeout = setTimeout(() => this.sendInput('\x1b' + `[8;${height};${width}t`), 100)
  }

  private onData(ab: ArrayBuffer) {
    let s: string = this.utf8Decoder.decodeToString(new Uint8Array(ab), { stream: true });
    hilog.info(DOMAIN, 'WebTerminal', 'write, data: %{public}s', s);
    if (s.startsWith('\\x1b[H\\x1b[J')) {
      this.webviewController.runJavaScript('exports.clear()');
    }
    this.webviewController.runJavaScript('exports.write("' + s + '")');
  }

  private async onShutdown() {
    // QEMU 退出后记录日志
    hilog.info(DOMAIN, 'WebTerminal', 'qemu system exited');

    // 更新虚拟机状态 - 清除当前运行的模拟器标识
    AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN');
    AppStorage.setOrCreate(appOption.currentRunningEmulator, '');
    hilog.info(DOMAIN, 'WebTerminal', 'Updated emulator status to SHUTDOWN, cleared currentRunningEmulator');

    // 只在移动设备上自动退出应用，PC 设备不自动退出
    // PC 设备用户可通过界面手动关闭应用
    const isPc = deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'tablet';
    if (!isPc) {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await context?.terminateSelf()
    }
  }

  getFontSize(): number | null {
    return this.fontSize
  }

  getCursorShape(): string | null {
    return this.cursorShape
  }

  getCursorBlink(): boolean | null {
    return this.cursorBlink
  }

  onFontSizeChanged() {
    this.webviewController.runJavaScript(`exports.setFontSize(${this.fontSize})`)
  }

  onCursorShapeChanged() {
    this.webviewController.runJavaScript(`exports.setCursorShape('${this.cursorShape}')`)
  }

  onCursorBlinkChanged() {
    this.webviewController.runJavaScript(`exports.setCursorBlink(${this.cursorBlink})`)
  }

  // Ctrl+Insert 复制选中文本到剪贴板
  copyToClipboard(text: string): void {
    const board = pasteboard.getSystemPasteboard()
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
    board.setData(pasteData)
  }

  // Shift+Insert 从剪贴板粘贴
  async pasteFromClipboard(): Promise<void> {
    const board = pasteboard.getSystemPasteboard()
    const data = await board.getData()
    const text = data.getPrimaryText()
    if (text) {
      const array = util.TextEncoder.create().encodeInto(text)
      const base64 = new util.Base64Helper().encodeToStringSync(array)
      this.webviewController.runJavaScript(`exports.paste(atob('${base64}'))`)
    }
  }

  // Ctrl+Insert 复制请求 - 使用类似右键菜单的方式
  async requestCopy(): Promise<void> {
    hilog.info(DOMAIN, 'WebTerminal', 'requestCopy called');
    const selection = await this.webviewController.runJavaScript('exports.copy()')
    hilog.info(DOMAIN, 'WebTerminal', 'requestCopy selection: %{public}s', selection);
    if (selection !== '""') {
      let text: string = JSON.parse(selection);
      const board = pasteboard.getSystemPasteboard()
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      board.setData(pasteData)
      hilog.info(DOMAIN, 'WebTerminal', 'requestCopy completed');
    }
  }

  // Shift+Insert 粘贴请求 - 使用类似右键菜单的方式
  async requestPaste(): Promise<void> {
    hilog.info(DOMAIN, 'WebTerminal', 'requestPaste called');
    const board = pasteboard.getSystemPasteboard()
    const data = await board.getData()
    const text = data.getPrimaryText()
    hilog.info(DOMAIN, 'WebTerminal', 'requestPaste text length: %{public}d', text ? text.length : 0);
    if (text) {
      const array = util.TextEncoder.create().encodeInto(text)
      const base64 = new util.Base64Helper().encodeToStringSync(array)
      this.webviewController.runJavaScript(`exports.paste(atob('${base64}'))`)
      hilog.info(DOMAIN, 'WebTerminal', 'requestPaste completed');
    }
  }
}
