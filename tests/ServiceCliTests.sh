#!/usr/bin/env bash
set -euo pipefail

MINFWM_BIN="$1"

# 1. `minfwm service` rejects unexpected arguments with "service" wording
set +e
out_service="$("$MINFWM_BIN" service --unexpected 2>&1)"
rc_service=$?
out_daemon="$("$MINFWM_BIN" daemon --unexpected 2>&1)"
rc_daemon=$?
out_usage="$("$MINFWM_BIN" 2>&1)"
rc_usage=$?
set -e

if [[ $rc_service -ne 2 ]] || [[ "$out_service" != *"service does not accept arguments"* ]]; then
  echo "FAIL: unexpected 'minfwm service --unexpected' output (rc=$rc_service): $out_service" >&2
  exit 1
fi

# 2. `minfwm daemon` alias remains supported and reports "service" wording
if [[ $rc_daemon -ne 2 ]] || [[ "$out_daemon" != *"service does not accept arguments"* ]]; then
  echo "FAIL: unexpected 'minfwm daemon --unexpected' output (rc=$rc_daemon): $out_daemon" >&2
  exit 1
fi

# 3. Usage line advertises `service`, not `daemon`
if [[ $rc_usage -ne 2 ]] || [[ "$out_usage" != *"service|start|stop"* ]] || [[ "$out_usage" == *"daemon"* ]]; then
  echo "FAIL: unexpected usage output (rc=$rc_usage): $out_usage" >&2
  exit 1
fi

echo "ServiceCliTests: all checks passed"
