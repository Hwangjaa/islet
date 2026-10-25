#!/bin/bash
# Build Islet dan rakit menjadi .app bundle lokal (ad-hoc signed).
# Versi diambil dari git tag terdekat (v1.2.3 → 1.2.3); bisa dioverride lewat env VERSION.
# Pemakaian: ./scripts/make_app.sh [debug|release]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Islet.app"
CONF="${1:-release}"

VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD="${BUILD:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"

cd "$ROOT"
echo "== swift build -c $CONF =="
swift build -c "$CONF"

BIN="$ROOT/.build/$CONF/Islet"
[ -x "$BIN" ] || { echo "binary tidak ditemukan: $BIN"; exit 1; }

echo "== merakit bundle (versi $VERSION, build $BUILD) =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Islet"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>Islet</string>
    <key>CFBundleIdentifier</key><string>com.rafael.islet</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Islet</string>
    <key>CFBundleDisplayName</key><string>Islet</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>com.rafael.islet</string>
            <key>CFBundleURLSchemes</key><array><string>islet</string></array>
        </dict>
    </array>
    <key>NSAppleEventsUsageDescription</key>
    <string>Islet perlu izin untuk mengendalikan dan menampilkan musik yang sedang diputar.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Islet perlu izin kalender untuk menampilkan agenda berikutnya.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Islet perlu izin Bluetooth untuk mengenali perangkat audio yang terhubung.</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist"

# Ikon aplikasi: dari assets/logo-islet.png (kalau ada) → AppIcon.icns
ICON_SRC="$ROOT/assets/logo-islet.png"
if [ -f "$ICON_SRC" ]; then
  echo "== membuat AppIcon.icns dari assets/logo-islet.png =="
  ICONSET="$ROOT/dist/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for size in 16 32 64 128 256 512; do
    sips -z $size $size "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
  done
  # varian @2x untuk ukuran titik (pt) yang sesuai
  cp "$ICONSET/icon_32x32.png"   "$ICONSET/icon_16x16@2x.png"   2>/dev/null || true
  cp "$ICONSET/icon_64x64.png"   "$ICONSET/icon_32x32@2x.png"   2>/dev/null || true
  cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png" 2>/dev/null || true
  cp "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png" 2>/dev/null || true
  sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null 2>&1
  rm -f "$ICONSET/icon_64x64.png"
  if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP/Contents/Info.plist"
    echo "   ikon terpasang: $(du -h "$APP/Contents/Resources/AppIcon.icns" | awk '{print $1}')"
  else
    echo "   PERINGATAN: iconutil gagal, bundel tanpa ikon"
  fi
  rm -rf "$ICONSET"
else
  echo "== tanpa ikon (assets/logo-islet.png tidak ada) =="
fi

echo "== menandatangani (ad-hoc) =="
codesign --force --deep --sign - "$APP" 2>&1 | tail -3
codesign -dv "$APP" 2>&1 | head -4

echo "== hasil =="
ls -la "$APP/Contents/MacOS/"
echo "$APP"
