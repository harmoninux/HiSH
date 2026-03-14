#!/bin/bash
set -e
# build the project on linux
# deveco command line tools is downloaded from:
# https://developer.huawei.com/consumer/cn/download/
# and extracted to any dir

# use `make aarch64` to build for arm64-v8a
make x86_64 
