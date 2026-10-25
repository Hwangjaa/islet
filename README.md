# Islet

Dynamic island untuk notch MacBook, ditulis dengan Swift + SwiftUI, tanpa dependensi pihak ketiga.
Implementasi mandiri: tidak memakai kode, aset, atau sistem lisensi aplikasi lain.

![status](https://img.shields.io/badge/platform-macOS%2014%2B-black) ![swift](https://img.shields.io/badge/swift-5.9-orange)

## Fitur

| Modul | Isi |
|---|---|
| **Sedang diputar** | Judul/artis + kontrol putar, jeda, maju, mundur. Sumber: Now Playing sistem (termasuk browser) lewat MediaRemote, cadangan AppleScript untuk Music/Spotify |
| **Volume** | Slider volume, pemilih perangkat keluaran, indikator perangkat aktif |
| **Baterai** | Persentase, status cas, HUD saat adaptor dicabut/disambung, peringatan baterai lemah |
| **Kalender** | Acara berikutnya + waktu mulai relatif |
| **Aktivitas** | Timer hitung mundur dengan progres melingkar |
| **Tangkapan** | Tangkapan layar yang masuk clipboard otomatis tersimpan; bisa di-drag keluar sebagai berkas |
| **Notifikasi** | Pill ringkas di island, cermin Notification Center (opsional, butuh izin Accessibility) |
| **Notch** | Indikator Wi-Fi dan Bluetooth (glyph digambar sendiri, dicoret saat mati) |

Interaksi: hover untuk melebar, klik dua kali untuk mengunci, geser trackpad untuk ganti modul,
tombol `<` `>` di footer.

## Syarat

- macOS 14 atau lebih baru (diuji di macOS 27.0.1, MacBook Air M5 15")
- Swift 5.9+ / toolchain SwiftPM (diuji dengan Swift 6.4, language mode 5)

## Build & jalankan

```bash
git clone <url-repo-ini> islet && cd islet
swift build                       # build debug
.build/debug/Islet --selftest     # 47 pemeriksaan mandiri, tanpa GUI
./scripts/make_app.sh release     # rakit bundel .app (ad-hoc signed)
open dist/Islet.app
```

`make_app.sh` menghasilkan `dist/Islet.app` dengan bundle id `com.rafael.islet`. Untuk build
sendiri, ganti `CFBundleIdentifier` di skrip bila perlu.

## Izin macOS

| Izin | Kapan diminta | Wajib? |
|---|---|---|
| Automation (AppleScript ke Music/Spotify) | Saat fallback Now Playing dipakai | Tidak — hanya bila MediaRemote tidak tersedia |
| Accessibility | Saat cermin Notification Center diaktifkan | Tidak — fitur lain jalan tanpa izin |
| Kalender | Saat modul Kalender dimuat | Tidak — modul menampilkan status izin |

Cermin notifikasi: jalankan `./scripts/islet-enable-mirror.sh`. Skrip membuka panel
Privacy & Security → Accessibility, menyalin path `Islet.app` ke clipboard, dan menampilkan
`Islet.app` di Finder. macOS tidak mengizinkan aplikasi menambahkan dirinya sendiri ke daftar itu
(TCC dilindungi SIP), jadi langkah terakhir tetap drag/`⇧⌘G` oleh pengguna. Setelah toggle aktif,
buka ulang aplikasi — izin Accessibility hanya berlaku untuk proses baru.

## Kanal debug

Untuk pengujian tanpa menyentuh mouse:

```bash
echo "expand"   # perintah: expand | collapse | next | previous | togglePin
               #           activity | activityStop | hudVolume | hudBattery
               #           shelfInject | shelfClear | notifClear | snapshot | gestureBurst | hoverSim
```

Dikirim lewat `DistributedNotificationCenter` bernama `com.rafael.islet.debug`
(`scripts/islet-notify` untuk mengirim notifikasi contoh).

## Struktur

```
Sources/Islet/
  main.swift            masuk aplikasi
  AppDelegate.swift     panel, status item, kanal debug, HoverMonitor
  IslandModel.swift     state, pengaturan, geometri notch, animasi
  Views.swift           tampilan island, modul, pengaturan
  Monitors.swift        volume, baterai, media, kalender, konektivitas
  MediaRemoteEngine.swift  Now Playing sistem (MediaRemote, dimuat dinamis)
  Notifications.swift   penyimpanan notifikasi + cermin Notification Center
  Shelf.swift           tangkapan clipboard → berkas
  SelfTest.swift        --selftest
scripts/
  make_app.sh           rakit bundel .app
  islet-notify          kirim notifikasi contoh
  islet-enable-mirror.sh  bantuan izin cermin notifikasi
```

## Catatan teknis

- **MediaRemote** dimuat dengan `dlopen`, bukan API publik. Ini satu-satunya cara membaca
  Now Playing aplikasi lain (termasuk browser). Kalau simbol tidak tersedia di versi macOS
  tertentu, aplikasi otomatis jatuh ke AppleScript dan tidak crash.
- **Hover** tidak memakai `onHover` SwiftUI: jendela yang berubah ukuran me-reset tracking area
  dan memicu osilasi buka-tutup. `HoverMonitor` membaca posisi kursor 25×/detik dengan dua zona
  berhisteresis (`stayZone` selalu memuat `enterZone`) dan cooldown 0,35 s.
- **Animasi** jendela memakai `NSAnimationContext` dengan kurva `(0.22, 1, 0.36, 1)` 0,30 s;
  animasi konten memakai tiga konstanta di `IslandAnim`.
- **AppleScript** dijalankan di queue latar; menjalankannya di main thread bisa membuat aplikasi
  terlihat "not responding" saat macOS menampilkan dialog izin.

## Lisensi

Belum ditentukan — tambahkan berkas `LICENSE` sebelum dipublikasikan.
