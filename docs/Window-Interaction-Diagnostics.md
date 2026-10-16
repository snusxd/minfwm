# Window interaction trace

Enable operation tracing with `MINFWM_TRACE_WINDOW_INPUT=1`. It is disabled by
default; unset, empty and `0` disable the new trace. Output goes to stderr, which
the managed daemon normally shares with stdout in `~/Library/Logs/minfwm.log`.
No titles, document content or key input are recorded.

For a self-contained capture from this checkout, stop the current daemon and
run the built candidate in the foreground:

```sh
./build/minfwm stop
MINFWM_TRACE_WINDOW_INPUT=1 ./build/minfwm daemon > ~/Library/Logs/minfwm-interaction-trace.log 2>&1
```

Reproduce a working gesture and a failing gesture in the same session, then
press Ctrl-C. Keep the full log, including startup, the actions preceding the
failure, and at least a second after release. Include the application, the edge
outside the camera, whether this was titlebar/resize/drag-everywhere, and the
approximate failure time when reporting it. This command starts the built binary
directly; no LaunchAgent environment changes are needed.

If operation trace is insufficient, rerun with sampled observation enabled:

```sh
MINFWM_TRACE_WINDOW_INPUT=1 MINFWM_TRACE_WINDOW_OBSERVE=1 ./build/minfwm daemon > ~/Library/Logs/minfwm-interaction-observe.log 2>&1
```

Observation compares AX origin/size, public WindowServer origin, native frame,
transform matrix, canvas model, projected geometry and renderer cache. It runs
at most 20 times per second per relevant window, from the frame loop, including
while native interaction owns presentation. It adds AX/WindowServer reads and
may change timing; compare against the operation-only capture. Logging itself
also adds I/O while enabled. Trace files are verbose and are not rotated by this
feature. Stop the foreground diagnostic daemon before starting another one.
Resume normal operation with `./build/minfwm start` after capture.

Each `WINDOW_TRACE` line has a process-local `seq`, monotonic `mono_ms`, daemon
`pid`, `thread`, `gesture`, `wid`, and `stage`. Gesture IDs are allocated for
physical left-button DOWN events and stored on the selected window so renderer,
AX callbacks and delayed verification retain the same correlation. `gesture=0`
means no associated physical gesture; `wid=0` means no selected window yet.
An old gesture ID on a later renderer operation is correlation, not proof that
the button is still held; use `input.received`, capture/end/cancel and owner fields.

Rectangles use `x,y,w,h` in logical points. `model` is canvas space, `projected`
and `physical` are screen space; `snapshot` is the cached WindowServer hit-test
frame. `native` is the untransformed native frame. The presentation transform is
logged as `a,b,c,d,tx,ty`. Compare only fields marked valid by their `*_ok` flag.
Backend result codes: `0=ok`, `1=unavailable`, `2=unsupported`, `3=failed`.
`ack=0` means the SA operation was not positively acknowledged; if `checked=0`,
position readback was skipped. It does not prove that WindowServer did nothing.

Useful stages:

- `input.received`, `input.tap-disabled`: untouched mouse input and interruption.
- `native.begin`: selected window, initial pointer and projected canvas frame.
- `native.reconcile`: native bounds, per-transaction pointer, old/new canvas model;
  kind `0=stationary`, `1=move`, `2=resize`.
- `native.observe-failed`: selected native frame/transform could not be read;
  canvas geometry stays unchanged and AX does not take over.
- `native.present`: actual transform matched or required repair, result and scale.
- `native.commit-result`: final accepted observation and model. `observed=1`
  requires valid native geometry and successful presentation; `observed=0`
  after the bounded retry interval records completion without a valid final repair.
- `gesture.capture/update-everywhere/end/cancel`: explicit Drag Everywhere.
- `ax.notification/sync/skip/defer`: notification and handling decision.
- `render.dirty/move/geometry-result/verify/verify-recovery`: normal rendering.
- `sa.transform-request/transform-result/reset/native-request/native-result`:
  SA writes, ACK/readback and reset policy.
- `position.readback`: target and observed position, with no additional query.
- `observe`: optional independent geometry probe.

The native path has no app-name, titlebar-height or resize-band classification.
DOWN/DRAG/UP reach the application unchanged; there is no click replay and no AX
size request during a native transaction. The OS event target WID selects the
window when available; otherwise selection uses the cached stacking snapshot.
At DOWN, two direct reads fetch only that window's native frame and transform;
no AX traversal or full window-list query occurs on this path. These synchronous
reads and trace I/O can affect timing and must be included in live latency checks.

Interpret a native-origin jump separately from presentation drift. For an
observed move, canvas displacement follows the pointer from the transaction's
baseline even when the native frame clamps. For resize, native logical dimensions
are authoritative and the opposite canvas edge is anchored. A stationary native
frame does not establish a move; content/control drags retain their native behavior.
Compare actual transform against the projected model at the same reconciliation
stage. A pre-render observation can legitimately differ from the next frame's
model target; an immediate successful SA ACK alone does not rule out a later
application transform change or visible flash.

Automated checks use synthetic input, injected observations and fake SA transport.
They cover frame clamping, scale/negative origins, rapid gestures, independent
window transactions, ownership handoff, failures and trace correlation. They do
not establish actual app event delivery or absence of visible flicker. Record
those checks with a video and operation/observation capture in Acceptance-macos.md.
