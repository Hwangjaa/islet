#!/bin/bash
# islet-enable-mirror — bantu mengizinkan cermin notifikasi macOS untuk Islet.
#
# Yang dilakukan (macOS tidak mengizinkan penambahan otomatis ke daftar Accessibility —
# TCC dilindungi sistem, jadi langkah akhir tetap klik/drag oleh pengguna):
#   1. Menyalin path Islet.app ke clipboard.
#   2. Membuka Finder dengan Islet.app terpilih (untuk di-drag ke daftar).
#   3. Membuka panel System Settings → Privacy & Security → Accessibility.
#   4. Menampilkan instruksi langkah demi langkah.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
APP="${1:-$REPO_DIR/dist/Islet.app}"

if [ ! -d "$APP" ]; then
  echo "Islet.app tidak ditemukan di $APP"
  echo "Rakit dulu: cd $(dirname "$APP")/.. && ./scripts/make_app.sh"
  exit 1
fi

printf '%s' "$APP" | pbcopy
echo "1) Path disalin ke clipboard: $APP"

open -R "$APP" || true
echo "2) Finder dibuka dengan Islet.app terpilih"

open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility" 2>/dev/null \
  || open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null \
  || echo "   (buka manual: System Settings → Privacy & Security → Accessibility)"
echo "3) Panel Accessibility dibuka"

cat <<'TXT'

Langkah di layar:
  a. Di daftar Accessibility, klik tombol  +  (atau drag Islet.app dari Finder ke daftar).
  b. Tekan ⇧⌘G di dialog pemilihan file, paste path dari clipboard (⌘V), lalu pilih Islet.app.
  c. Pastikan toggle Islet.app  ON.
  d. Keluar dari Islet lalu buka lagi — izin Accessibility hanya berlaku untuk proses baru.
  e. Di island: modul Notifikasi → "Cek ulang" (atau jalankan ulang skrip ini).

Catatan: setelah izin diberikan, cermin hanya membaca banner Notification Center.
Kalau struktur UI Notification Center berubah di versi macOS berikutnya, cermin bisa berhenti;
aplikasi tidak crash, hanya melaporkan status.
TXT
