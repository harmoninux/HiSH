#!/bin/bash
set -e
# build the project on linux
# deveco command line tools is downloaded from:
# https://developer.huawei.com/consumer/cn/download/
# and extracted to any dir
#export TOOL_HOME=""

if [[ ! -n ${TOOL_HOME} ]]; then
  echo """\$TOOL_HOME IS NOT DEFINED, PLS SPECIFIY A CORRECT DIR!
  You can download HarmonyOS Commandline Tools form
  https://developer.huawei.com/consumer/cn/download/
       """
  exit 1
fi

export DEVECO_SDK_HOME=$TOOL_HOME/sdk
export OHOS_SDK_HOME=$TOOL_HOME/sdk/default/openharmony
export PATH=$TOOL_HOME/bin:$PATH
export PATH=$TOOL_HOME/tool/node/bin:$PATH
# set default to x86_64 for emulator
# to build for arm64, set OHOS_ARCH=aarch64, OHOS_ABI=arm64-v8a
export OHOS_ARCH=x86_64
export OHOS_ABI=x86_64

make
