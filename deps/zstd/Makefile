include ../utils/Makefrag

SOURCE_URL = https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz
SOURCE_FILE = zstd-1.5.7.tar.gz
SOURCE_DIR = zstd-1.5.7
# avoid clashing existing build folder
BUILD_DIR = build-zstd
PATCH_SOURCE = cd temp/$(SOURCE_DIR) && cat ../../0001-qsort.diff | patch -Np1
CMAKE_LISTS_PATH = ../build/cmake
CMAKE_ARGS = -DCMAKE_INSTALL_PREFIX=$(PREFIX) -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=$(OHOS_ARCH) -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_SHARED=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo

$(eval $(call define_cmake_package))
