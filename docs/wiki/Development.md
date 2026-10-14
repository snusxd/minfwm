# Development

## Layout

`src/core/` contains pure geometry and policy. `src/daemon/` contains the macOS
adapter. `src/cli/` and `src/common/` contain the command line and IPC contract.
`tests/` contains CTest targets; `tools/` contains development utilities.

## Build and checks

```sh
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

Focused targets:

```sh
cmake --build build --target minfwm_geometry_tests
ctest --test-dir build -R geometry
cmake --build build --target minfwm_ipc_tests
ctest --test-dir build -R ipc
cmake --build build --target minfwm_yabai_sa_tests
ctest --test-dir build -R yabai
```

Accessibility, WindowServer, event tap, and live SA behavior require manual
checks on macOS and are not established by CI. See
[macOS acceptance](https://github.com/snusxd/minfwm/wiki/Acceptance-macos#macos-acceptance).
