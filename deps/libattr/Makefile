include ../utils/Makefrag

SOURCE_URL = https://download.savannah.gnu.org/releases/attr/attr-2.5.1.tar.gz
SOURCE_FILE = attr-2.5.1.tar.gz
SOURCE_DIR = attr-2.5.1
CONFIG_ARGS = --prefix=$(PREFIX) --disable-nls --host=$(OHOS_ARCH)-linux --build=x86_64-unknown-linux-gnu --enable-static --disable-shared

# Handle libatomic location for different architectures
ifeq ($(OHOS_ARCH), aarch64)
LIBATOMIC_PATH = /usr/lib/gcc-cross/aarch64-linux-gnu/11/libatomic.a
else
LIBATOMIC_PATH = /usr/lib/gcc/x86_64-linux-gnu/11/libatomic.a
endif

# Install shim xattr.h header, fix pkg-config paths, and copy libs to OHOS sysroot
# Note: sed modifies .pc in build dir before Makefrag copies to buildroot
AFTER_INSTALL = sed -i "s|^prefix=.*|prefix=$(shell pwd)/../buildroot|" build$(PREFIX)/lib/pkgconfig/libattr.pc && \
	mkdir -p ../buildroot/include/attr && cp $(shell pwd)/xattr.h ../buildroot/include/attr/ && \
	cp build$(PREFIX)/lib/libattr.a $(OHOS_SDK_HOME)/native/sysroot/usr/lib/$(OHOS_ARCH)-linux-ohos/ && \
	cp $(LIBATOMIC_PATH) $(OHOS_SDK_HOME)/native/sysroot/usr/lib/$(OHOS_ARCH)-linux-ohos/

$(eval $(call define_autotools_package))
