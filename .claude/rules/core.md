---
paths:
  - "src/core/**"
  - "tests/{GeometryTests,PanGestureTests,NativeWindowInteractionTests}.cpp"
---

# Core (`src/core/`)

- Pure C++20 with zero macOS dependencies. If a change needs a platform type, convert it at the daemon adapter and pass plain values in.
- Coordinate model: every window has a position on an endless per-display canvas; each display's camera projects that canvas onto the physical screen. Displays keep independent cameras. Secondary displays may have negative origins; every projection and visibility test must hold for them (cover it in a test).
- Visibility/culling only decides rendering. It never drops or rewrites a window's canvas position.
- Overview previews are a rendering optimization, not a second window model: a preview occupies the same projected bounds as its window.
