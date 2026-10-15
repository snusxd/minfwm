cmake_minimum_required(VERSION 3.20)
project(minfwm LANGUAGES CXX OBJCXX OBJC)

execute_process(
    COMMAND git rev-parse --short HEAD
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    OUTPUT_VARIABLE MINFWM_BUILD_COMMIT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
if(NOT MINFWM_BUILD_COMMIT)
    set(MINFWM_BUILD_COMMIT "unknown")
endif()
set(MINFWM_BUILD_VERSION "${MINFWM_BUILD_COMMIT}" CACHE STRING "Version shown by minfwm version")

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
find_library(SCREEN_CAPTURE_KIT_FRAMEWORK ScreenCaptureKit REQUIRED)

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

add_library(minfwm_ipc_transport STATIC src/common/LocalSocketListener.cpp)
target_link_libraries(minfwm_ipc_transport PUBLIC minfwm_common)

# Pure C++ state and geometry core.
add_library(minfwm_core STATIC
    src/core/Geometry.cpp
    src/core/Camera.cpp
    src/core/Visibility.cpp
    src/core/DisplayState.cpp
    src/core/PanGesture.cpp
)
target_compile_features(minfwm_core PUBLIC cxx_std_20)
target_include_directories(minfwm_core PUBLIC src/core)

# Objective-C++ adapter for AX window ownership and identity.
add_library(minfwm_window_pool STATIC src/daemon/WindowPool.mm)
target_compile_features(minfwm_window_pool PUBLIC cxx_std_20)
target_include_directories(minfwm_window_pool PUBLIC src/daemon src/core)
target_link_libraries(minfwm_window_pool PUBLIC minfwm_core ${COMMON_LIBS})

add_library(minfwm_window_runtime STATIC
    src/daemon/WindowRenderer.mm
    src/daemon/AXBackend.mm
    src/daemon/WindowPosition.mm
)
target_link_libraries(minfwm_window_runtime PUBLIC minfwm_window_pool)

# Screenshots/canvases stay behind an Objective-C++ adapter; test doubles do
# not touch WindowServer, Accessibility, or Screen Recording permissions.
add_library(minfwm_overview_preview STATIC src/daemon/OverviewPreview.mm)
set_source_files_properties(src/daemon/OverviewPreview.mm PROPERTIES COMPILE_FLAGS "-fobjc-arc")
target_link_libraries(minfwm_overview_preview PUBLIC minfwm_window_pool ${SCREEN_CAPTURE_KIT_FRAMEWORK})

# Daemon adapters, also linked by socket lifecycle tests without starting AX.
add_library(minfwm_daemon_runtime STATIC
    src/daemon/DaemonRunLoop.mm
    src/daemon/DisplayFrameClock.mm
    src/daemon/WindowManager.mm
    src/daemon/AXObserver.mm
    src/daemon/InputInterceptor.mm
    src/daemon/TrackpadInput.mm
    src/daemon/IPCServer.mm
    src/daemon/YabaiSA.mm
    src/daemon/ConfigManager.mm
)
target_include_directories(minfwm_daemon_runtime SYSTEM PRIVATE third_party/tomlplusplus)
target_link_libraries(minfwm_daemon_runtime PUBLIC minfwm_ipc_transport minfwm_window_runtime minfwm_overview_preview ${COMMON_LIBS})

# CLI and daemon share one executable. LaunchAgent starts it with the `daemon`
# subcommand; normal invocations continue to use the CLI commands.
add_executable(minfwm
    src/cli/main.mm
    src/cli/IPCClient.mm
    src/cli/CommandLine.cpp
    src/cli/DaemonControl.mm
    src/daemon/main.mm
)
target_link_libraries(minfwm PRIVATE minfwm_common minfwm_daemon_runtime ${COMMON_LIBS})
target_compile_definitions(minfwm PRIVATE
    MINFWM_BUILD_COMMIT="${MINFWM_BUILD_COMMIT}"
    MINFWM_BUILD_VERSION="${MINFWM_BUILD_VERSION}"
    MINFWM_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
    MINFWM_BUILD_DIR="${CMAKE_BINARY_DIR}"
)

# Run explicitly on a desktop session; never run as part of automated CTest.
add_executable(minfwm_manual_window_move EXCLUDE_FROM_ALL tools/ManualWindowMove.mm)
target_link_libraries(minfwm_manual_window_move PRIVATE minfwm_daemon_runtime)

if(BUILD_TESTING)
    add_executable(minfwm_permission_gate_tests tests/PermissionGateTests.cpp)
    target_include_directories(minfwm_permission_gate_tests PRIVATE src/daemon)
    add_test(NAME minfwm_permission_gate_tests COMMAND minfwm_permission_gate_tests)

    add_executable(minfwm_window_position_tests tests/WindowPositionTests.mm)
    target_include_directories(minfwm_window_position_tests PRIVATE src/common src/daemon)
    target_link_libraries(minfwm_window_position_tests PRIVATE ${COMMON_LIBS})
    add_test(NAME minfwm_window_position_tests COMMAND minfwm_window_position_tests)
    add_executable(minfwm_daemon_run_loop_tests tests/DaemonRunLoopTests.mm)
    target_link_libraries(minfwm_daemon_run_loop_tests PRIVATE minfwm_daemon_runtime)
    add_test(NAME minfwm_daemon_run_loop_tests COMMAND minfwm_daemon_run_loop_tests)
    set_tests_properties(minfwm_daemon_run_loop_tests PROPERTIES TIMEOUT 2)
    add_executable(minfwm_transform_payload_tests tests/TransformPayloadTests.m)
    target_link_libraries(minfwm_transform_payload_tests PRIVATE ${COMMON_LIBS})
    add_test(NAME minfwm_transform_payload_tests COMMAND minfwm_transform_payload_tests)
    add_executable(minfwm_ipc_tests
        tests/IPCProtocolTests.cpp
        src/cli/CommandLine.cpp
    )
    target_include_directories(minfwm_ipc_tests PRIVATE src/cli)
    target_link_libraries(minfwm_ipc_tests PRIVATE minfwm_common)
    add_test(NAME minfwm_ipc_protocol COMMAND minfwm_ipc_tests)

    add_executable(minfwm_local_socket_tests tests/LocalSocketTests.cpp)
    target_link_libraries(minfwm_local_socket_tests PRIVATE minfwm_ipc_transport)
    add_test(NAME minfwm_local_socket_tests COMMAND minfwm_local_socket_tests)

    add_executable(minfwm_ipc_server_tests tests/IPCServerTests.cpp src/cli/IPCClient.mm)
    target_include_directories(minfwm_ipc_server_tests PRIVATE src/cli)
    target_link_libraries(minfwm_ipc_server_tests PRIVATE minfwm_daemon_runtime)
    add_test(NAME minfwm_ipc_server_tests COMMAND minfwm_ipc_server_tests)
    set_tests_properties(minfwm_ipc_server_tests PROPERTIES TIMEOUT 10)
endif()

if(BUILD_TESTING)
    add_executable(minfwm_geometry_tests tests/GeometryTests.cpp)
    target_link_libraries(minfwm_geometry_tests PRIVATE minfwm_core)
    add_test(NAME minfwm_geometry_tests COMMAND minfwm_geometry_tests)

    add_executable(minfwm_pan_gesture_tests tests/PanGestureTests.cpp)
    target_link_libraries(minfwm_pan_gesture_tests PRIVATE minfwm_core)
    add_test(NAME minfwm_pan_gesture_tests COMMAND minfwm_pan_gesture_tests)

    add_executable(minfwm_window_pool_tests tests/WindowPoolTests.mm)
    target_link_libraries(minfwm_window_pool_tests PRIVATE minfwm_window_pool)
    add_test(NAME minfwm_window_pool_tests COMMAND minfwm_window_pool_tests)

    add_executable(minfwm_window_renderer_tests tests/WindowRendererTests.mm)
    target_link_libraries(minfwm_window_renderer_tests PRIVATE minfwm_window_runtime)
    add_test(NAME minfwm_window_renderer_tests COMMAND minfwm_window_renderer_tests)

    add_executable(minfwm_overview_preview_tests tests/OverviewPreviewTests.mm)
    set_source_files_properties(tests/OverviewPreviewTests.mm PROPERTIES COMPILE_FLAGS "-fobjc-arc")
    target_link_libraries(minfwm_overview_preview_tests PRIVATE minfwm_overview_preview)
    add_test(NAME minfwm_overview_preview_tests COMMAND minfwm_overview_preview_tests)

    add_executable(minfwm_config_tests
        tests/ConfigTests.mm
        src/daemon/ConfigManager.mm
    )
    target_include_directories(minfwm_config_tests PRIVATE src/daemon)
    target_include_directories(minfwm_config_tests SYSTEM PRIVATE third_party/tomlplusplus)
    target_link_libraries(minfwm_config_tests PRIVATE ${COMMON_LIBS})
    add_test(NAME minfwm_config_tests COMMAND minfwm_config_tests)

    add_executable(minfwm_yabai_sa_tests
        tests/YabaiSATests.mm
        src/daemon/YabaiSA.mm
    )
    target_include_directories(minfwm_yabai_sa_tests PRIVATE src/daemon)
    target_link_libraries(minfwm_yabai_sa_tests PRIVATE minfwm_window_runtime minfwm_common ${COMMON_LIBS})
    add_test(NAME minfwm_yabai_sa_tests COMMAND minfwm_yabai_sa_tests)
endif()
