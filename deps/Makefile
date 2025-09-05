PKGS=zstd \
	zlib \
    pcre2 \
	libglib \
	libqemu
STAMP=$(patsubst %,%/.stamp,$(PKGS))

all: copy

copy: output/.stamp

output/.stamp: $(STAMP) Makefile
	rm -f ../entry/libs/$(OHOS_ABI)/*
	cp output/libqemu-system-aarch64.so ../entry/libs/$(OHOS_ABI)/
	touch output/.stamp

%/.stamp: %/Makefile
	make -C $(patsubst %/.stamp,%,$@)
	touch $@

clean:
	rm -f $(STAMP)
	rm -rf buildroot
	rm -rf output