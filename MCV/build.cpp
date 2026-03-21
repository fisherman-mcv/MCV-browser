#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT_DIR/main.swift"
HELPER_SRC="$ROOT_DIR/helper.cpp"
ICON_SRC="$ROOT_DIR/logos/logo.png"
APP_NAME="MCV"
BIN_NAME="$APP_NAME"
HELPER_BIN_NAME="mcv_command_helper"
APP_DIR="$ROOT_DIR/$APP_NAME.app"
BIN_PATH="$ROOT_DIR/$BIN_NAME"
HELPER_BIN_PATH="$ROOT_DIR/$HELPER_BIN_NAME"
APP_BIN_PATH="$APP_DIR/Contents/MacOS/$APP_NAME"
APP_HELPER_PATH="$APP_DIR/Contents/MacOS/$HELPER_BIN_NAME"
BUNDLE_ID="com.local.mcv"
ICON_ICNS="$APP_DIR/Contents/Resources/AppIcon.icns"

MODE="${MCV_BUILD_MODE:-dev}"
FORCE_REBUILD="${MCV_FORCE_REBUILD:-0}"

if [[ "$MODE" == "release" ]]; then
  DEFAULT_CODESIGN=1
  DEFAULT_REGISTER=1
  DEFAULT_STRIP=1
else
  DEFAULT_CODESIGN=0
  DEFAULT_REGISTER=0
  DEFAULT_STRIP=0
fi

CODESIGN_ENABLED="${MCV_CODESIGN:-$DEFAULT_CODESIGN}"
REGISTER_APP="${MCV_REGISTER_APP:-$DEFAULT_REGISTER}"
STRIP_BINARIES="${MCV_STRIP:-$DEFAULT_STRIP}"

needs_rebuild() {
  local target="$1"
  shift
  if [[ "$FORCE_REBUILD" == "1" ]]; then
    return 0
  fi
  if [[ ! -f "$target" ]]; then
    return 0
  fi
  local source
  for source in "$@"; do
    if [[ "$source" -nt "$target" ]]; then
      return 0
    fi
  done
  return 1
}

if [[ ! -f "$SRC" ]]; then
  echo "Source not found: $SRC" >&2
  exit 1
fi

if [[ ! -f "$HELPER_SRC" ]]; then
  echo "Helper source not found: $HELPER_SRC" >&2
  exit 1
fi

if [[ ! -f "$ICON_SRC" ]]; then
  echo "Icon source not found: $ICON_SRC" >&2
  exit 1
fi

if [[ "$MODE" == "release" ]]; then
  SWIFT_FLAGS=(
    -parse-as-library
    -Osize
    -whole-module-optimization
    -gnone
    -Xlinker -dead_strip
  )
  HELPER_FLAGS=(-std=c++17 -O2 -DNDEBUG)
else
  SWIFT_FLAGS=(
    -parse-as-library
    -Onone
    -gnone
    -suppress-warnings
  )
  HELPER_FLAGS=(-std=c++17 -O0)
fi

if needs_rebuild "$BIN_PATH" "$SRC"; then
  xcrun swiftc "${SWIFT_FLAGS[@]}" "$SRC" -o "$BIN_PATH"
  if [[ "$STRIP_BINARIES" == "1" ]]; then
    strip -x "$BIN_PATH"
  fi
else
  echo "swift binary up to date: $BIN_PATH"
fi

if needs_rebuild "$HELPER_BIN_PATH" "$HELPER_SRC"; then
  xcrun clang++ "${HELPER_FLAGS[@]}" "$HELPER_SRC" -o "$HELPER_BIN_PATH"
  if [[ "$STRIP_BINARIES" == "1" ]]; then
    strip -x "$HELPER_BIN_PATH"
  fi
else
  echo "helper binary up to date: $HELPER_BIN_PATH"
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

if needs_rebuild "$ICON_ICNS" "$ICON_SRC"; then
  ICONSET_ROOT="$(mktemp -d)"
  ICONSET_DIR="$ICONSET_ROOT/AppIcon.iconset"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16 "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
  rm -rf "$ICONSET_ROOT"
else
  echo "app icon up to date: $ICON_ICNS"
fi

cp "$BIN_PATH" "$APP_BIN_PATH"
cp "$HELPER_BIN_PATH" "$APP_HELPER_PATH"
chmod +x "$APP_HELPER_PATH"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSHandlerRank</key>
      <string>Owner</string>
      <key>CFBundleURLName</key>
      <string>Web URL</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>http</string>
        <string>https</string>
      </array>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>HTML document</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Owner</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.html</string>
      </array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key>
      <string>XHTML document</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Owner</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.xhtml</string>
      </array>
    </dict>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "APPL????" > "$APP_DIR/Contents/PkgInfo"

if [[ "$CODESIGN_ENABLED" == "1" ]]; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ "$REGISTER_APP" == "1" && -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi

BINARY_SIZE="$(stat -f '%z' "$BIN_PATH")"
HELPER_SIZE="$(stat -f '%z' "$HELPER_BIN_PATH")"
APP_BINARY_SIZE="$(stat -f '%z' "$APP_BIN_PATH")"
APP_HELPER_SIZE="$(stat -f '%z' "$APP_HELPER_PATH")"

echo "Built binary: $BIN_PATH ($BINARY_SIZE bytes)"
echo "Built helper: $HELPER_BIN_PATH ($HELPER_SIZE bytes)"
echo "Built app: $APP_DIR"
echo "App executable: $APP_BIN_PATH ($APP_BINARY_SIZE bytes)"
echo "App helper: $APP_HELPER_PATH ($APP_HELPER_SIZE bytes)"
echo "App icon: $ICON_ICNS"
echo "Build mode: $MODE"
echo "Codesign: $CODESIGN_ENABLED"
echo "LS register: $REGISTER_APP"
