include ../utils/Makefrag

all: download/libepoxy
	rm -rf temp build
	mkdir -p temp build
	cd temp && cp -vr ../download/libepoxy libepoxy
	cd temp/libepoxy && rm cross.txt || true
	cd temp/libepoxy && echo "[binaries]" >> cross.txt
	cd temp/libepoxy && echo "c = '${OHOS_SDK_HOME}/native/llvm/bin/$(OHOS_ARCH)-unknown-linux-ohos-clang'" >> cross.txt
	cd temp/libepoxy && echo "cpp = '${OHOS_SDK_HOME}/native/llvm/bin/$(OHOS_ARCH)-unknown-linux-ohos-clang++'" >> cross.txt
	cd temp/libepoxy && echo "ar = '${OHOS_SDK_HOME}/native/llvm/bin/llvm-ar'" >> cross.txt
	cd temp/libepoxy && echo "ld = '${OHOS_SDK_HOME}/native/llvm/bin/ld.lld'" >> cross.txt
	cd temp/libepoxy && echo "strip = '${OHOS_SDK_HOME}/native/llvm/bin/llvm-strip'" >> cross.txt
	cd temp/libepoxy && echo "[host_machine]" >> cross.txt
	cd temp/libepoxy && echo "system = 'linux'" >> cross.txt
	cd temp/libepoxy && echo "cpu_family = '$(OHOS_ARCH)'" >> cross.txt
	cd temp/libepoxy && echo "cpu = '$(OHOS_ARCH)'" >> cross.txt
	cd temp/libepoxy && echo "endian = 'little'" >> cross.txt
	cd temp/libepoxy && echo "[properties]" >> cross.txt
	cd temp/libepoxy && echo "needs_exe_wrapper = true" >> cross.txt
	cd temp/libepoxy && PKG_CONFIG=$(shell which pkg-config) PKG_CONFIG_LIBDIR=$(shell pwd)/../buildroot/lib/pkgconfig meson --cross-file cross.txt --prefix=$(PREFIX) -Dglx=no -Dx11=false -Ddefault_library=static build
	cd temp/libepoxy/build && meson compile
	mkdir -p ../buildroot
	cd temp/libepoxy/build && DESTDIR=$(shell pwd)/build meson install
	cp -rfv ./build/$(PREFIX)/. ../buildroot | tee file.lst

download/libepoxy:
	mkdir -p download
	cd download && rm -rf libepoxy && git clone -b 1.5.10 --recursive --depth=1 https://github.com/anholt/libepoxy
