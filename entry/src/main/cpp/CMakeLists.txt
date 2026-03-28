# minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(hish)
set(PROJECT_LANGUAGE C)
if(DEFINED CMAKE_CXX_COMPILER)
  set(CMAKE_CXX_STANDARD 17)
  list(APPEND PROJECT_LANGUAGES CXX)
endif(DEFINED CMAKE_CXX_COMPILER)

project(HiSH VERSION 1.0.0 LANGUAGES ${PROJECT_LANGUAGES})
include(CheckFunctionExists)
include(CheckSymbolExists)
include(CheckIncludeFile)
include(CheckTypeSize)
include(TestBigEndian)
include(CheckCSourceCompiles)
include(CheckCSourceRuns)
include(GNUInstallDirs)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

# libvncclient paths
set(COMMON_DIR ${CMAKE_CURRENT_SOURCE_DIR}/libvncserver/src/common)
set(LIBVNCCLIENT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/libvncserver/src/libvncclient)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_CURRENT_SOURCE_DIR}/libvncserver/cmake/Modules/")
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Headers needed for check_type_size()
check_include_file("vfork.h"       LIBVNCSERVER_HAVE_VFORK_H)
check_include_file("ws2tcpip.h"    LIBVNCSERVER_HAVE_WS2TCPIP_H)
check_include_file("arpa/inet.h"   HAVE_ARPA_INET_H)
check_include_file("stdint.h"      HAVE_STDINT_H)
check_include_file("stddef.h"      HAVE_STDDEF_H)
check_include_file("sys/types.h"   HAVE_SYS_TYPES_H)
check_include_file("sys/time.h"    LIBVNCSERVER_HAVE_SYS_TIME_H)
check_include_file("sys/socket.h"  LIBVNCSERVER_HAVE_SYS_SOCKET_H)
check_include_file("netinet/in.h"  LIBVNCSERVER_HAVE_NETINET_IN_H)

if(HAVE_ARPA_INET_H)
  list(APPEND CMAKE_EXTRA_INCLUDE_FILES "arpa/inet.h")
endif()

check_function_exists(vfork           LIBVNCSERVER_HAVE_VFORK)

# Crypto - use builtin only (simplest for HarmonyOS)
set(CRYPTO_SOURCES ${COMMON_DIR}/crypto_included.c ${COMMON_DIR}/sha1.c ${COMMON_DIR}/d3des.c)

check_type_size(pid_t     LIBVNCSERVER_PID_T)
check_type_size(size_t    LIBVNCSERVER_SIZE_T)
check_type_size(socklen_t LIBVNCSERVER_SOCKLEN_T)
check_type_size(in_addr_t LIBVNCSERVER_IN_ADDR_T)

# Generate rfbconfig.h
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/libvncserver/include/rfb/rfbconfig.h.cmakein
               ${CMAKE_CURRENT_BINARY_DIR}/include/rfb/rfbconfig.h)

# Configure libvncclient
set(LIBVNCCLIENT_SOURCES
    ${LIBVNCCLIENT_DIR}/cursor.c
    ${LIBVNCCLIENT_DIR}/listen.c
    ${LIBVNCCLIENT_DIR}/rfbclient.c
    ${LIBVNCCLIENT_DIR}/sockets.c
    ${LIBVNCCLIENT_DIR}/vncviewer.c
    ${COMMON_DIR}/sockets.c
    ${CRYPTO_SOURCES}
)

# Use TLS_none (no TLS support for simplicity)
set(LIBVNCCLIENT_SOURCES
    ${LIBVNCCLIENT_SOURCES}
    ${LIBVNCCLIENT_DIR}/tls_none.c
)

# Use minilzo (no LZO dependency)
set(LIBVNCCLIENT_SOURCES
    ${LIBVNCCLIENT_SOURCES}
    ${COMMON_DIR}/minilzo.c
)

# Include directories
include_directories(
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/include
    ${NATIVERENDER_ROOT_PATH}/libvncserver/include
    ${NATIVERENDER_ROOT_PATH}/libvncserver/src/common
    ${LIBVNCCLIENT_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}/include
)

# HiSH sources
add_library(entry SHARED
    napi_init.cpp
    napi_vnc.cpp
    vnc_client.cpp
    vnc_renderer.cpp
    utils.cpp
    ${LIBVNCCLIENT_SOURCES}
)

target_link_libraries(entry PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    libEGL.so
    libGLESv3.so
    libnative_window.so
)
