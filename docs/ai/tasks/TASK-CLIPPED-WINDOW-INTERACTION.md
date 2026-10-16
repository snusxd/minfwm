# TASK-CLIPPED-WINDOW-INTERACTION

Stage: integration; universal architecture candidate, live acceptance pending.
Participants: Codex `/root` (builder), `/root/clipped_review` (independent reviewer).
Base: f072460; changes remain uncommitted.

Goal: remove competing native-frame and canvas-position writers during ordinary
window dragging/resizing, including partly clipped windows. User requires a common
mechanism across applications rather than application-specific chrome exceptions.

Decision: docs/ai/ADR-NATIVE-INTERACTION.md. Native events are unchanged. Each window
gets an immutable native/canvas/visual/pointer/scale baseline. Actual native frame
changes classify movement/resizing. Application owns native size; manager owns
presentation. Every active frame checks actual transform, repairs only presentation,
and prevents normal AX rendering/hiding/native handoff for that transaction.
Release samples final app geometry after UP. Failed reads retain the model and retry
for a bounded interval. Explicit managed capture retires the previous native writer.

Acceptance: native clamp, all resize anchors, stale model size, scale and negative
origins, stationary controls, quick same/different-window gestures, DE handoff,
malformed reads, failed presentation without transform reset, lifecycle cleanup,
trace correlation. Focused regression tests plus full build/CTest and risk-triggered
independent review. Actual flicker, native delivery, app constraints and latency
require docs/Acceptance-macos.md evidence. No daemon restart or live write performed.

History: initial clipped-chrome capture and AX-metadata/size-limit attempts passed
synthetic checks but user reported continued visual failures. Those mechanisms are
removed from the current candidate. Previous green test/review verdicts and product
digests apply only to superseded candidates and do not establish this bug resolved.
The trace showed successful immediate SA writes alongside later native geometry
changes; it does not prove a synchronous flicker-free presentation boundary.

Current regression evidence: new pure interaction tests first failed 7 assertions;
presentation ownership tests first failed 5. Independent review found pending-native
versus DE ownership and scaled failure reset gaps; both receive focused coverage.
Integration results and reviewer verdict are recorded after the stable rebuild.

Manual: pending. Usage: unavailable. No claim of visual resolution from fake APIs.
Diagnostic capture: docs/Window-Interaction-Diagnostics.md.

Integration evidence (2026-10-16): full build exit0; full CTest18/18 passed.
Final diagnostic-only delta rebuilt successfully and affected interaction/renderer
CTest2/2 passed. git diff --check passed. Independent reviewer inspected final
ownership, finite-validation and diagnostic deltas: automated spec pass, quality
pass, zero remaining actionable findings. Reviewer independently ran six focused
CTest targets successfully before the final narrow diagnostic delta.
Product/test SHA256 (sorted paths + NUL + bytes + NUL): a70f649f1c429b5fc2ce1e5b395d10af68045af526f41f01d65cbe0b2bcdbaf3.
This fingerprint excludes documentation; live acceptance remains pending.
