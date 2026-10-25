# Audit keamanan & jaringan

Lingkup: seluruh kode di repo ini (commit `df0fba4`, 11 berkas Swift, 3 skrip shell) dan biner
`arm64` di `dist/Islet.app` yang dipakai untuk rilis v1.0.0.

Kesimpulan singkat:

- **Tidak ada koneksi internet, sama sekali.** Tidak ada satu pun kerangka jaringan yang ditautkan,
  tidak ada simbol soket di biner, tidak ada URL di dalam biner, dan saat aplikasi berjalan
  (termasuk semua fitur digerakkan) jumlah soket terbuka = **0**.
- **Tidak ada telemetri, analitik, akun, atau pembaruan otomatis.**
- Data yang dibaca hanya dari API sistem lokal (sebagian butuh izin eksplisit darimu), dan
  tidak pernah meninggalkan mesin ini.

## 1. Metode

Empat lapis, semuanya bisa diulang sendiri:

```bash
# a. Pindai sumber untuk API jaringan dan eksekusi proses
grep -rnE "URLSession|URLRequest|NSURLConnection|NWConnection|CFStream|socket\(|connect\(|getaddrinfo|curl|NSTask|Process\(" Sources scripts

# b. Kerangka yang benar-benar ditautkan ke biner
otool -L dist/Islet.app/Contents/MacOS/Islet | awk '{print $1}' | sort

# c. Simbol jaringan dan URL yang tertanam di biner
nm -u dist/Islet.app/Contents/MacOS/Islet | grep -iE "socket|connect|getaddrinfo|CFNetwork|nw_|URLSession"
strings -a dist/Islet.app/Contents/MacOS/Islet | grep -oE "https?://[a-zA-Z0-9./_-]+"

# d. Soket saat aplikasi hidup
open dist/Islet.app && PID=$(pgrep -f "Islet.app/Contents/MacOS/Islet")
lsof -p "$PID" -a -i          # koneksi inet (harus kosong)
lsof -p "$PID" -a -i -P -n    # semua soket (harus kosong)
lsof -p "$PID" -a -iTCP -sTCP:LISTEN   # port mendengarkan (harus kosong)
```

## 2. Hasil

| Pemeriksaan | Hasil |
|---|---|
| Kerangka jaringan (`Network`, `CFNetwork`, `WebKit`) | tidak ada di `otool -L` |
| `URLSession`, `URLRequest`, `socket()`, `connect()`, `getaddrinfo` | tidak ada di sumber |
| Simbol jaringan di biner | tidak ada |
| URL/host di dalam biner | tidak ada |
| Soket terbuka saat 6 sampel / 12 detik idle | **0** |
| Soket saat semua fitur digerakkan (7× ganti modul, notifikasi, aktivitas, shelf, hoverSim) | **0** |
| Port mendengarkan | **0** |
| `NSTask` / `Process` / `system()` / shell | tidak ada |
| Kunci privat, token, Keychain, `~/.ssh` | tidak disentuh |

## 3. Yang memang menghubungi sesuatu — semuanya lokal

| Mekanisme | Ke mana | Data yang lewat | Izin |
|---|---|---|---|
| `dlopen` MediaRemote (`/System/Library/PrivateFrameworks/MediaRemote.framework`) | framework sistem, via XPC | judul/artis media yang sedang diputar | tidak perlu |
| `NSAppleScript` ke Music/Spotify (cadangan) | app lokal | perintah putar/jeda, judul trek | Automation |
| EventKit | daemon kalender lokal | acara hari ini | Kalender |
| CoreWLAN / CoreBluetooth | daemon sistem | status nyala/mati Wi-Fi & Bluetooth | tidak perlu |
| IOKit.ps | kernel | persentase baterai, status cas | tidak perlu |
| CoreAudio | daemon audio lokal | daftar perangkat keluaran, volume | tidak perlu |
| `NSWorkspace.open` | membuka Calendar.app / System Settings | hanya saat kamu klik | — |

Tidak satu pun dari daftar di atas memakai jaringan. MediaRemote, EventKit, CoreAudio, dan CoreWLAN
berkomunikasi lewat XPC ke daemon di mesin yang sama.

## 4. Data pribadi yang disentuh

| Data | Kapan | Disimpan di mana | Bisa keluar? |
|---|---|---|---|
| Isi clipboard | dipantau tiap 0,7 detik; hanya gambar/berkas gambar yang dipakai | `~/Library/Application Support/Islet/Shelf/*.png` | tidak — tidak ada kode jaringan |
| Teks notifikasi Notification Center | hanya jika kamu mengaktifkan cermin | memori saja (`items`, `recentKeys` dipangkas 30 detik) | tidak |
| Judul acara kalender | modul Kalender aktif | memori saja | tidak |
| Judul/artis media | saat ada media diputar | memori saja | tidak |

## 5. Permukaan serangan lokal (jujur, ini ada)

Ketiganya **lokal** — hanya proses di sesi macOS kamu yang bisa memakainya, dan tidak satu pun
membuka jalan keluar jaringan.

1. **Kanal debug `com.rafael.islet.debug`** (DistributedNotificationCenter). Proses lokal mana pun
   bisa mengirim perintah: `expand`, `collapse`, `next`, `notify`, `shelfInject`, `notifClear`,
   `activity`, `hudVolume`, `snapshot`, `hoverSim`. Dampak: mengubah tampilan atau menyuntik
   notifikasi palsu. Tidak bisa membaca berkas atau data pribadi. Mitigasi yang disarankan:
   aktifkan hanya saat dijalankan dengan flag `--debug`.
2. **Skema URL `islet://notify?...`.** Aplikasi lain atau halaman web bisa memicu
   `open "islet://notify?title=..."` sehingga muncul notifikasi palsu di island. Dampak: spoofing
   tampilan, tanpa akses data. Mitigasi: hapus skema URL, atau minta konfirmasi.
3. **`/tmp/islet-hover.log`.** Ditulis `Debug.trace` (dipakai `hoverSim`), berisi koordinat kursor
   dan zona geometri. Berkas di `/tmp` bisa dibaca pengguna lain di mesin yang sama. Mitigasi:
   pindah ke folder Application Support dengan izin `0600`, atau hapus setelah build stabil.

## 6. Batasan audit ini

- Audit statis + dinamis pada satu mesin (macOS 27.0.1, arm64). Tidak ada pengujian fuzzing atau
  analisis biner mendalam (dekompilasi).
- MediaRemote adalah kerangka privat; perilakunya bisa berubah antar versi macOS. Aplikasi
  menangani ketiadaan simbol dengan jatuh ke AppleScript, tidak crash.
- Biner rilis belum dinotarized Apple (ad-hoc signed), jadi macOS meminta konfirmasi saat pertama
  dibuka. Itu soal distribusi, bukan keamanan data.
