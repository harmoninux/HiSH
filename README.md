# HiSH

[中文](README_CN.md)

Run Linux Shell on HarmonyOS devices! Based on [harmony-qemu](https://github.com/hackeris/harmony-qemu), both 2in1(PC), Tablet and Phone are supported.

You can install from [Invite Test of AppGallery](https://appgallery.huawei.com/link/invite-test-wap?taskId=7dd1e118ab11367c6f26b55bb989bbc5&invitationCode=2ByVRjHk2fg)

This is screenshot of HiSH on multiple devices(PC/Tablet/Phone):

![On multiple devices](docs/images/devices.png)

## Core Features

- Complete arm64 Linux kernel
- Networking with port forwarding
- Alpine Linux rootfs
- Virtual Keys (Tab/Ctrl/Esc/Up/Down/Left/Right)
- Shared Folder (Experimental)
- JIT (Only available for developer)

# How to use

Download hap from [Releases page](https://github.com/harmoninux/HiSH/releases) and signed by yourself, then install to your device or emulator.

# How to build

- HAP bundle
- libqemu-system (optional)
- Linux kernel (optional)
- rootfs (optional)

## Build HAP

- Clone this repo to local
- Copy `build-profile.template.json5` to `build-profile.json5`
- Download files and move to corresponding location as following
  - [entry/libs/arm64-v8a/libqemu-system-aarch64.so](https://github.com/harmoninux/HiSH/releases/download/release-20251022/arm64-v8a.libqemu-system-aarch64.so)
  - [entry/libs/x86_64/libqemu-system-aarch64.so](https://github.com/harmoninux/HiSH/releases/download/release-20251022/x86_64.libqemu-system-aarch64.so)
  - [entry/src/main/resources/rawfile/vm/kernel_aarch64](https://github.com/harmoninux/HiSH/releases/download/release-20251022/kernel_aarch64)
  - [entry/src/main/resources/rawfile/vm/rootfs_aarch64.qcow2](https://github.com/harmoninux/HiSH/releases/download/v0.0.13/rootfs_aarch64.qcow2)
- Build project in DevEco Studio
- Sign and run in your device or emulator

## Build libqemu-system (Optional)

Build your own `libqemu-system-aarch64.so` for `entry/libs` on Ubuntu (or WSL2 on Windows), for customizing `libqemu`

- Install dependencies
```shell
sudo apt install -y build-essential cmake curl wget unzip python3 libncurses-dev \
		git flex bison bash make autoconf libcurl4-openssl-dev tcl \
		gettext zip pigz meson
```
- Download "Command Line Tools" for Linux from https://developer.huawei.com/consumer/cn/download/
- Extract downloaded zip and set TOOL_HOME env variable to `command-line-tools` directory
- Change current directory to `deps` and run `build.sh`, for x86_64 emulator default
  - For real devices, you can change target to arm64 in build.sh by modifying OHOS_ARCH and OHOS_ABI
```shell
cd deps
./build.sh
```
- See `*.so` files in `deps/output`
```shell
ls -lh output
```

## Build Linux Kernel (Optional)

Build your own Linux kernel for HiSH, for customizing Linux kernel

- Install dependencies
```shell
sudo apt install build-essential gcc bc bison flex libssl-dev libncurses5-dev libelf-dev gcc-aarch64-linux-gnu
```
- Clone linux kernel source to local
```shell
git clone --depth=1 -b v6.16 https://github.com/torvalds/linux
```
- Download linux kernel build config
```shell
cd linux
curl https://raw.githubusercontent.com/harmoninux/linux-config/refs/heads/master/arm64_tinydocker > .config
```
- Build Linux kernel
```shell
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
```
- The kernel image is at `arch/arm64/boot/Image`, copy it to `entry/src/main/resources/rawfile/vm/kernel_aarch64`

## Build rootfs for Linux (Optional)

Build your own rootfs for HiSH

- Download and extract Alpine rootfs from [downloads | Alpine Linux](https://alpinelinux.org/downloads)
```shell
mkdir alpine
tar xvf alpine-minirootfs-3.22.1-aarch64.tar.gz -C alpine
```
- Use `qemu-img` to create a `rootfs.img` file
```shell
qemu-img create -f raw rootfs.img 8G
```
- Make fs for `rootfs.img` file
```shell
mkfs.ext4 rootfs.img
```
- Mount `rootfs.img` as directory
```shell
sudo mkdir /mnt/rootfs
sudo mount rootfs.img /mnt/rootfs
```
- Copy files of rootfs to `/mnt/rootfs`
```shell
sudo cp -r alpine/* /mnt/rootfs
```
- Unmount `/mnt/rootfs`
```shell
sudo umount /mnt/rootfs
```
- Convert raw img to qcow2 format
```shell
qemu-img convert -p -f raw -O qcow2 rootfs.img rootfs.qcow2
```
- Put `rootfs.qcow2` to `entry/src/main/resources/rawfile/vm/rootfs_aarch64.qcow2`

# Screenshots

Screenshots of HiSH running on various HarmonyOS devices.

### 2in1(PC)

![On 2in1(PC)](docs/images/Screenshot_2025-10-18T211856.png)

### Tablet

![On Tablet](docs/images/Screenshot_2025-10-18T212000.png)

### Phone

<img src="docs/images/Screenshot_2025-10-18T212024.png" width="400" alt="On Phone"/>

# Star History

[![Star History Chart](https://api.star-history.com/svg?repos=harmoninux/hish&type=Date)](https://www.star-history.com/#harmoninux/hish&Date)