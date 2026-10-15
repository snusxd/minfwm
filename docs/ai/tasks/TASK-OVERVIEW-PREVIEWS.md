# TASK-OVERVIEW-PREVIEWS

Stage: test — automated implementation ready; manual acceptance pending.
Participants: `/root`, `/root/overview_adapter`, `/root/overview_review` (Codex).
Base: `7764edd8ee2837b73e24855258450df729e539f1`.
Plan: [overview-previews](../plans/overview-previews.md).

## Acceptance

- Bounded asynchronous screenshots, reusable canvas layers, live focus/whitelist
  exceptions, safe fallback and restoration.
- Focused and full automated checks on the candidate; independent risk review.
- Actual transformed-image framing, stacking/coordinates, lifecycle and measured
  desktop performance require the wiki macOS checklist before Done.

## Evidence

- Configure and full build succeeded with the macOS 14 deployment target.
- All 14 CTest targets passed; three focused preview/renderer/config tests passed.
- The 100-window/60-frame fake-backend test observed 6,000 live updates versus
  100 one-time preview parking moves. This is not a live performance benchmark.
- Adapter worker reported strict warnings and ASan/UBSan tests passed.
- Independent reviewer inspected the actual dirty product diff: spec pass,
  quality pass, zero actionable findings; independently reran focused binaries.
- Product modified-file SHA-256 at review: `9171bcddca0e2d9ee42ffbd3f62c6d30124dfcb0c7aedc0d8dbc860075ce7a8e`.
- Manual: pending. No daemon start/restart, capture permission change, SIP change
  or live capture was performed. No accepted integration SHA is claimed.

## Workflow limitation

The supplied runtime and one-time bootstrap both fail validation of historical
cards with `fatal: Needed a single revision`. Bootstrap confirmed the skill
profile then stopped before hook installation. Existing cards/hooks were left
unchanged. This Markdown card records the same seven-stage work without adding
an invalid JSON card to the runtime. The task remains at Test until manual
acceptance; usage measurements are unavailable.
