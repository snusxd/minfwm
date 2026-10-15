# TASK-OVERVIEW-NONREWIND

Stage: test; implementation and automated checks passed, live acceptance pending.
Participants: `/root`, `/root/overview_click_worker`, `/root/overview_review` (Codex).

Goal: `rewind-on-focus = false` preserves zoom when selecting a preview. It must
not disable preview rendering or the Screen Recording permission request.

Acceptance: first click promotes and focuses the original at the current scale
after successful live presentation, without click-through; subsequent native
input works. Pending selection uses weak ownership, has bounded failure handling,
and never changes camera/zoom. Rewinding selection and modifiers retain their
behavior. Preserve unrelated local work and integrate task-owned changes directly
into main. The policy/permission tests first demonstrated four expected failures
on the original code; implementation and focused/full checks follow.

Checks: overview policy/permission tests, daemon build, relevant rendering/input
checks and full CTest at integration. Actual AX focus, desktop hit testing and
event-tap behavior remain manual using `docs/Acceptance-macos.md`.

Evidence: four new policy/permission checks failed on the original implementation
then passed after the correction. The clean joint candidate and the main working
tree each passed full build and all 15 CTest targets. Independent read-only review
found zero actionable findings and reran focused checks. First-click selection and
native keyboard focus remain manual-only; no daemon restart was performed.
