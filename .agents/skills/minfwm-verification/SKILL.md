---
name: minfwm-verification
description: Bind minfwm check evidence and manual acceptance to the actual candidate and integration SHA.
---

# Evidence before completion

This is a locally authored stage adapter; read `ADAPTATION.md`.
Inspect the task acceptance, candidate SHA, checkout status, relevant environment
and existing proofs. Record command, exit status, output/artifact, timestamp,
actual tested SHA and tree digest. A dirty checkout must be identified explicitly;
do not present its HEAD as proof of the modified files. Read output before
claiming success. Missing or failed evidence is a gap, never an inferred pass.

Build runs focused checks before review. Test performs the broader required
checks and negative scenarios for the candidate. Integration's actual committed
SHA requires the repository full checks:

```sh
cmake -S . -B build -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

Reuse proofs only for the same exact tested SHA and relevant unchanged checkout
and environment. A new merge/cherry-pick/rebase identity, changed base or conflict
resolution requires full checks on the actual integration SHA, even for an equal
tree digest. When AI infrastructure changes, also run its Python validators and
focused unittests. Do not repeatedly rerun unchanged focused proofs as a ritual.

Record `manual: not-required | pending | passed | failed` and a reason. AX,
WindowServer, CGEventTap and live SA checks are manual-only using
`docs/acceptance-macos.md`. A task promising visible behavior cannot be Done with
pending manual checks. Code-only changes may justify not-required. Do not start
the daemon or change SIP/permissions implicitly.

Return actual accepted SHA, check evidence, manual status, gaps and measured
usage (or `unavailable`). The coordinator is the only lifecycle owner and decides
whether the acceptance permits Done. Verification does not install tools, run a
second scheduler, merge branches, or write canonical task state independently.
