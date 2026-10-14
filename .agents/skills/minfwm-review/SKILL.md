---
name: minfwm-review
description: Independently review one minfwm candidate for specification compliance and code quality.
---

# Independent review

This is a locally authored, read-only stage adapter; read `ADAPTATION.md`.
The coordinator supplies acceptance, applicable instructions, base/result SHAs,
the complete commit range, owned paths, relevant contracts/tests and evidence.
Review the actual diff and source. The builder's narrative is supporting context,
never a substitute for inspection. Verify that SHAs and packet revision match.

Use a different agent from the builder. One reviewer is the default; another
reviewer requires a separate risk or contract. Return separate spec-compliance
and code-quality verdicts with paths, specific impact, reproduction or evidence,
severity and unresolved uncertainty. Zero actionable findings is valid. Never
manufacture a quota of issues or import arbitrary coverage thresholds.

Check scope/ownership, malformed and partial IPC, atomic config reload, resource
lifetime, AX fallback and negative display origins when the diff touches them.
Read only the relevant domain rubric and repository contracts. Do not run live
AX/WindowServer/event-tap/SA operations as an automated review check.

Do not modify product files, merge, commit, or promote the task. Return findings
to the coordinator for a builder fix and re-review of affected proofs. A changed
candidate invalidates a verdict until its affected changes have been inspected.
Record the reviewer in evidence; attribution includes reviewer tool identity only
when a review contribution actually enters the change.
