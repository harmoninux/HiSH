# HiSH

[English](README.md)

在HarmonyOS设备上运行Linux Shell。基于[harmony-qemu](https://github.com/hackeris/harmony-qemu)，支持2in1(PC)、平板和手机。

可通过[内测邀请链接](https://appgallery.huawei.com/link/invite-test-wap?taskId=7dd1e118ab11367c6f26b55bb989bbc5&invitationCode=2ByVRjHk2fg)安装。

HiSH在多种设备(PC/平板/手机)上的运行的截图如下：

![多设备运行](docs/images/devices.png)

## 核心功能

- 完整的arm64 Linux内核
- 网络支持，并支持端口转发
- Alpine Linux根文件系统
- 虚拟按键（Tab/Ctrl/Esc/方向键）
- 共享文件夹（实验中）
- JIT（仅开发者可用）

# 使用方法

从[Releases](https://github.com/harmoninux/HiSH/releases)下载hap文件，自行签名后安装到设备或模拟器。

# 构建指南

- HAP包
- libqemu-system库（可选）
- Linux内核（可选）
- 根文件系统（可选）

## 构建HAP

* 克隆本仓库到本地
* 复制`build-profile.template.json5`为`build-profile.json5`
* 下载以下文件到指定位置：
    - [entry/libs/arm64-v8a/libqemu-system-aarch64.so](https://github.com/harmoninux/HiSH/releases/download/release-20251022/arm64-v8a.libqemu-system-aarch64.so)
    - [entry/libs/x86_64/libqemu-system-aarch64.so](https://github.com/harmoninux/HiSH/releases/download/release-20251022/x86_64.libqemu-system-aarch64.so)
    - [entry/src/main/resources/rawfile/vm/kernel_aarch64](https://github.com/harmoninux/HiSH/releases/download/release-20251022/kernel_aarch64)
    - [entry/src/main/resources/rawfile/vm/rootfs_aarch64.qcow2](https://github.com/harmoninux/HiSH/releases/download/v0.0.13/rootfs_aarch64.qcow2)
* 在DevEco Studio中构建项目
* 签名后在设备或模拟器上运行

## 构建libqemu-system（可选）

在Ubuntu或Windows的WSL2环境下构建自定义的`libqemu-system-aarch64.so`：

* 安装依赖：

```shell 
sudo apt install -y build-essential cmake curl wget unzip python3 libncurses-dev \
    git flex bison bash make autoconf libcurl4-openssl-dev tcl \
    gettext zip pigz meson 
```

* 从[华为开发者官网](https://developer.huawei.com/consumer/cn/download/)下载Linux版"命令行工具"
* 解压后将`TOOL_HOME`环境变量设置为解压目录
* 进入`deps`目录运行构建脚本（默认针对x86_64模拟器）：
    * 针对真机的构建，需要将`build.sh`脚本中的`OHOS_ARCH`改为`aarch64`，`OHOS_ABI`改为`arm64-v8a`

```shell 
cd deps 
./build.sh 
```

* 构建产物位于`deps/output`目录

## 构建Linux内核（可选）

* 安装依赖：

```shell 
sudo apt install build-essential gcc bc bison flex libssl-dev libncurses5-dev libelf-dev gcc-aarch64-linux-gnu 
```

* 克隆Linux内核源码：

```shell 
git clone --depth=1 -b v6.16 https://github.com/torvalds/linux 
```

* 下载内核配置：

```shell 
cd linux 
curl https://raw.githubusercontent.com/harmoninux/linux-config/refs/heads/master/arm64_tinydocker > .config 
```

* 编译内核：

```shell 
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
```

* 内核镜像位于`arch/arm64/boot/Image`，复制到项目对应目录

## 构建Linux根文件系统（可选）

以下是构建自定义根文件系统的完整流程

* 准备Alpine根文件系统

```shell 
# 创建目录并解压Alpine最小根文件系统 
mkdir alpine 
wget https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/aarch64/alpine-minirootfs-3.22.1-aarch64.tar.gz 
tar xvf alpine-minirootfs-3.22.1-aarch64.tar.gz -C alpine 
```

* 创建磁盘镜像文件

```shell 
# 创建8GB大小的原始镜像文件（可根据需要调整大小）
qemu-img create -f raw rootfs.img 8G 
 
# 格式化为ext4文件系统 
mkfs.ext4 rootfs.img 
```

* 挂载并填充文件系统

```shell 
# 创建挂载点并挂载镜像 
sudo mkdir -p /mnt/rootfs 
sudo mount -o loop rootfs.img /mnt/rootfs 
 
# 复制Alpine文件系统内容 
sudo cp -a alpine/* /mnt/rootfs/
 
# 卸载镜像 
sudo umount /mnt/rootfs 
```

* 转换为qcow2格式

```shell 
# 转换格式（qcow2支持动态分配空间）
qemu-img convert -p -f raw -O qcow2 rootfs.img rootfs.qcow2 
```

* 部署到项目

```shell 
# 将生成的文件放入项目目录 
mkdir -p entry/src/main/resources/rawfile/vm/
mv rootfs.qcow2 entry/src/main/resources/rawfile/vm/rootfs_aarch64.qcow2 
```

# 运行截图

HiSH在不同HarmonyOS设备上的运行效果。

### 2in1(PC)

![二合一设备](docs/images/Screenshot_2025-10-18T211856.png)

### 平板

![平板设备](docs/images/Screenshot_2025-10-18T212000.png)

### 手机

<img src="docs/images/Screenshot_2025-10-18T212024.png" width="400" alt="手机设备"/>

# Star history

[![星标历史图表](https://api.star-history.com/svg?repos=harmoninux/hish&type=Date)](https://www.star-history.com/#harmoninux/hish&Date)
