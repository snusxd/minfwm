cmake_minimum_required(VERSION 3.20)
project(minfwm LANGUAGES CXX OBJCXX)

# Require C++20
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Compile strictly for Apple Silicon
set(CMAKE_OSX_ARCHITECTURES arm64)

# Define executable and sources
add_executable(minfwm 
    src/main.mm
    src/ClientWindow.cpp
    src/Application.cpp
    src/WindowManager.mm
    src/GridLayout.cpp
    src/Camera.cpp
    src/WindowPool.mm
    src/DisplayManager.mm
)

# Link required macOS Frameworks
target_link_libraries(minfwm PRIVATE
    "-framework Cocoa"
    "-framework ApplicationServices"
    "-framework CoreGraphics"
    "-framework CoreFoundation"
)
