PKGS=zstd \
	zlib \
    pcre2 \
	libglib \
	pixman \
	libepoxy \
	virglrenderer \
	libqemu
STAMP=$(patsubst %,%/.stamp,$(PKGS))

all: copy

copy: output/.stamp

output/.stamp: $(STAMP) Makefile
	rm -f ../entry/libs/$(OHOS_ABI)/*
	cp output/*.so ../entry/libs/$(OHOS_ABI)/
	cp output/*.so.* ../entry/libs/$(OHOS_ABI)/
	mkdir -p ../entry/src/main/resources/rawfile/vm/keymaps
	cp output/en-us ../entry/src/main/resources/rawfile/vm/keymaps/
	touch output/.stamp

%/.stamp: %/Makefile
	make -C $(patsubst %/.stamp,%,$@)
	touch $@

clean:
	rm -f $(STAMP)
	rm -rf buildroot
	rm -rf output