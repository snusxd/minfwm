cmake_minimum_required(VERSION 3.20)
project(minfwm LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Optimization for ARM64
if(APPLE AND CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
    add_compile_options("-mcpu=apple-m1")
endif()

# Frameworks
find_library(CORE_GRAPHICS_FRAMEWORK CoreGraphics)
find_library(APP_KIT_FRAMEWORK AppKit)
find_library(APPLICATION_SERVICES_FRAMEWORK ApplicationServices)
find_library(FOUNDATION_FRAMEWORK Foundation)

set(COMMON_LIBS
    ${CORE_GRAPHICS_FRAMEWORK}
    ${APP_KIT_FRAMEWORK}
    ${APPLICATION_SERVICES_FRAMEWORK}
    ${FOUNDATION_FRAMEWORK}
)

# Shared common code (IPC, logging, etc.)
add_library(minfwm_common INTERFACE)
target_include_directories(minfwm_common INTERFACE src/common)

# Daemon
add_executable(minfwmd
    src/daemon/main.mm
    src/daemon/WindowManager.mm
    src/daemon/Camera.mm
    src/daemon/WindowPool.mm
    src/daemon/AXObserver.mm
    src/daemon/InputInterceptor.mm
    src/daemon/IPCServer.mm
    src/daemon/YabaiSA.mm
    src/daemon/ConfigManager.mm
)
target_link_libraries(minfwmd PRIVATE minfwm_common ${COMMON_LIBS})

# CLI
add_executable(minfwmc
    src/cli/main.mm
    src/cli/IPCClient.mm
)
target_link_libraries(minfwmc PRIVATE minfwm_common ${COMMON_LIBS})
