#!/bin/bash
# Rakit .dmg siap unduh untuk GitHub Releases.
# Pemakaian: ./scripts/make_dmg.sh [versi]
# Hasil: dist/Islet-<versi>.dmg  (berisi Islet.app + symlink /Applications)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-${VERSION:-$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}}"
VERSION="${VERSION:-0.0.0-dev}"

STAGE="$ROOT/dist/dmg-stage"
DMG="$ROOT/dist/Islet-$VERSION.dmg"

echo "== rakit bundel versi $VERSION =="
VERSION="$VERSION" "$ROOT/scripts/make_app.sh" release >/dev/null

echo "== siapkan isi dmg =="
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$ROOT/dist/Islet.app" "$STAGE/Islet.app"
ln -s /Applications "$STAGE/Applications"

echo "== buat dmg (UDZO, terkompresi) =="
hdiutil create -volname "Islet $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "== verifikasi dmg (mount read-only) =="
MOUNT="$ROOT/dist/.mnt"
rm -rf "$MOUNT"; mkdir -p "$MOUNT"
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT" >/dev/null
ls -1 "$MOUNT"
APP_IN_DMG="$MOUNT/Islet.app"
if [ -d "$APP_IN_DMG" ]; then
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_IN_DMG/Contents/Info.plist" 2>/dev/null \
    | sed 's/^/  versi di dalam dmg: /'
  codesign -dv "$APP_IN_DMG" 2>&1 | grep -E "Identifier|Signature" | sed 's/^/  /'
else
  echo "  Islet.app TIDAK ada di dalam dmg"; hdiutil detach "$MOUNT" >/dev/null; exit 1
fi
hdiutil detach "$MOUNT" >/dev/null
rmdir "$MOUNT" 2>/dev/null || true

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
SIZE=$(du -h "$DMG" | awk '{print $1}')
echo
echo "== hasil =="
echo "  berkas : $DMG"
echo "  ukuran : $SIZE"
echo "  sha256 : $SHA"
