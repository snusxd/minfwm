# MinfWM (macOS Infinite Window Manager) - Project Blueprint

## 🎯 Core Concept
A Tiling Window Manager for macOS (Apple Silicon / ARM64) implementing an "Infinite Canvas" workspace.
Instead of using native macOS Spaces, MinfWM uses a 2D virtual camera to pan across a borderless, infinite workspace.

## 🏗 Architecture & State Management
- **Virtual Camera**: Maintained via `viewport_x` and `viewport_y`.
- **Window Coordinates**: Every tracked window (e.g., `ClientWindow` struct) stores its *absolute* coordinates on the infinite canvas.
- **Screen Mapping Formula**: `screen_pos = absolute_pos - viewport_pos`.
- **Bypassing macOS Limits**: Uses **Yabai Scripting Addition (SA)** to move window title bars above the menu bar ($Y < 38$) by communicating with the Yabai UNIX socket.

## 🛠 Technical Stack & Constraints
- **Language**: C++20 + Objective-C++ (`.mm`).
- **Architecture**: ARM64 (Apple Silicon).
- **Event Loop**: Pure `CFRunLoop`.
- **Low-level Hook**: `CGEventTap` for intercepting `Cmd + Option + Drag`.
- **Required Env**: SIP partially disabled (`--without debug --without fs --without nvram`), boot-arg `-arm64e_preview_abi`, and `yabai --load-sa` active.

---

## 🗺 Detailed Implementation Plan

### Phase 1: Foundation (✅ Completed)
- [x] Setup CMake for C++20 and ARM64.
- [x] Initialize `CFRunLoop`.
- [x] Request and verify macOS Accessibility permissions.
- [x] Install global `CGEventTap` for mouse tracking.

### Phase 2: Core Data Structures & Window Tracking (✅ Completed)
- [x] **Create `ClientWindow` class**: Wrapper for `AXUIElementRef`.
- [x] **Create `Application` class**: Manages `AXObserverRef` to listen for window events per-app.
- [x] **Create `WindowManager`**: State Singleton managing viewport and app lists.
- [x] **Hook App Launches**: Using `NSWorkspace` notifications.
- [x] **Hook Window Events**: Listen for Create, Destroy, Move, and Resize notifications.

### Phase 3: The Infinite Canvas (Panning) (✅ Completed)
- [x] **Modifier Detection**: `Cmd + Option` chord detection in Event Tap.
- [x] **Panning Logic**: High-performance panning using raw mouse deltas.
- [x] **Bypass Clamping**: Integrated Yabai SA socket communication (0x06 MOVE opcode) to allow windows to move above the menu bar.
- [x] **Feedback Loop Fix**: Implemented notification suppression during active panning to prevent "rubber-band" flickering.

### Phase 4: Tiling Engine (✅ In Progress)
- [x] **Layout Interface (`ILayout`)**: Abstract base for different tiling strategies.
- [x] **GridLayout**: Initial implementation of an infinite grid (1200x800 windows).
- [x] **Floating Mode**: Standard windows are tiled; popups and dialogs are ignored.
- [ ] **Real-time Re-tiling**: Refine the trigger for automatic layout application without causing unexpected jumps.

### Phase 5: Keyboard Navigation & Hotkeys (📅 Planned)
- [ ] **Global Hotkeys**: Intercept keys for camera movement and window focus.
- [ ] **Shortcuts**: `Mod + Arrows` (Pan), `Mod + Shift + Arrows` (Move Window).

### Phase 6: IPC & CLI (📅 Planned)
- [ ] **Unix Domain Socket**: Internal socket for controlling the daemon.
- [ ] **CLI Client**: `minfwmc` tool for sending commands.
