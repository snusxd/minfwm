# Native interaction and canvas presentation ownership

Status: implemented candidate; live macOS acceptance pending.

## Problem

A native frame and an absolute presentation transform are different coordinate
systems. The previous path stopped rendering during native input, then adopted
WindowServer presentation coordinates at release. AppKit could meanwhile clamp
its native frame or replace/adjust its transform. Chrome hit bands and AX control
caches selected a competing managed drag implementation; they cannot provide a
universal contract for arbitrary applications.

## Decision

Keep native input native. No titlebar/edge recognition, intercepted click replay,
app-name tables or AX chrome traversal. Record one immutable native/canvas/pointer
baseline for the selected window. Prefer the public event target WID; use cached
stacking selection only when it is absent. Read just the selected native frame and
transform at DOWN; no AX traversal or complete WindowServer list query. Observe native frame changes in the frame loop.
A move is recognized from native geometry changing under a real pointer drag;
once recognized, canvas displacement follows the pointer in canvas units, even
if the native frame subsequently stops at a physical display edge. A resize uses
actual native dimensions and anchors the opposite canvas edges; actual dimensions
are native logical units, never inversely scaled screen presentation dimensions.
Unchanged native geometry (content/button/scrollbar input) does not move the canvas.

The application owns its native frame. The compositor owns the presentation
transform. During interaction the daemon may reassert presentation, but never
writes native position/size, resets the transform, hides the active window, or
hands it back and forth between coordinate systems. Release reconciles the final
native sample after the app has processed UP, then ends the transaction without
adopting visual coordinates a second time. Normal renderer/native handoff resumes
only after that boundary. Camera/scale changes cannot change the transaction's
coordinate baseline. Pending completions keep their own final pointer; a new native
gesture on the same window rebases once, and explicit Drag Everywhere retires the
previous native writer before taking ownership. Failed final reads/presentation
retry for up to 500 ms, then release ownership without inventing final geometry.
Both scale-one and scaled repairs preserve transform ownership on uncertain ACKs.

## Validation and limits

Pure tests cover coordinate epochs, stale model size, native clamping, resize
anchors, negative origins, scale, malformed observations and stationary input.
Injected adapter tests prove no AX geometry writes/reset/native handoff during a
native transaction and verify repair even at unchanged cached coordinates. Native
mouse input is delivered unmodified in production callback tests. Actual visual
behavior, app constraints and event-tap interruption remain manual acceptance.

This design does not claim a synchronous WindowServer pre-presentation hook.
The upstream Yabai declarations provide frame/transform reads and transform
writes, but no demonstrated atomic cross-process AX/frame callback contract:
https://github.com/asmvik/yabai/blob/master/src/misc/extern.h
Use existing checked SA operations, rather than introduce an unverified hook or
screen-wide update lock around another process. A physical frame that never
changes offers no universal evidence that a control intended to move a window;
that boundary must be measured, not hidden behind a per-app exception.
