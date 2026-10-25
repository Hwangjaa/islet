## Islet 1.0.0

Dynamic island untuk notch MacBook. Rilis pertama: satu DMG, aplikasi siap dipakai tanpa build.

### Pasang

1. Unduh `Islet-1.0.0.dmg` di bawah.
2. Buka DMG, tarik **Islet** ke **Applications**.
3. Jalankan dari Applications.

Build ini ad-hoc signed (belum notarized Apple). Kalau macOS menolak membuka dengan pesan
"developer cannot be verified", pilih salah satu:

```bash
xattr -dr com.apple.quarantine /Applications/Islet.app
```

atau klik kanan `Islet.app` → **Open** → **Open** lagi.

### Isi rilis ini

- **Media** — judul/artis + putar, jeda, maju, mundur; sumber Now Playing sistem (termasuk browser), cadangan AppleScript untuk Music/Spotify
- **Volume** — slider, pemilih perangkat keluaran, indikator perangkat aktif
- **Baterai** — persentase, status cas, HUD saat adaptor dicabut/disambung, peringatan baterai lemah
- **Kalender** — acara berikutnya + waktu relatif
- **Aktivitas** — timer hitung mundur
- **Tangkapan** — tangkapan layar dari clipboard tersimpan otomatis, bisa di-drag keluar
- **Notifikasi** — pill ringkas di island, cermin Notification Center opsional
- **Notch** — indikator Wi-Fi/Bluetooth (glyph digambar sendiri, dicoret saat mati)

Interaksi: hover untuk melebar, klik dua kali untuk mengunci, geser trackpad untuk ganti modul,
tombol `<` `>` di footer.

### Syarat

- macOS 14 atau lebih baru (diuji di macOS 27.0.1, MacBook Air M5 15")
- Izin opsional: Automation (AppleScript media), Accessibility (cermin notifikasi), Kalender

### Catatan

- Binary: `arm64` (Apple Silicon). Versi Intel belum disediakan.
- sha256: `4699e1cf381a9901740d7937d26097aee014a97af5f94bb4df108b71967707fe`
- Lisensi: MIT (lihat `LICENSE` di repo).
