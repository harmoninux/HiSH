# 完整 HiSH 真机验收

日期：2026-10-03。设备：用户的 Mate，系统上报型号 BRA-AL00，运行时 API 23。

## 测试包与范围

独立安装完整 HiSH 普通应用，包含 QEMU TCI、Linux 内核和 Alpine rootfs。测试工程合入端口校验 PR 和网页预览 PR 的生产源文件；三个端口校验文件逐个校验 SHA256，与本分支一致。没有使用电脑 HTTP 服务或 HDC 反向端口转发替代 QEMU 网络。

原项目 API 24 的 Phone 未签名包构建通过。由于这台手机运行 API 23，真机临时工程以 API 24 工具链编译，将 compatible / target 调整为 API 12，并使用独立普通应用包名和有效 Debug Profile。原项目的 API 配置未修改。此次不是原版 API 24 发布包在 API 24 设备上的验收。

测试使用此前缓存的 HiSH QEMU TCI 库、内核与 Alpine 镜像，未重新编译全部 QEMU；原生 HiSH glue 在临时工程构建。包及运行资源哈希见 `runtime-hashes.json`。

## 真实界面检查

| 输入 | 结果 | 截图 |
| --- | --- | --- |
| 一条空映射 | 显示第 1 项不完整，未退出编辑页 | `missing.jpeg` |
| 客户机 0，主机 8000 | 显示第 1 条整数范围错误，拒绝保存 | `zero.jpeg` |
| 客户机 3080，主机 65536 | 拒绝保存 | `host-overflow.jpeg` |
| 客户机 65536，主机 8000 | 拒绝保存 | `guest-overflow.jpeg` |
| 3080→8000 与 3080→8001 | 显示端口重复，拒绝保存 | `duplicate.jpeg` |
| 删除重复行，只保留 3080→8000 | 保存成功，管理页显示 1 条映射 | `saved.jpeg` |

小数、负数、非有限值和 1 / 65535 边界由生产校验函数的主机测试覆盖；没有把这些宣称为真机输入检查。

## 实际网络

1. 从界面保存 3080→8000，使用模拟器管理的“重启”重新启动完整 HiSH。新启动的预览菜单显示保存的映射。
2. 在手机内 Alpine 执行 `apk add busybox-extras`；镜像默认的 busybox 没有 httpd applet。
3. 在 Linux 创建 `/tmp/check/index.html` 和 `two.html`，执行 `httpd -p 0.0.0.0:3080 -h /tmp/check`。
4. Guest 内 `wget -qO- http://127.0.0.1:3080` 返回测试页面；截图 `guest-service.jpeg`。
5. 完整 HiSH 的网页预览打开 `http://127.0.0.1:8000/`，实际显示 `HiSH guest page one`；截图 `forwarded-page.jpeg`。

验证链路：手机内 Linux HTTP → QEMU hostfwd → 同一 HiSH 的 ArkWeb。完整测试期间 HDC 转发列表为空；HDC 仅用于安装、输入和取证。

## 清理

测试结束已移除独立 HiSH 回归应用。没有覆盖 Sofia 或原测试 App，也没有清除它们的数据。签名文件与已签名 HAP 不提交仓库。
