include ../utils/Makefrag

all: download/virglrenderer
	rm -rf temp build
	mkdir -p temp build
	cd temp && cp -vr ../download/virglrenderer virglrenderer
	cd temp/virglrenderer && rm cross.txt || true
	cd temp/virglrenderer && echo "[binaries]" >> cross.txt
	cd temp/virglrenderer && echo "c = '${OHOS_SDK_HOME}/native/llvm/bin/$(OHOS_ARCH)-unknown-linux-ohos-clang'" >> cross.txt
	cd temp/virglrenderer && echo "cpp = '${OHOS_SDK_HOME}/native/llvm/bin/$(OHOS_ARCH)-unknown-linux-ohos-clang++'" >> cross.txt
	cd temp/virglrenderer && echo "ar = '${OHOS_SDK_HOME}/native/llvm/bin/llvm-ar'" >> cross.txt
	cd temp/virglrenderer && echo "ld = '${OHOS_SDK_HOME}/native/llvm/bin/ld.lld'" >> cross.txt
	cd temp/virglrenderer && echo "strip = '${OHOS_SDK_HOME}/native/llvm/bin/llvm-strip'" >> cross.txt
	cd temp/virglrenderer && echo "[host_machine]" >> cross.txt
	cd temp/virglrenderer && echo "system = 'linux'" >> cross.txt
	cd temp/virglrenderer && echo "cpu_family = '$(OHOS_ARCH)'" >> cross.txt
	cd temp/virglrenderer && echo "cpu = '$(OHOS_ARCH)'" >> cross.txt
	cd temp/virglrenderer && echo "endian = 'little'" >> cross.txt
	cd temp/virglrenderer && echo "[properties]" >> cross.txt
	cd temp/virglrenderer && echo "needs_exe_wrapper = true" >> cross.txt
	cd temp/virglrenderer && PKG_CONFIG=$(shell which pkg-config) PKG_CONFIG_LIBDIR=$(shell pwd)/../buildroot/lib/pkgconfig meson --cross-file cross.txt --prefix=$(PREFIX) -Ddefault_library=static build
	cd temp/virglrenderer/build && meson compile
	mkdir -p ../buildroot
	cd temp/virglrenderer/build && DESTDIR=$(shell pwd)/build meson install
	cp -rfv ./build/$(PREFIX)/. ../buildroot | tee file.lst

download/virglrenderer:
	mkdir -p download
	cd download && rm -rf virglrenderer && git clone -b 1.2.0 --recursive --depth=1 https://gitlab.freedesktop.org/virgl/virglrenderer
