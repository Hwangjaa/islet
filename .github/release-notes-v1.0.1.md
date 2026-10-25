## Islet 1.0.1

Rilis ini menyusul 1.0.0 yang tertinggal 6 commit. Semua perbaikan dan fitur di bawah sudah ada
di dalam DMG ini.

### Yang baru & diperbaiki

- **Perbaikan: ikon timer menabrak ikon status.** Layout pill kini satu baris tiga zona (bukan
  ZStack dua lapis), jadi ikon Wi-Fi/Bluetooth/baterai tidak mungkin tertimpa konten kiri.
- **Ikon status kembali ke tengah.** Saat tidak ada timer/media/tangkapan, ikon duduk di tengah
  pill; begitu ada konten, mereka bergeser ke kanan dengan animasi.
- **Timer jadi jam digital interaktif.** Tidak lagi preset 1/5/25 menit: ada digit `HH : MM : SS`
  dengan panah naik/turun, tombol **Mulai**, serta **Jeda/Lanjut** dan **Stop** saat berjalan.
  Jeda benar-benar membekukan sisa waktu.
- **Indikator modul di footer memakai ikon SF Symbols** (musik, kamera, lonceng, audio, baterai,
  kalender, timer) — bukan titik lagi. Ukuran sel dan jarak tetap sama.
- Baterai minimalis: angka persen hanya muncul saat sedang cas atau ≤ 20%.

### Perbaikan stabilitas yang sudah ikut di 1.0.0

AppleScript dipindah ke queue latar (penyebab "not responding"), blok MediaRemote
`@escaping @convention(block)` (penyebab crash saat start), store notifikasi tidak lagi
ObservableObject bersarang (penyebab fault "Publishing changes"), dan HoverMonitor berhisteresis
(penyebab pill membesar-mengecil cepat).

### Pasang

1. Unduh `Islet-1.0.1.dmg`.
2. Buka DMG, tarik **Islet** ke **Applications**.
3. Build ini ad-hoc signed (belum notarized). Kalau macOS menolak membuka:
   `xattr -dr com.apple.quarantine /Applications/Islet.app` atau klik kanan → Open.

sha256: `babf125ad497e1f339d255a279eaffe61a4fc67365a078a11c316c3d224e5565`
Syarat: macOS 14+ (diuji macOS 27.0.1, arm64). Lisensi MIT.
