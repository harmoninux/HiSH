# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(hish)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(entry SHARED napi_init.cpp)
add_library(qemu_childprocess SHARED qemu_childprocess.cpp)

target_link_libraries(entry PUBLIC libace_napi.z.so libdeviceinfo_ndk.z.so libhilog_ndk.z.so libability_runtime.so libchild_process.so)
target_link_libraries(qemu_childprocess PUBLIC libdeviceinfo_ndk.z.so libhilog_ndk.z.so libability_runtime.so libchild_process.so)