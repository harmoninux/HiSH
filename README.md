# HiSH

Run Linux Shell on HarmonyOS devices! Based on [harmony-qemu](https://github.com/hackeris/harmony-qemu), both 2in1(PC), Tablet and Phone are supported.

# How to use

Download hap from [Releases page](https://github.com/harmoninux/HiSH/releases) and signed by yourself, then install to your device or emulator.

# How to build



## Build HAP

- Clone this repo to local
- Copy `build-profile.template.json5` to `build-profile.json5`
- Download files from [Releases page](https://github.com/harmoninux/HiSH/releases) and move to corresponding location as following
  - [entry/libs/arm64-v8a/libqemu-system-aarch64.so](https://github.com/harmoninux/HiSH/releases/download/v0.0.4/arm64-v8a.libqemu-system-aarch64.so)
  - [entry/libs/x86_64/libqemu-system-aarch64.so](https://github.com/harmoninux/HiSH/releases/download/v0.0.4/x86_64.libqemu-system-aarch64.so)
  - [entry/src/main/resources/rawfile/vm/kernel_aarch64](https://github.com/harmoninux/HiSH/releases/download/v0.0.4/kernel_aarch64)
  - [entry/src/main/resources/rawfile/vm/alpine_aarch64_rootfs.qcow2](https://github.com/harmoninux/HiSH/releases/download/v0.0.4/alpine_aarch64_rootfs.qcow2)
- Build project in DevEco Studio
- Sign and run in your device or emulator

## Build libs (Optional)

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
curl https://raw.githubusercontent.com/harmoninux/linux-config/refs/heads/master/arm64_tinyconfig > .config
```
- Build Linux kernel
```shell
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
```
- The kernel image is at `arch/arm64/boot/Image`, copy it to `entry/src/main/resources/rawfile/vm/kernel_aarch64`

# Screenshots

Screenshots of HiSH running on various HarmonyOS devices.

### 2in1(PC)

![On 2in1(PC)](docs/images/Screenshot_2025-09-11T005915.png)

### Tablet

![On 2in1(PC)](docs/images/Screenshot_2025-09-13T122058.png)

### Phone

<img src="docs/images/Screenshot_2025-09-13T122218.png" width="400" alt="On Phone"/>

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=harmoninux/hish&type=Date)](https://www.star-history.com/#harmoninux/hish&Date)