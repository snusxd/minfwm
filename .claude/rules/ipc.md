---
paths:
  - "src/cli/**"
  - "src/common/**"
  - "src/daemon/IPCServer.*"
  - "tests/{IPCProtocolTests,LocalSocketTests,PermissionGateTests}.cpp"
  - "tests/IPCServerTests.cpp"
---

# CLI and IPC

- `src/common/Protocol.hpp` owns the versioned binary wire contract. Change it test-first: malformed frames, truncated/partial reads and writes, and version mismatch each get a CTest.
- The socket is `$TMPDIR/minfwm.sock`, owned by the user, mode `0600`. Never widen permissions or move it to a shared path.
- Sockets are owned through `UniqueFd`; every `read`/`write`/`accept` result is checked, including short counts and `EINTR`.
