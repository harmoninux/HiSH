# Docker

开发者可以使用 HiSH 提供的 Linux 环境中下载并运行 Docker 容器。

## 准备

Docker 需要依赖 OpenRC 对 `dockerd` 相关服务进行管理，故使用 `docker` 前，需要先确保 OpenRC 在运行中。具体内容参考“OpenRC”部分内容。

在 Alpine Linux 中使用 apk 安装 `docker` 软件包。

```
apk add docker
```

## 启动Docker

docker 安装好后，运行 `rc-service docker start` 启动 Docker 服务，这个步骤需要等待一段时间。

使用 `docker images` 查看镜像，确定 `docker` 已完成安装并成功启动。如下图：

<img src="images/08_001.png" width="400"/>

## 运行容器

使用 `docker pull alpine:latest` 拉取 `alpine:latest` 镜像。拉取成功后，使用`docker images`查看镜像，如图所示：

<img src="images/08_002.png" width="400"/>

运行 `docker run -it alpine:latest sh` 启动容器，如图：

<img src="images/08_003.png" width="400"/>

至此已经实现了在 HiSH 中运行 docker 容器。
