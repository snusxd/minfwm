# ADR 0002: Versioned Local IPC

## Status

Accepted for phase one.

## Decision

The Unix socket protocol uses a fixed little-endian frame: four-byte `MFWM`
magic, one-byte version `1`, two-byte command, four-byte payload length, and a
payload capped at 64 bytes. `RELOAD` has no payload. `CAMERA_MOVE` carries two
IEEE-754 `float32` values. The server returns a status and stable error code;
unsupported commands are not successful no-ops.

All stream operations use exact-read/all-write helpers. The socket is created
under the user-owned `TMPDIR` runtime directory, checked for ownership/type,
and mode `0600` is enforced. The CLI validates arguments before connecting and
uses nonzero exit codes for usage, transport, and daemon errors.

## Consequences

The wire format is independent of C++ struct layout and can reject malformed
or oversized input before dispatch. Future commands require a new documented
payload contract; reserved commands remain unsupported until implemented.
