# 完整 HiSH 联动验收

2026-10-03，在 Mate（系统型号 BRA-AL00，运行时 API23）安装完整 HiSH，实际启动手机内 QEMU TCI / Alpine，并完成以下检查。

## 通过项目

| 检查 | 结果与证据 |
| --- | --- |
| Linux 启动并进入 shell | `linux.jpeg`，`uname.jpeg` |
| 保存映射并重启 HiSH | 客户机 3080→主机 8000；`mapped-ports.jpeg` |
| Linux 内服务 | `apk add busybox-extras` 后执行 httpd，guest wget 返回 HTML；`guest-service.jpeg` |
| 实际映射访问 | 预览访问 127.0.0.1:8000，显示 guest 页面；`guest-one.jpeg` |
| 页内链接 | 打开 two.html；`guest-two.jpeg` |
| 系统返回 | 从第二页返回第一页；`history-back.jpeg` |
| 刷新 | 仍显示第一页；`refresh.jpeg` |
| 返回终端 | 返回真实终端，httpd PID658 仍运行；`guest-alive.jpeg` |
| 服务停止 | 在 Linux 延时停止 PID658，预览刷新显示加载失败；`stopped.jpeg` |
| 服务恢复 | 在 Linux 延时重新启动 httpd，失败页刷新恢复；`recovered.jpeg` |
| 非 HTTP 地址 | 输入 file:///etc/passwd 后拒绝打开，原网页保留；`invalid-url.jpeg` |

没有电脑 HTTP 服务或 HDC rport；服务运行在手机内 guest。HDC 只用于安装、输入和取证，结束时转发列表为空。

## 可复现步骤

在模拟器配置中添加 3080→8000，保存并重启 HiSH。在 Linux 运行：

```sh
apk add busybox-extras
mkdir -p /tmp/check
printf '<h1>HiSH guest page one</h1><a href=/two.html>Next page</a>' > /tmp/check/index.html
printf '<h1>HiSH guest page two</h1>' > /tmp/check/two.html
httpd -p 0.0.0.0:3080 -h /tmp/check
wget -qO- http://127.0.0.1:3080
ps | grep httpd
```

从虚拟键盘设置菜单进入网页预览，选择映射端口，检查链接、返回、刷新。回终端检查服务 PID，再执行 `sleep 15 && kill <PID> &`，回到预览打开页面，15 秒后刷新应失败。回终端执行 `sleep 15 && httpd -p 3080 -h /tmp/check &`，在服务启动前打开预览得到错误，启动后点击刷新恢复。

## 构建与范围

原项目配置的 API24 Phone / Tablet 未签名 HAP 均构建通过。真机临时工程使用 SDK24 / Command Line Tools 6.1.1.280，调整 compatible/target 为 API12，以在现有 API23 设备安装，独立普通应用包名与有效 Debug Profile；原仓库 API 配置未改。

临时工程包含完整 HiSH 原生 glue、此前缓存的 TCI 库、HiSH 内核与 Alpine 镜像。运行资源和 HAP 哈希见 `runtime-hashes.json`。没有重新编译全部 QEMU，也没有验证 API24 发布包在 API24 手机上的安装。

预览生产组件 SHA256 为 B25AE993A9FD31D0396AB9EA4F74DD9CB87A7A84E3AC85CBBFBBBE20E61C8213，与安装工程逐字节一致。临时工程还合入独立端口校验 PR，验证输入后使用合法映射；网页预览分支本身不依赖该 PR。

此测试验证完整 guest 联动和 Phone 前台路由；Tablet / PC 仅构建及路由检查，后台调度、下载、TLS 和公开互联网网站未作本次真机验收。

测试结束已卸载独立 HiSH 验收应用，Sofia 和原测试 App 未覆盖、未清除数据。签名与已签名 HAP 不公开。
