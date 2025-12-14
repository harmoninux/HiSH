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

target_link_libraries(entry PUBLIC libace_napi.z.so libhilog_ndk.z.so)


add_executable(qemu_runner qemu_runner.cpp)
# Rename to libqemu_runner.so so it gets installed to libs directory
set_target_properties(qemu_runner PROPERTIES SUFFIX ".so")
set_target_properties(qemu_runner PROPERTIES PREFIX "lib")
target_link_libraries(qemu_runner PUBLIC libhilog_ndk.z.so)
