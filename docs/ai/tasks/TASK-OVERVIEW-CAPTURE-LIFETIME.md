# TASK-OVERVIEW-CAPTURE-LIFETIME

Participant: `/root` (Codex).
Stage: test; native callback regression reproduced and fixed; live acceptance pending.

Problem: after Screen Recording was granted, the daemon crashed on its first
overview screenshot. The macOS crash report places the invalid read in
`ScreenshotProvider::captureWindow`'s callback, at `cache->generation`.

Cause: an Objective-C block captures a C++ reference parameter by reference.
The discovery continuation's local shared pointer had already been destroyed
when the screenshot completion tried to use it. Pass the shared pointer by value
so the block owns the cache until completion.

Acceptance: deferred callbacks survive both discovery and cached-content paths,
provider destruction and session reset. Successful borrowed images remain owned
after the native callback returns; stale/error results preserve live fallback.
No real capture, permission change, daemon launch or unrelated edit is permitted
as part of automated verification. Integrate only owned changes into main.

Evidence: a regression exercising the actual private provider with intercepted
ScreenCaptureKit methods failed before the fix under AddressSanitizer with
`heap-use-after-free` at `OverviewPreview.mm:104`. The corrected provider passed
the same sanitizer test, including successful image delivery, error delivery,
cached content, reset and destruction. Logs: `/tmp/minfwm-capture-lifetime-red.log`
and `/tmp/minfwm-capture-lifetime-green.log`. Full build and all 16 CTest targets
passed on the main working tree (which also contains unrelated unstaged changes);
log: `/tmp/minfwm-capture-lifetime-check.log`. A clean archive of the committed
integration is checked separately; log: `/tmp/minfwm-capture-integration-check.log`.

The latest separate launch was blocked by Accessibility: TCC reported a mismatch
between the saved and current ad-hoc code requirements. Screen Recording had
already been granted before the crash. Neither permission was modified here.
Live overview/AX/SA acceptance remains pending using `docs/Acceptance-macos.md`.
