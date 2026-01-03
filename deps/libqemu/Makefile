include ../utils/Makefrag

ifeq ($(OHOS_ARCH), aarch64)
LSE_FLAGS := -D__ARM_LSE_ATOMIC_INLINES
endif

# to disable jit, add --enable-tcg-interpreter option

all: download/qemu
	rm -rf temp build
	mkdir -p temp build
	cd download/qemu && git worktree add -f $(shell pwd)/temp/qemu HEAD
	cd temp/qemu && \
	PKG_CONFIG=$(shell which pkg-config) \
	PKG_CONFIG_PATH= \
	PKG_CONFIG_LIBDIR=$(shell pwd)/../buildroot/lib/pkgconfig:$(shell pwd)/../buildroot/share/pkgconfig \
	PKG_CONFIG_buildroot_DIR=$(shell pwd)/../buildroot \
	CFLAGS="$(LSE_FLAGS) -D_UAPI_LINUX_VIRTIO_VSOCK_H -D_UAPI_LINUX_VIRTIO_TYPES_H -D_UAPI_LINUX_VIRTIO_RING_H -D_UAPI_LINUX_VIRTIO_PMEM_H -D_UAPI_LINUX_VIRTIO_NET_H -D_UAPI_LINUX_VIRTIO_IOMMU_H -D_UAPI_LINUX_VIRTIO_FS_H -D_UAPI_LINUX_VIRTIO_CONSOLE_H -D_UAPI_LINUX_VIRTIO_CONFIG_H -D_LINUX_SYSINFO_H -UHAVE_OPENAT2_H -D__user= -D__force= ${CFLAGS} -Wno-unused-command-line-argument -I$(shell pwd)/../buildroot/include/glib-2.0 -I$(shell pwd)/../buildroot/lib/glib-2.0/include -I$(shell pwd)/../buildroot/include/pixman-1 -L$(shell pwd)/../buildroot/lib" \
	./configure --target-list=aarch64-softmmu --cross-prefix= --host-cc=cc --disable-kvm --disable-xen --disable-rust --disable-docs --disable-werror \
	 --enable-tcg --enable-lto --enable-strip --with-coroutine=sigaltstack \
	 --enable-trace-backends=nop --disable-qom-cast-debug \
	 --disable-stack-protector \
	 --disable-bsd-user --disable-guest-agent --disable-gcrypt --disable-debug-info --disable-debug-tcg --enable-attr --disable-brlapi --disable-linux-aio \
	 --disable-bzip2 --disable-cap-ng --disable-curl --disable-glusterfs --disable-gnutls --disable-nettle --disable-gtk --disable-rdma --disable-libiscsi \
	 --disable-vnc-jpeg --disable-lzo --disable-curses --disable-libnfs --disable-numa --disable-opengl --disable-rbd --disable-vnc-sasl --disable-sdl \
	 --disable-seccomp --disable-smartcard --disable-snappy --disable-spice --disable-libusb --disable-usb-redir --disable-vde --disable-vhost-net --disable-virglrenderer \
	 --disable-vte --disable-xen-pci-passthrough --enable-tools --disable-libudev --disable-passt \
	 --enable-pixman --enable-vnc --enable-slirp --enable-virtfs --enable-virglrenderer
	cd temp/qemu && make libqemu-system-aarch64.so -j $(shell nproc)
	cp temp/qemu/pc-bios/efi-virtio.rom ./build
	cp temp/qemu/build/libqemu-system-aarch64.so ./build
	cp temp/qemu/build/subprojects/slirp/libslirp.so.0.4.0 ./build/libslirp.so.0
	cp temp/qemu/pc-bios/keymaps/en-us ./build/
	mkdir -p ../output
	cp -rv ./build/* ../output

download/qemu:
	mkdir -p download
	cd download && git clone -b libqemu-ohos-10.2 --depth=1 https://github.com/hackeris/harmony-qemu qemu
