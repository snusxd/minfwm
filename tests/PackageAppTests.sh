#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$1"
MINFWM_BIN="$2"

TMP_WORK="$(mktemp -d /tmp/minfwm-package-test-XXXXXX)"
trap 'rm -rf "$TMP_WORK"' EXIT

# 1. Verify relative OUT_APP works even though package_app.sh cds into app/
cd "$TMP_WORK"
APP_VERSION="v1.2" \
MINFWM_BIN="$MINFWM_BIN" \
OUT_APP="rel/minfWM.app" \
bash "$ROOT_DIR/app/Scripts/package_app.sh" >/dev/null

test -d "$TMP_WORK/rel/minfWM.app"
test -x "$TMP_WORK/rel/minfWM.app/Contents/MacOS/Minfwm"
test -x "$TMP_WORK/rel/minfWM.app/Contents/Resources/minfwm"
test -f "$TMP_WORK/rel/minfWM.app/Contents/Resources/AppIcon.icns"
test -f "$TMP_WORK/rel/minfWM.app/Contents/Info.plist"

# 2. Verify Info.plist version stripping (v1.2 -> 1.2) and bundle ID
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$TMP_WORK/rel/minfWM.app/Contents/Info.plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$TMP_WORK/rel/minfWM.app/Contents/Info.plist")"
if [[ "$version" != "1.2" ]]; then
  echo "FAIL: expected CFBundleShortVersionString=1.2, got '$version'" >&2
  exit 1
fi
if [[ "$bundle_id" != "com.minfwm.app" ]]; then
  echo "FAIL: expected CFBundleIdentifier=com.minfwm.app, got '$bundle_id'" >&2
  exit 1
fi

# 3. Verify SVG assets exist and contain valid <svg> tags
for svg in "$ROOT_DIR/assets/icon-dark.svg" "$ROOT_DIR/assets/menubar-icon.svg"; do
  test -f "$svg"
  grep -q "<svg" "$svg"
done

echo "PackageAppTests: all checks passed"
