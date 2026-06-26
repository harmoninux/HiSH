import util from '@ohos.util';
import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import napi from 'libentry.so';
import { webview } from '@kit.ArkWeb';
import { pasteboard, deviceInfo } from '@kit.BasicServicesKit'
import appOption, { CursorShape, savePreference } from '../model/appOption';
import { common } from '@kit.AbilityKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import stringToArrayBuffer from '../lib/stringToArrayBuffer';
import { QemuAgentManager } from '../lib/QemuAgentManager';
import { createAutoSnapshot } from '../lib/autoSnapshot';
import {
  applyVirtualKeyModifiers,
  FunctionKeySequences,
  getVirtualKeyMetrics,
  NormalKeySequences
} from '../lib/terminalVirtualKeys';

const DOMAIN = 0x0000;

const VKeyMetrics = getVirtualKeyMetrics(deviceInfo.deviceType)
const VKeyMargin = VKeyMetrics.margin;
const VKeyPadding = VKeyMetrics.padding;
const VKeyHeight = VKeyMetrics.height;
const VKeyWidth = VKeyMetrics.width;
const VKeyFontSize = VKeyMetrics.fontSize;
const VKeyRadius = VKeyMetrics.radius;

@Component
export default struct WebTerminal {
  @Require virtKeyEnabled: boolean = true
  @State ctrlPressed: boolean = false
  @State shiftPressed: boolean = false
  @State fnPressed: boolean = false
  @Watch('onFontSizeChanged') @StorageProp(appOption.terminalFontSize) fontSize: number | null = null
  @Watch('onCursorShapeChanged') @StorageProp(appOption.terminalCursorShape) cursorShape: CursorShape | null = null
  @Watch('onCursorBlinkChanged') @StorageProp(appOption.terminalCursorBlink) cursorBlink: boolean | null = null
  @Watch('onThemeChanged') @StorageProp(appOption.terminalTheme) terminalTheme: string = 'dark'
  @Watch('onFontChanged') @StorageProp(appOption.terminalFont) terminalFont: string = 'CodeNewRoman NF Mono'
  @Watch('saveShowVirtKey') @StorageProp(appOption.showVirtKey) showVirtKey: boolean = true
  @StorageProp(appOption.vncEnabled) vncEnabled: boolean = true
  webviewController: WebviewController = new webview.WebviewController()
  utf8Decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
  private lastResizeWidth: number = -1
  private lastResizeHeight: number = -1
  private resizeTimeout: number | undefined = undefined
  private vmReady: boolean = false        // set to true when first data from VM arrives
  applicationMode: boolean = false
  private destroyed: boolean = false

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
        PasteButton()
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
          .backgroundColor('#292b2e')
      }
    }
    .width('160vp')
  }

  /**
   * @param appCode code used in application mode
   */
  @Builder
  buildVKey(name: string, value: string, appCode?: string) {
    Button(name, { buttonStyle: ButtonStyleMode.TEXTUAL })
      .height(VKeyHeight)
      .width(VKeyWidth)
      .borderRadius(VKeyRadius)
      .fontSize(VKeyFontSize)
      .fontColor($r('sys.color.white'))
      .margin(VKeyMargin)
      .padding({ left: VKeyPadding, right: VKeyPadding })
      .onClick(() => {
        if (this.applicationMode && appCode) {
          this.sendInput(appCode);
        } else {
          this.sendInput(value)
        }
      })
  }

  @Builder
  toggleCtrlKey(name: string, action: () => void) {
    Toggle({ type: ToggleType.Button, isOn: this.ctrlPressed }) {
      Text(name).fontSize(VKeyFontSize).fontWeight(FontWeight.Medium)
    }
    .height(VKeyHeight)
    .width(VKeyWidth)
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
    .width(VKeyWidth)
    .borderRadius(VKeyRadius)
    .margin(VKeyMargin)
    .backgroundColor($r('sys.color.black'))
    .selectedColor($r('sys.color.interactive_active'))
    .onClick(() => action())
  }

  @Builder
  toggleFnKey(name: string, action: () => void) {
    Toggle({ type: ToggleType.Button, isOn: this.fnPressed }) {
      Text(name).fontSize(VKeyFontSize).fontWeight(FontWeight.Medium)
    }
    .height(VKeyHeight)
    .width(VKeyWidth)
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
    .bindMenu(this.settingsButtonOptions())
  }

  private settingsButtonOptions(): MenuElement[] {
    const vncOptions: MenuElement[] = this.vncEnabled ? [{
      value: $r('app.string.vnc_console_title'),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.display')).fontSize($r('sys.float.Title_S')),
      action: () => {
        const vncEnabled = AppStorage.get<boolean>(appOption.vncEnabled)!!
        if (vncEnabled) {
          this.getUIContext().getRouter().pushUrl({
            url: 'pages/VncPage'
          });
        } else {
          this.getUIContext().getPromptAction().showToast({ message: $r('app.string.vnc_service_not_started') });
        }
      }
    }] : []
    const regularOptions: MenuElement[] = [{
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
    }]
    return [...vncOptions, ...regularOptions];
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

  aboutToDisappear() {
    this.destroyed = true
    if (this.flushTimeoutID !== undefined) {
      clearTimeout(this.flushTimeoutID)
      this.flushTimeoutID = undefined
    }
    if (this.resizeTimeout !== undefined) {
      clearTimeout(this.resizeTimeout)
      this.resizeTimeout = undefined
    }
  }

  build() {
    Column() {
      Web({
        src: $rawfile('term/term.html'),
        controller: this.webviewController
      })
        .javaScriptProxy({
          object: this,
          name: 'native',
          methodList: ['sendInput', 'resize', 'load',
            'getFontSize', 'getCursorShape', 'getCursorBlink',
            'setApplicationMode'],
          controller: this.webviewController,
          asyncMethodList: [],
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
      if (this.virtKeyEnabled) {
        if (this.showVirtKey) {
          this.buildVirtualKeys()
        } else {
          this.buildShowVirtualKeysButton()
        }
      }
    }
    .height('100%')
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
    .width('100%')
  }

  @Builder
  buildVirtualKeys() {
    Column() {
      if (this.fnPressed) {
        Row() {
          this.toggleFnKey('FN', () => this.toggleFn());
          this.buildVKey('F1', FunctionKeySequences.F1);
          this.buildVKey('F2', FunctionKeySequences.F2);
          this.buildVKey('F3', FunctionKeySequences.F3);

          Row().layoutWeight(1);

          this.buildVKey('F4', FunctionKeySequences.F4);
          this.buildVKey('F5', FunctionKeySequences.F5);
          this.buildVKey('F6', FunctionKeySequences.F6);
          this.settingsButton();
        }
        .margin({ left: 5, right: 5 })

        Row() {
          this.buildVKey('F7', FunctionKeySequences.F7);
          this.buildVKey('F8', FunctionKeySequences.F8);
          this.buildVKey('F9', FunctionKeySequences.F9);

          Row().layoutWeight(1);

          this.buildVKey('F10', FunctionKeySequences.F10);
          this.buildVKey('F11', FunctionKeySequences.F11);
          this.buildVKey('F12', FunctionKeySequences.F12);
          this.hideVKeyButton();
        }
        .margin({ left: 5, right: 5 })
      } else {
        Row() {
          this.buildVKey('ESC', NormalKeySequences.ESC);
          this.toggleFnKey('FN', () => this.toggleFn());
          this.buildVKey('/', '/', '/');

          Row().layoutWeight(1);

          this.buildVKey('PGUP', NormalKeySequences.PGUP);
          this.buildVKey('HOME', NormalKeySequences.HOME);
          this.buildVKey('↑', NormalKeySequences.UP, NormalKeySequences.UP_APP);
          this.buildVKey('END', NormalKeySequences.END);

          this.settingsButton();
        }
        .margin({ left: 5, right: 5 })

        Row() {
          this.buildVKey('TAB', NormalKeySequences.TAB);
          this.toggleCtrlKey('CTRL', () => this.toggleCtrl());
          this.buildVKey('-', '-', '-');

          Row().layoutWeight(1);

          this.buildVKey('PGDN', NormalKeySequences.PGDN);
          this.buildVKey('←', NormalKeySequences.LEFT, NormalKeySequences.LEFT_APP);
          this.buildVKey('↓', NormalKeySequences.DOWN, NormalKeySequences.DOWN_APP);
          this.buildVKey('→', NormalKeySequences.RIGHT, NormalKeySequences.RIGHT_APP);
          this.hideVKeyButton();
        }
        .margin({ left: 5, right: 5 })
      }
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

  private toggleFn(): void {
    this.fnPressed = !this.fnPressed;
  }
  //  ============== for javascript in ArkWeb ================

  sendInput(data: string): void {
    hilog.info(DOMAIN, 'WebTerminal', 'sendInput, data: %{public}s', data);

    const modifierResult = applyVirtualKeyModifiers(data, this.ctrlPressed, this.shiftPressed)
    data = modifierResult.data

    if (modifierResult.ctrlConverted) {
      hilog.info(DOMAIN, 'WebTerminal', 'sendInput with Ctrl, converted to control char');
    }
    if (modifierResult.shouldResetCtrl) {
      this.toggleCtrl()
    }
    if (modifierResult.shiftConverted) {
      hilog.info(DOMAIN, 'WebTerminal', 'sendInput with Shift, converted to: %{public}s', data);
    }

    let buffer = stringToArrayBuffer(data, 'utf-8');
    napi.sendInput(buffer)

    // Ctrl: 一次性模式，发送后自动重置 | Shift: 状态保持，需要用户手动点击取消
  }

  async load(): Promise<void> {
    this.webviewController.runJavaScript('exports.setFocused(true)')
    napi.onData((d: ArrayBuffer): void => this.onData(d))
    napi.onShutdown((): void => {
      void this.onShutdown()
    })
    const vmStatus = AppStorage.get(appOption.currentEmulatorStatus) as string | undefined
    if (vmStatus === 'ABNORMAL') {
      const message = this.getUIContext().getHostContext()?.resourceManager.getStringByNameSync('pm_status_qmp_connect_failed')
        ?? 'Failed to connect to QMP (please restart app)'
      const text = util.TextEncoder.create('utf-8').encodeInto('\r\n' + message + '\r\n')
      const base64 = new util.Base64Helper().encodeToStringSync(text)
      this.webviewController.runJavaScript(`exports.writeBase64("${base64}", ${this.applicationMode})`)
    }
  }

  // QGA 通知 VM 终端尺寸（走 QGA socket，绕过 tty echo）
  async resize(width: number, height: number): Promise<void> {
    hilog.info(DOMAIN, "WebTerminal", 'on resize: %{public}d x %{public}d', width, height)
    if (width === this.lastResizeWidth && height === this.lastResizeHeight) return
    this.lastResizeWidth = width
    this.lastResizeHeight = height

    if (!this.vmReady) return

    // 通过 QGA 执行 stty 设终端尺寸，走独立 socket 不触发 tty echo
    try {
      const agent = await QemuAgentManager.acquire('terminal-resize', 0, 2000)
      if (agent) {
        try {
          await agent.execAndGetOutput('/bin/sh',
            ['-c', `stty cols ${width} rows ${height} < /dev/ttyAMA0`], 2000)
          hilog.info(DOMAIN, 'WebTerminal', 'QGA resize ok: %{public}d x %{public}d', width, height)
        } finally {
          await QemuAgentManager.release('terminal-resize')
        }
      }
    } catch (_e) {
      // QGA 不可用时静默忽略（VM 未启动 guest-agent、boot 中等）
    }
  }

  // 性能优化：输出缓冲区
  private pendingChunks: Uint8Array[] = [];
  private flushTimeoutID: number | undefined = undefined;
  private readonly FLUSH_INTERVAL = 16; // 60FPS (16.6ms)
  private readonly CLEAR_DEBOUNCE_MS = 300; // 清屏 debounce：防止 TUI 高频刷新导致跳屏
  private lastClearScrollbackTime: number = 0;

  private onData(ab: ArrayBuffer) {
    if (this.destroyed) return
    try {
      // VM 首次输出数据，标志已就绪（resize CSI 在用户首次按键时激活）
      if (!this.vmReady) {
        this.vmReady = true
      }

      // 将收到的数据块加入队列
      this.pendingChunks.push(new Uint8Array(ab));

      // 如果没有正在等待的 Flush 任务，则调度一个
      if (this.flushTimeoutID === undefined) {
        this.flushTimeoutID = setTimeout(() => {
          this.flushData();
        }, this.FLUSH_INTERVAL);
      }
    } catch (e) {
      hilog.error(DOMAIN, 'WebTerminal', 'onData failed: %{public}s', JSON.stringify(e));
    }
  }

  private flushData() {
    this.flushTimeoutID = undefined;

    if (this.pendingChunks.length === 0) return;

    try {
      // 1. 计算总长度
      let totalLength = 0;
      for (const chunk of this.pendingChunks) {
        totalLength += chunk.length;
      }

      // 2. 合并所有 Chunk
      const merged = new Uint8Array(totalLength);
      let offset = 0;
      for (const chunk of this.pendingChunks) {
        merged.set(chunk, offset);
        offset += chunk.length;
      }

      // 清空缓冲区
      this.pendingChunks = [];

      // 3. 检测清屏信号
      // 检查合并后的数据是否包含 \x1b[H\x1b[J 的字面量转义序列
      if (merged.length >= 12 &&
        merged[0] === 0x5C && merged[1] === 0x78 && merged[2] === 0x31 && merged[3] === 0x62 && // \x1b
        merged[4] === 0x5B && merged[5] === 0x48 && // [H
        merged[6] === 0x5C && merged[7] === 0x78 && merged[8] === 0x31 && merged[9] === 0x62 && // \x1b
        merged[10] === 0x5B && merged[11] === 0x4A // [J
      ) {
        const now = Date.now()
        if (now - this.lastClearScrollbackTime >= this.CLEAR_DEBOUNCE_MS) {
          this.lastClearScrollbackTime = now
          const clearCmd = '\\x1b[3J'
          const encoder = util.TextEncoder.create('utf-8')
          const clearBytes = encoder.encodeInto(clearCmd)
          const clearBase64 = new util.Base64Helper().encodeToStringSync(clearBytes)
          this.webviewController.runJavaScript(`exports.writeBase64("${clearBase64}", ${this.applicationMode})`)
        }
      }

      // 3. 发送合并后的数据
      const base64Helper = new util.Base64Helper();
      const base64 = base64Helper.encodeToStringSync(merged);
      this.webviewController.runJavaScript(`exports.writeBase64("${base64}", ${this.applicationMode})`);

    } catch (e) {
      hilog.error(DOMAIN, 'WebTerminal', 'flushData failed: %{public}s', JSON.stringify(e));
      // 出错时也要清空缓冲区，避免积压
      this.pendingChunks = [];
    }
  }

  private async onShutdown() {
    if (this.destroyed) return
    hilog.info(DOMAIN, 'WebTerminal', 'qemu system exited');

    await createAutoSnapshot()

    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    await context?.terminateSelf()
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

  getDeviceType(): string {
    return deviceInfo.deviceType;
  }

  onFontSizeChanged() {
    if (this.destroyed) return
    this.webviewController.runJavaScript(`exports.setFontSize(${this.fontSize})`)
  }

  onCursorShapeChanged() {
    if (this.destroyed) return
    this.webviewController.runJavaScript(`exports.setCursorShape('${this.cursorShape}')`)
  }

  onCursorBlinkChanged() {
    if (this.destroyed) return
    this.webviewController.runJavaScript(`exports.setCursorBlink(${this.cursorBlink})`)
  }

  onThemeChanged() {
    if (this.destroyed) return
    // 使用 JSON.stringify 确保自定义主题 JSON 被正确转义
    this.webviewController.runJavaScript(`exports.setTheme(${JSON.stringify(this.terminalTheme)})`)
  }

  onFontChanged() {
    if (this.destroyed) return
    this.webviewController.runJavaScript(`exports.setFont(${JSON.stringify(this.terminalFont)}); exports.fit()`)
  }

  getTheme(): string {
    return this.terminalTheme
  }

  getFont(): string {
    return this.terminalFont
  }

  setApplicationMode(mode: boolean) {
    this.applicationMode = mode
    hilog.info(DOMAIN, 'WebTerminal', 'set applicationMode to %{public}s', this.applicationMode);
  }
}
