#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_PKG_DIR="$ROOT_DIR/app"
ARCH="${ARCH:-$(uname -m)}"
APP_VERSION="${APP_VERSION:-0.1.0}"
OUT_APP="${OUT_APP:-$ROOT_DIR/build/minfWM.app}"
MINFWM_BIN="${MINFWM_BIN:-$ROOT_DIR/build/minfwm}"
if [[ "$OUT_APP" != /* ]]; then
  OUT_APP="$PWD/$OUT_APP"
fi
if [[ "$MINFWM_BIN" != /* ]]; then
  MINFWM_BIN="$PWD/$MINFWM_BIN"
fi
CONTENTS_DIR="$OUT_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SRC="$ROOT_DIR/assets/minfwm.icon"
XCODE_APP="${XCODE_APP:-/Applications/Xcode.app}"

echo "==> Building Minfwm Swift app ($ARCH)..."
cd "$APP_PKG_DIR"
swift build -c release --arch "$ARCH"
BIN_PATH="$(swift build -c release --arch "$ARCH" --show-bin-path)/Minfwm"

echo "==> Assembling $OUT_APP..."
rm -rf "$OUT_APP"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/Minfwm"
chmod +x "$MACOS_DIR/Minfwm"

if [[ -x "$MINFWM_BIN" ]]; then
  echo "==> Embedding minfwm service binary from $MINFWM_BIN..."
  cp "$MINFWM_BIN" "$RESOURCES_DIR/minfwm"
  chmod +x "$RESOURCES_DIR/minfwm"
fi

# Compile .icon bundle into AppIcon.icns if available
ICTOOL="$XCODE_APP/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$ICTOOL" ]]; then
  ICTOOL="$XCODE_APP/Contents/Applications/Icon Composer.app/Contents/Executables/icontool"
fi

if [[ -d "$ICON_SRC" && -x "$ICTOOL" ]]; then
  echo "==> Compiling $ICON_SRC into AppIcon.icns..."
  ICON_WORK="$ROOT_DIR/build/icon_tmp"
  ICONSET_DIR="$ICON_WORK/AppIcon.iconset"
  rm -rf "$ICON_WORK"
  mkdir -p "$ICONSET_DIR"

  MASTER_ART="$ICON_WORK/icon_art_824.png"
  MASTER_1024="$ICON_WORK/icon_1024.png"
  "$ICTOOL" "$ICON_SRC" --export-preview macOS Default 824 824 1 -45 "$MASTER_ART"
  sips --padToHeightWidth 1024 1024 "$MASTER_ART" --out "$MASTER_1024" >/dev/null

  for sz in 16 32 64 128 256 512 1024; do
    sips -z "$sz" "$sz" "$MASTER_1024" --out "$ICONSET_DIR/icon_${sz}x${sz}.png" >/dev/null
    if [[ "$sz" -ne 1024 ]]; then
      dbl=$((sz * 2))
      sips -z "$dbl" "$dbl" "$MASTER_1024" --out "$ICONSET_DIR/icon_${sz}x${sz}@2x.png" >/dev/null
    fi
  done
  cp "$MASTER_1024" "$ICONSET_DIR/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
  rm -rf "$ICON_WORK"
else
  echo "==> Skipping icon compilation (ictool or assets/minfwm.icon not found)"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>minfWM</string>
    <key>CFBundleExecutable</key>
    <string>Minfwm</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.minfwm.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>minfWM</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION#v}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing $OUT_APP with stable identifier requirement..."
codesign --force --deep --sign - -r='designated => identifier "com.minfwm.app"' "$OUT_APP"

echo "==> Done: $OUT_APP"
