# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HiSH is a HarmonyOS application that runs a Linux Shell using QEMU. It's based on qemu-ohos and supports 2in1 (PC), tablet, and phone devices. The app provides a complete arm64 Linux kernel with network support, Alpine Linux root filesystem, virtual keys, shared folders, and VNC support.

## Build Commands

### Build HAP (HarmonyOS Application Package)
Use DevEco Studio to build the project:
- Install DevEco Studio from https://developer.huawei.com/consumer/cn/deveco-studio/
- Clone the repo and copy `build-profile.template.json5` to `build-profile.json5`
- Download required resources (libs.zip, kernel_aarch64, rootfs_aarch64.qcow2) to `entry/src/main/resources/rawfile/vm/`
- Build in DevEco Studio and sign for installation

### Build libqemu-system (Native QEMU Library)
Builds QEMU and its dependencies. Requires Ubuntu or Windows WSL2:

```bash
# Install dependencies
sudo apt install -y build-essential cmake curl wget unzip python3 libncurses-dev \
    git flex bison bash make autoconf libcurl4-openssl-dev tcl \
    gettext zip pigz meson

# Download HarmonyOS Command Line Tools and set TOOL_HOME
export TOOL_HOME=/path/to/commandline/tools

# Build for x86_64 emulator (default)
cd deps
make

# Build for arm64-v8a device
make aarch64

# Clean build
make clean
```

Build outputs are placed in `deps/output/` and copied to `entry/libs/<abi>/` automatically.

### Linting
The project uses `.clang-format` for C++ code formatting. Apply with:
```bash
clang-format -i entry/src/main/cpp/**/*.cpp
```

## Architecture

### Application Entry Points
- `entry/src/main/ets/entryability/EntryAbility.ets` - Main ability that:
  - Loads user preferences
  - Extracts kernel and root filesystem on first run
  - Prepares shared folders
  - Starts the default emulator VM
  - Handles background running state

### UI Structure
- `entry/src/main/ets/pages/Index.ets` - Main page, renders different layouts based on device type:
  - `PcIndex` - Full desktop layout with toolbar, terminal, and management dialogs
  - `PhoneOrTablet` - Mobile layout with terminal and optional status bar
- `entry/src/main/ets/components/` - Reusable UI components:
  - `WebTerminal.ets` - xterm.js-based terminal interface with virtual keys
  - `VmStatusBar.ets` - VM resource monitoring display
  - `EmulatorListGrid.ets`, `EditEmulatorContent.ets` - Emulator management
  - `RootfsManagementContent.ets` - Root filesystem management
  - `SharedFolderContent.ets` - Shared folder file browser
  - `SettingsContent.ets` - Application settings

### Data Models (`entry/src/main/ets/model/`)
- `Emulator.ets` - Core data structures:
  - `Emulator` - VM configuration (CPU, memory, port mapping, init path, etc.)
  - `PortMapping` - Network port forwarding rules
  - `RootFilesystem` - Available root filesystem images
  - `defaultEmulator`, `defaultRoot` - Default configurations
- `appOption.ets` - Application-wide settings and preferences keys

### VM Management (`entry/src/main/ets/lib/`)
- `startVm.ets` - Builds QEMU command line arguments and starts the VM:
  - Constructs QEMU args for machine, CPU, memory, kernel, network, drives, etc.
  - Configures VNC server when enabled
  - Calls native `napi.startVM()` via libentry.so
- `QemuAgent.ets`, `QemuAgentManager.ets` - QMP (QEMU Monitor Protocol) communication for VM control
- `terminalVirtualKeys.ets` - Virtual keyboard handling for mobile devices

### Native Layer (`entry/src/main/cpp/`)
- `napi_init.cpp` - N-API bindings between ArkTS and native code:
  - `startVM()` - Starts QEMU with given arguments
  - `checkPortUsed()` - Checks if a port is in use
  - Interacts with libqemu-system-aarch64.so

### VNC Subsystem (`entry/src/main/cpp/`)
Three-thread architecture for VNC display rendering:

- **`napi_vnc.cpp`** - N-API bindings and poll thread management:
  - Poll thread: `WaitForMessage` + `HandleRFBServerMessage` loop (protected by `socketMutex_`)
  - TSFN notifications to JS for resize (status=1) and disconnect (status=-1)
  - Frame updates go directly to render thread via `markDirty()` (no TSFN)
  - **Critical**: Do NOT send duplicate `SendFramebufferUpdateRequest` or `SendIncrementalFramebufferUpdateRequest` — `rfbInitConnection` and `HandleRFBServerMessage` already send these; duplicates cause QEMU stream desync

- **`vnc_client.cpp`** / **`include/vnc_client.hpp`** - libvncclient wrapper:
  - RGB565 pixel format (16bpp, redMax=0x1f, greenMax=0x3f, blueMax=0x1f, shifts 11/5/0)
  - Encodings: zrle ultra hextile zlib copyrect raw (when LIBZ available)
  - `readTimeout=0` (infinite): non-zero causes spurious timeouts during ZRLE/zlib decode
  - `useRemoteCursor=FALSE`: QEMU cursor pseudo-encodings may cause stream desync
  - All socket I/O serialized via `socketMutex_` (libvncclient is NOT thread-safe)
  - `rfbClientLog`/`rfbClientErr` redirected to HiLog

- **`vnc_renderer.cpp`** / **`include/vnc_renderer.hpp`** - OpenGL ES renderer:
  - Render thread owns EGL context (JS thread releases after `init()`)
  - Condition variable wakeup on `markDirty()` or `surfaceResized_`
  - GLES 3.0 with GLES 2.0 fallback (VAO available on GLES 3.0)
  - Letterbox viewport via `calcViewport()` for aspect ratio preservation
  - `updateTexture()`: full `glTexImage2D` on resize, partial `glTexSubImage2D` for dirty regions (GLES 3.0), full fallback (GLES 2.0)

- **`utils.cpp`** / **`include/utils.hpp`** - HarmonyOS keycode to RFB keysym mapping

### Resources
- `entry/src/main/resources/rawfile/vm/` - Kernel and root filesystem images
- `entry/src/main/resources/rawfile/novnc/` - NoVNC web VNC client
- `entry/src/main/resources/rawfile/term/` - xterm.js terminal emulator
- `entry/src/main/resources/rawfile/guide/` - User guide documentation

### Dependencies (`deps/`)
Each dependency has its own Makefile. The main `deps/Makefile` orchestrates builds:
- `zstd`, `zlib` - Compression libraries
- `pcre2`, `libglib` - QEMU dependencies
- `pixman` - Graphics library
- `libqemu/` - QEMU source and build configuration

## Key Technical Details

- **Device Detection**: Uses `deviceInfo.deviceType` to render appropriate UI ('2in1', 'tablet', 'phone')
- **Shared Folders**: Implemented via virtio-9p with 9p filesystem protocol
- **Network**: User-mode networking with configurable port forwarding
- **VNC**: Optional VNC server with WebSocket support for GUI access
- **Storage**: Uses `@ohos.data.preferences` for persistent settings
- **Native Integration**: libentry.so provides QEMU runtime interface via N-API

## Native Build Requirements
- HarmonyOS Command Line Tools (set `TOOL_HOME` environment variable)
- `OHOS_ARCH`: x86_64 (emulator) or aarch64 (device)
- `OHOS_ABI`: x86_64 or arm64-v8a
