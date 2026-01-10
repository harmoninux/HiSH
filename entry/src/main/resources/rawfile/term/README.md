# Terminal 渲染引擎说明 (xterm.js)

本文档说明本项目中终端渲染引擎从 `hterm` 迁移至 `xterm.js` 后的特性、输入处理机制及异常处理方法。

## 1. 中文等宽字符支持 (Chinese Character Support)

### 现状问题 (Legacy Issues)

旧版 `hterm` 基于 DOM 元素渲染文本。在不同字体或字号下，中文字符的宽度往往不是英文字符的严格 2 倍（例如 1.8 倍或 2.1 倍），导致在显示表格（如 `top` 命令）、边框或 Vim 界面时，排版会发生错位。

### xterm.js 解决方案 (Current Solution)

`xterm.js` 采用 Canvas/WebGL 绘制技术，强制执行**严格的网格布局 (Grid Layout)**：

* **单元格机制**：终端被划分为规则的网格。
* **中英文对齐**：所有半角字符（英文、数字）占用 **1 个** 单元格；所有全角字符（中文、日文、Emoji）占用 **2 个** 单元格。
* **效果**：无论字体如何渲染，字符都严格落入网格中，彻底解决了字符不对齐的问题。

## 2. 键盘输入与交互 (Keyboard Input Handling)

### 数据流 (Data Flow)

键盘输入不再使用 `iso-2022` 编码，而是全面转向现代化的 **UTF-8** 编码：

1. **捕获**: `xterm.js` 监听浏览器键盘事件。
2. **编码**: 将按键转换为标准的 VT/ANSI 转义序列（例如方向键 `\x1b[A`）或 UTF-8 字符流。
3. **传输**: 通过 `term.js` 中的 `term.onData(data)` 回调，直接调用 `native.sendInput(data)` 将 UTF-8 数据发送给底层虚拟机。

### Insert 键与粘贴 (Insert Key & Paste)

* **Insert 键**: 当用户按下 `Insert` 键时，xterm.js 会发送标准 VT 转义序列 `\x1b[2~` 给虚拟机。这与标准 Linux 终端行为一致。
* **Shift + Insert (粘贴)**:
  * 应用层 (ArkTS) 拦截到 `Shift+Insert` 组合键时，会调用 `term.js` 暴露的 `exports.paste(text)` 接口。
  * `term.js` 适配器将文本转换为 UTF-8 字节流并发送给 VM，确保粘贴内容准确无误。

## 3. 故障处理与降级方法 (Troubleshooting & Fallback)

### WebGL 硬件加速与降级

为了获得最佳性能（60FPS+），系统默认加载 `xterm-addon-webgl`。

* **处理方法**: 代码包含自动检测逻辑。如果在某些低端设备或 Webview 环境中 WebGL 初始化失败（或上下文丢失），`term.js` 会自动捕获异常，并**静默降级**到 Canvas 2D 渲染器。
* **影响**: 降级模式下功能完全一致，仅在高负载滚屏时 CPU 占用略高。

### 字体大小与光标同步

ArkTS 主动下发配置（如 `setFontSize`, `setCursorStyle`）时，`term.js` 适配器会实时更新 xterm 实例的 Options，并触发 `fitAddon.fit()` 以确保行列数与显示区域重新匹配。
