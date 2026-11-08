# 端口映射校验回归测试

测试直接转译并调用生产代码 `validatePortMappings.ets`，覆盖两端端口的上下界、缺失值、越界值、非整数、非有限数值及已有的重复端口规则。

需要 Node.js 18+ 和 TypeScript。可使用 DevEco / HarmonyOS Command Line Tools 自带的 TypeScript，或在仓库外安装 TypeScript，然后指定其模块路径。

```powershell
$env:HISH_TYPESCRIPT = 'C:/path/to/typescript'
node --test test/port-mappings.test.cjs
```

Linux/macOS：

```sh
HISH_TYPESCRIPT=/path/to/typescript node --test test/port-mappings.test.cjs
```

这些主机测试验证配置逻辑。完整 HiSH 的独立真机验收、输入检查、QEMU 网络与打包边界另见 [DEVICE.md](validation/2026-10-03/DEVICE.md)。
