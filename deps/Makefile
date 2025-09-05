PKGS=zstd \
	zlib \
    pcre2 \
	libglib \
	libqemu
STAMP=$(patsubst %,%/.stamp,$(PKGS))

all: copy

copy: harmonix-public.hnp
	rm -f ../entry/libs/$(OHOS_ABI)/*.hnp
	cp $^ ../entry/libs/$(OHOS_ABI)/harmonix-private.hnp
	cp $^ ../entry/libs/$(OHOS_ABI)/harmonix-public.hnp

harmonix-public.hnp: $(STAMP) Makefile
	# reduce size
	rm -rf sysroot
	mkdir -p sysroot/bin
	mkdir -p sysroot/lib
	mkdir -p sysroot/usr/share/qemu

	cp -r buildroot/lib/libz.so* sysroot/lib/
	cp -r buildroot/lib/libzstd.so* sysroot/lib/
	cp -r buildroot/lib/libssl.so* sysroot/lib/
	cp -r buildroot/lib/libidn2.so* sysroot/lib/
	cp -r buildroot/lib/libcrypto.so* sysroot/lib/

	cp -r buildroot/bin/wget sysroot/bin/hmx_wget
	cp -r buildroot/bin/harmonix sysroot/bin/
	cp -r buildroot/bin/qemu-* sysroot/bin/
	cp -vr buildroot/usr/share/qemu sysroot/usr/share

	# create hnp manually
	cp hnp.json sysroot
	rm -f harmonix-public.hnp
	zip -r harmonix-public.hnp sysroot

%/.stamp: %/Makefile
	make -C $(patsubst %/.stamp,%,$@)
	touch $@

rebuild-%:
	make -C $(patsubst rebuild-%,%,$@)
	touch $(patsubst rebuild-%,%/.stamp,$@)

clean:
	rm -f $(STAMP)
	rm -rf buildroot
	rm -rf sysroot
