include ../utils/Makefrag

SOURCE_URL = https://github.com/jemalloc/jemalloc/releases/download/5.3.0/jemalloc-5.3.0.tar.bz2
SOURCE_FILE = jemalloc-5.3.0.tar.bz2
SOURCE_DIR = jemalloc-5.3.0
PATCH_SOURCE = printf '\043undef JEMALLOC_TLS\n\043define JEMALLOC_TSD_TYPE_PTHREAD 1\n' | cat - temp/$(SOURCE_DIR)/include/jemalloc/internal/tsd.h > temp/tsd.h.tmp && mv temp/tsd.h.tmp temp/$(SOURCE_DIR)/include/jemalloc/internal/tsd.h
CONFIG_ARGS = --prefix=$(PREFIX) --disable-cxx --host=$(OHOS_ARCH)-linux --build=x86_64-unknown-linux-gnu --with-lg-page=12 --enable-static --disable-shared --disable-tls --disable-initial-exec-tls je_cv_tls=no je_cv_thread_local=no je_cv_c11_thread_local=no

# Handle libatomic location for different architectures
ifeq ($(OHOS_ARCH), aarch64)
LIBATOMIC_PATH = /usr/lib/gcc-cross/aarch64-linux-gnu/11/libatomic.a
else
LIBATOMIC_PATH = /usr/lib/gcc/x86_64-linux-gnu/11/libatomic.a
endif

# Copy jemalloc (and libatomic) to OHOS sysroot for meson to find it
AFTER_INSTALL = cp build$(PREFIX)/lib/libjemalloc.a $(OHOS_SDK_HOME)/native/sysroot/usr/lib/$(OHOS_ARCH)-linux-ohos/ && \
	cp $(LIBATOMIC_PATH) $(OHOS_SDK_HOME)/native/sysroot/usr/lib/$(OHOS_ARCH)-linux-ohos/

$(eval $(call define_autotools_package))
