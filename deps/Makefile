# TOOL_HOME must be set externally (HarmonyOS Commandline Tools)
ifndef TOOL_HOME
$(error TOOL_HOME is not set. Please download HarmonyOS Commandline Tools from https://developer.huawei.com/consumer/cn/download/ and set TOOL_HOME)
endif

# Set derived SDK paths
export DEVECO_SDK_HOME = $(TOOL_HOME)/sdk
export OHOS_SDK_HOME = $(TOOL_HOME)/sdk/default/openharmony

# Set default platform to x86_64 for emulator
OHOS_ARCH ?= x86_64
OHOS_ABI ?= x86_64

PKGS=zstd \
    zlib \
    pcre2 \
    libglib \
    pixman \
    libqemu
STAMP=$(patsubst %,%/.stamp,$(PKGS))

# Default target
all: copy

# Build for x86_64 platform
x86_64: clean_libqemu
	$(MAKE) copy OHOS_ARCH=x86_64 OHOS_ABI=x86_64

# Build for aarch64 platform
aarch64: clean_libqemu
	$(MAKE) copy
	$(MAKE) copy OHOS_ARCH=aarch64 OHOS_ABI=arm64-v8a

clean_libqemu:
	rm -f libqemu/.stamp
	rm -rf libqemu/temp libqemu/build

copy: output/.stamp

output/.stamp: $(STAMP) Makefile
	rm -f ../entry/libs/$(OHOS_ABI)/*
	cp output/*.so ../entry/libs/$(OHOS_ABI)/
	cp output/*.so.* ../entry/libs/$(OHOS_ABI)/
	mkdir -p ../entry/src/main/resources/rawfile/vm/keymaps
	cp output/en-us ../entry/src/main/resources/rawfile/vm/keymaps/
	touch output/.stamp

%/.stamp: %/Makefile
	make -C $(patsubst %/.stamp,%,$@) OHOS_ARCH=$(OHOS_ARCH) OHOS_ABI=$(OHOS_ABI)
	touch $@

clean:
	rm -f $(STAMP)
	rm -rf buildroot
	rm -rf output
