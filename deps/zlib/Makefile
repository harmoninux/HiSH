include ../utils/Makefrag

export uname := Linux

export CFLAGS := $(CFLAGS) -fPIC

SOURCE_URL = https://zlib.net/zlib-1.3.1.tar.gz
SOURCE_FILE = zlib-1.3.1.tar.gz
SOURCE_DIR = zlib-1.3.1
CONFIG_ARGS = --prefix=$(PREFIX) --enable-shared

$(eval $(call define_autotools_package))
