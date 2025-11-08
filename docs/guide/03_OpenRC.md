# OpenRC

OpenRC是Gentoo Linux和Alpine
Linux等发行版默认采用的轻量级初始化系统，专为类Unix系统设计。

它基于依赖关系管理服务，支持并行启动，兼容传统的SysVinit脚本，同时提供更高效的服务控制。OpenRC的核心特点包括模块化设计、低资源占用以及对自定义运行级别的灵活支持。

## 启用OpenRC

在HiSH中，OpenRC可能不会自动启动，如果在 Linux Shell 中看到如下内容，则需要手动开启 OpenRC 后台进程：
```
OpenRC is disabled by default, you can start it with: rc-start
```

运行`rc-start`可以启动 OpenRC：

<img src="images/03_001.png" width="400"/>

也可以手动输入以下命令启动 OpenRC：

```
openrc sysinit
openrc boot
openrc default
```

## 查看服务状态

使用`rc-service <服务名> status`命令可查看特定服务的运行状态。例如，检查sshd服务状态：

```
rc-service sshd status  
```

输出会显示服务是否活跃（`started`）或停止（`stopped`），以及可能的错误信息。

## 查看运行中的服务

通过rc-status命令列出当前所有运行中的服务及其状态：

```
rc-status --servicelist  
```

输出中标记为`started`的服务表示正在运行，`crashed`表示异常终止的服务。

## 查看所有可用服务

使用`rc-update -v show`可列出系统中所有已配置的服务，包括已启用（标记为`default`运行级别）和未启用的服务。例如：

```
rc-update -v
```

## 启动与停止服务

* 启动服务：rc-service <服务名> start

```
rc-service docker start
```

* 停止服务：rc-service <服务名> stop

```
rc-service nginx stop
```

* 支持`restart`（重启）和`reload`（重载配置）操作。

