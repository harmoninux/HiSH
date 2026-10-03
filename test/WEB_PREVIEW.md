# 网页预览回归测试

测试直接转译并调用生产代码 `webPreviewUrl.ets`，验证 HTTP(S)、本机端口、IPv6 地址及非法地址的处理，并检查 Phone / Tablet 页面注册。

需要 Node.js 18+ 和 TypeScript。可使用 DevEco / HarmonyOS Command Line Tools 自带的 TypeScript，或在仓库外安装 TypeScript，然后指定其模块路径。

```powershell
$env:HISH_TYPESCRIPT = 'C:/path/to/typescript'
node --test test/web-preview.test.cjs
```

Linux/macOS：

```sh
HISH_TYPESCRIPT=/path/to/typescript node --test test/web-preview.test.cjs
```

设备验收建议：

1. 配置 Linux 端口 `3080` → 主机端口 `8000`，重启模拟器，在 Linux 中执行 `python3 -m http.server 3080 --bind 0.0.0.0`。
2. 手机通过虚拟键盘的设置菜单进入“网页预览”；平板 / PC 可使用顶部入口。
3. 输入 `127.0.0.1:8000` 并打开，确认显示目录；点击其中的页面链接，使用系统返回键验证网页历史，再返回终端。
4. 服务停止后刷新，确认显示加载失败提示；重新启动服务并刷新，确认恢复。
5. 验证地址栏拒绝 `file:`、`javascript:`、带内嵌账号密码的地址和越界端口。
6. 确认浏览期间 HiSH 保持前台，返回终端后 Linux 进程仍在运行。

主机测试和未签名包构建通过不等于以上真机步骤通过。

2026-10-03 已补齐完整 HiSH 的 Phone 真机联动，包括手机内 Alpine HTTP 服务、QEMU 端口映射、网页历史、刷新、服务断开与恢复。截图、复现命令、运行资源和 API 兼容测试边界见 [FULL_DEVICE.md](validation/2026-10-03/FULL_DEVICE.md)。

## 独立 ArkWeb 界面回归包

完整 Linux 联动测试之外，可以单独检查网页预览界面：

```powershell
./test/stage-web-fixture.ps1 -OutputDirectory C:/tmp/hish-web-fixture
node test/web-preview-server.cjs
```

脚本创建未签名工程，直接复制生产预览组件和 URL 校验代码，Phone 页面包装器仅调整导入路径。使用自己的测试包名和有效签名构建、安装后，将手机端口转发至主机测试服务：

```sh
hdc -t <device> rport tcp:8000 tcp:18085
```

打开测试包的 `Open preview`，通过“映射端口”进入页面，点击 `Next page`，检查返回历史和刷新。主机访问 `http://127.0.0.1:18085/admin/fail/on` 可模拟连接失败，访问 `/admin/fail/off` 恢复；手机刷新后检查错误提示消失。结束后移除测试转发：

```sh
hdc -t <device> fport rm tcp:8000 tcp:18085
```

该回归包使用模拟配置和主机 HTTP 服务，不启动 QEMU，因此只验证 ArkWeb 界面与路由，不能代替上面的完整 HiSH 真机验收。
