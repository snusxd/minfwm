cmake_minimum_required(VERSION 3.20)
project(minfwm LANGUAGES CXX OBJCXX)

include(CTest)

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
find_library(QUARTZ_CORE_FRAMEWORK QuartzCore)

set(COMMON_LIBS
    ${CORE_GRAPHICS_FRAMEWORK}
    ${APP_KIT_FRAMEWORK}
    ${APPLICATION_SERVICES_FRAMEWORK}
    ${FOUNDATION_FRAMEWORK}
    ${QUARTZ_CORE_FRAMEWORK}
)

# Shared common code (IPC, logging, etc.)
add_library(minfwm_common INTERFACE)
target_include_directories(minfwm_common INTERFACE src/common)

# Pure C++ state and geometry core.
add_library(minfwm_core STATIC
    src/core/Geometry.cpp
    src/core/Camera.cpp
    src/core/Visibility.cpp
    src/core/DisplayState.cpp
)
target_compile_features(minfwm_core PUBLIC cxx_std_20)
target_include_directories(minfwm_core PUBLIC src/core)

# Objective-C++ adapter for AX window ownership and identity.
add_library(minfwm_window_pool STATIC src/daemon/WindowPool.mm)
target_compile_features(minfwm_window_pool PUBLIC cxx_std_20)
target_include_directories(minfwm_window_pool PUBLIC src/daemon src/core)
target_link_libraries(minfwm_window_pool PUBLIC minfwm_core ${COMMON_LIBS})

# Daemon
add_executable(minfwmd
    src/daemon/main.mm
    src/daemon/WindowManager.mm
    src/daemon/AXObserver.mm
    src/daemon/InputInterceptor.mm
    src/daemon/IPCServer.mm
    src/daemon/AXBackend.mm
    src/daemon/YabaiSA.mm
    src/daemon/ConfigManager.mm
)
target_link_libraries(minfwmd PRIVATE minfwm_common minfwm_window_pool ${COMMON_LIBS})

# CLI
add_executable(minfwmc
    src/cli/main.mm
    src/cli/IPCClient.mm
    src/cli/CommandLine.cpp
)
target_link_libraries(minfwmc PRIVATE minfwm_common ${COMMON_LIBS})

if(BUILD_TESTING)
    add_executable(minfwm_ipc_tests
        tests/IPCProtocolTests.cpp
        src/cli/CommandLine.cpp
    )
    target_include_directories(minfwm_ipc_tests PRIVATE src/cli)
    target_link_libraries(minfwm_ipc_tests PRIVATE minfwm_common)
    add_test(NAME minfwm_ipc_protocol COMMAND minfwm_ipc_tests)
endif()

if(BUILD_TESTING)
    add_executable(minfwm_geometry_tests tests/GeometryTests.cpp)
    target_link_libraries(minfwm_geometry_tests PRIVATE minfwm_core)
    add_test(NAME minfwm_geometry_tests COMMAND minfwm_geometry_tests)

    add_executable(minfwm_window_pool_tests tests/WindowPoolTests.mm)
    target_link_libraries(minfwm_window_pool_tests PRIVATE minfwm_window_pool)
    add_test(NAME minfwm_window_pool_tests COMMAND minfwm_window_pool_tests)

    add_executable(minfwm_config_tests
        tests/ConfigTests.mm
        src/daemon/ConfigManager.mm
    )
    target_include_directories(minfwm_config_tests PRIVATE src/daemon)
    target_link_libraries(minfwm_config_tests PRIVATE ${COMMON_LIBS})
    add_test(NAME minfwm_config_tests COMMAND minfwm_config_tests)

    add_executable(minfwm_yabai_sa_tests
        tests/YabaiSATests.mm
        src/daemon/YabaiSA.mm
    )
    target_include_directories(minfwm_yabai_sa_tests PRIVATE src/daemon)
    target_link_libraries(minfwm_yabai_sa_tests PRIVATE ${COMMON_LIBS})
    add_test(NAME minfwm_yabai_sa_tests COMMAND minfwm_yabai_sa_tests)
endif()
