import AppKit
import CoreWLAN
import Foundation
import SwiftUI

// Pengujian otomatis tanpa antarmuka: dijalankan dengan `Islet --selftest`.
// Mengembalikan jumlah kegagalan sebagai exit code.

enum SelfTest {

    private static var failures = 0
    private static var checks = 0

    private static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        checks += 1
        if condition {
            print("PASS  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
        } else {
            failures += 1
            print("FAIL  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
        }
    }

    static func run() -> Int32 {
        print("Islet selftest — \(Date())")
        let settings = IslandSettings()

        // 1. Geometri pada layar nyata
        if let screen = IslandGeometry.targetScreen {
            let notch = screen.notchWidth
            let inset = IslandGeometry.topInset(screen: screen, settings: settings)
            let collapsed = IslandGeometry.size(for: .collapsed, settings: settings)
            let expanded = IslandGeometry.size(for: .expanded, settings: settings)
            let frame = IslandGeometry.frame(for: .collapsed, settings: settings)

            if IslandGeometry.hasRealNotch(screen: screen, settings: settings) {
                let expected = (notch + IslandGeometry.earWidth * 2 + CGFloat(settings.extraWidth)).rounded()
                check("collapsed width = notch + 2 telinga + tambahan",
                      abs(collapsed.width - expected) < 0.51,
                      "notch=\(notch) width=\(collapsed.width) expected=\(expected)")
                check("collapsed height = notch + konten",
                      abs(collapsed.height - (inset + IslandGeometry.collapsedContentHeight).rounded()) < 0.51,
                      "inset=\(inset) height=\(collapsed.height)")
            } else {
                check("collapsed width tanpa notch mengambang",
                      abs(collapsed.width - (150 + CGFloat(settings.extraWidth))) < 0.51,
                      "width=\(collapsed.width)")
                check("collapsed height mengambang = celah + konten",
                      abs(collapsed.height - (IslandGeometry.floatingGap + IslandGeometry.collapsedContentHeight)) < 0.51,
                      "height=\(collapsed.height)")
            }
            check("expanded lebih lebar & lebih tinggi dari collapsed",
                  expanded.width > collapsed.width && expanded.height > collapsed.height,
                  "collapsed=\(collapsed) expanded=\(expanded)")
            check("panel terpusat horizontal",
                  abs(frame.midX - screen.frame.midX) < 0.51,
                  "panelMid=\(frame.midX) screenMid=\(screen.frame.midX)")
            check("panel menempel tepi atas layar",
                  abs(frame.maxY - screen.frame.maxY) < 0.51,
                  "panelTop=\(frame.maxY) screenTop=\(screen.frame.maxY)")
            check("panel tidak melewati lebar layar", frame.width <= screen.frame.width,
                  "panel=\(frame.width) layar=\(screen.frame.width)")
        } else {
            check("layar terdeteksi", false, "NSScreen tidak tersedia di proses ini")
        }

        // 2. Pergantian modul
        let state = IslandState()
        let modules = state.availableModules
        check("daftar modul tidak kosong", !modules.isEmpty, "\(modules.map { $0.rawValue })")
        var cursor = modules[0]
        var visited: [IslandModule] = [cursor]
        for _ in 0..<(modules.count - 1) {
            cursor = state.nextModule(from: cursor)
            visited.append(cursor)
        }
        check("nextModule mengunjungi semua modul tanpa duplikat",
              Set(visited) == Set(modules) && visited.count == modules.count,
              "\(visited.map { $0.rawValue })")
        check("nextModule kembali ke modul pertama setelah satu putaran",
              state.nextModule(from: cursor) == modules[0],
              "\(state.nextModule(from: cursor).rawValue)")
        check("previousModule adalah kebalikan nextModule",
              state.previousModule(from: modules[0]) == modules[modules.count - 1],
              "\(state.previousModule(from: modules[0]).rawValue)")

        // 3. HUD muncul lalu hilang sendiri
        state.showHUD(.volume, value: 0.42)
        check("HUD aktif setelah showHUD", state.hud != nil)
        RunLoop.current.run(until: Date().addingTimeInterval(1.8))
        check("HUD hilang otomatis setelah ~1,5 s", state.hud == nil)

        // 4. Baterai terbaca di mesin ini
        if let battery = BatteryMonitor.snapshot() {
            check("baterai terdeteksi", battery.available,
                  "\(battery.percent)% charging=\(battery.charging) ac=\(battery.onAC)")
            check("persentase baterai masuk akal", (0...100).contains(battery.percent), "\(battery.percent)")
            check("charging dan onAC tidak bertentangan", !(battery.charging && !battery.onAC),
                  "charging=\(battery.charging) onAC=\(battery.onAC)")
        } else {
            check("baterai terdeteksi", false, "BatteryMonitor.snapshot() nil (mungkin desktop)")
        }

        // 5. Volume sistem terbaca
        let device = VolumeMonitor.defaultOutputDevice()
        check("perangkat keluaran default terdeteksi", device != 0, "deviceID=\(device)")
        if device != 0 {
            check("nama perangkat terbaca", VolumeMonitor.deviceName(device) != nil,
                  VolumeMonitor.deviceName(device) ?? "-")
            if let reading = VolumeMonitor.currentOutputVolume() {
                check("level volume dalam 0...1", reading.level >= 0 && reading.level <= 1,
                      "level=\(reading.level) muted=\(reading.muted)")
            } else {
                print("SKIP  level volume tidak terbaca pada perangkat ini (bukan kegagalan)")
            }
        }

        // 6. Preferensi
        let stored = UserDefaults.standard.integer(forKey: "settingsVersion")
        check("versi setelan tersimpan (migrasi lebar default)", stored >= 2, "settingsVersion=\(stored)")
        check("extraWidth tersimpan sebagai angka", UserDefaults.standard.object(forKey: "extraWidth") != nil,
              "\(settings.extraWidth)")

        // 7. Teks status daya (dipakai HUD sejenak)
        check("caption saat mengisi daya", HUDKind.charging.caption == "Mengisi daya", HUDKind.charging.caption)
        check("caption saat adaptor tersambung tanpa mengisi", HUDKind.onAC.caption == "Tersambung adaptor", HUDKind.onAC.caption)
        check("caption saat adaptor dilepas", HUDKind.battery.caption == "Ga lagi ngecas cok", HUDKind.battery.caption)
        check("volume dan mute bukan keluarga baterai",
              !HUDKind.volume.isBatteryFamily && !HUDKind.mute.isBatteryFamily)

        // 8. Shelf tangkapan layar — memakai pasteboard terpisah supaya clipboard pengguna tidak tersentuh.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("islet-selftest-shelf", isDirectory: true)
        try? FileManager.default.removeItem(at: tmp)
        let board = NSPasteboard(name: NSPasteboard.Name("com.rafael.islet.selftest"))
        board.clearContents()
        let shelf = ScreenshotShelf(pasteboard: board, directory: tmp)
        let canvas = NSSize(width: 320, height: 200)
        let testImage = NSImage(size: canvas)
        testImage.lockFocus()
        NSColor.systemPink.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()
        testImage.unlockFocus()

        if let tiff = testImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            board.clearContents()
            board.setData(png, forType: .png)
            let first = shelf.ingest(from: board)
            check("shelf menyimpan gambar dari clipboard", first != nil,
                  first?.url.lastPathComponent ?? "tidak tersimpan")
            check("berkas shelf ada di disk",
                  first.map { FileManager.default.fileExists(atPath: $0.url.path) } ?? false)
            check("ukuran piksel tercatat benar",
                  first.map { Int($0.pixelSize.width) == rep.pixelsWide } ?? false,
                  first.map { "\(Int($0.pixelSize.width))×\(Int($0.pixelSize.height))" } ?? "-")
            let again = shelf.ingest(from: board)
            check("gambar identik tidak digandakan", again == nil && shelf.items.count == 1,
                  "items=\(shelf.items.count)")
            if let url = first?.url {
                let provider = NSItemProvider(object: url as NSURL)
                check("provider drag siap untuk berkas", provider.canLoadObject(ofClass: NSURL.self),
                      provider.registeredTypeIdentifiers.joined(separator: ","))
            }
            shelf.clearAll()
            check("bersihkan shelf menghapus berkas", shelf.items.isEmpty)
        } else {
            check("membuat PNG uji", false, "NSBitmapImageRep gagal")
        }

        // 9. Tombol navigasi: posisinya tetap di ujung kanan, berdampingan.
        let origins = IslandLayout.stepButtonOrigins(settings: settings)
        let expandedWidth = IslandLayout.expandedWidth(settings: settings)
        check("tombol 'next' menempel di ujung kanan panel",
              abs(origins.next + IslandLayout.stepButtonSize.width
                  - (expandedWidth - IslandLayout.horizontalPadding)) < 0.01,
              "x_next=\(origins.next) lebar panel=\(expandedWidth)")
        check("tombol 'previous' tepat di sebelah kiri 'next'",
              abs(origins.next - (origins.previous + IslandLayout.stepButtonSize.width)) < 0.01,
              "x_prev=\(origins.previous) x_next=\(origins.next)")
        check("lebar area klik tombol navigasi minimal 28×20 pt",
              IslandLayout.stepButtonSize.width >= 28 && IslandLayout.stepButtonSize.height >= 20,
              "\(IslandLayout.stepButtonSize.width)×\(IslandLayout.stepButtonSize.height)")

        // 10. Gerbang gestur: satu gestur = satu aksi (bug "sekali geser pindah 2 fitur").
        var gate = GestureGate()
        let t0 = Date()
        check("aksi pertama pada gestur baru diizinkan", gate.registerAction(at: t0))
        check("event susulan 0,05 s kemudian ditolak",
              !gate.registerAction(at: t0.addingTimeInterval(0.05)))
        check("event susulan 0,30 s kemudian masih ditolak",
              !gate.registerAction(at: t0.addingTimeInterval(0.30)))
        check("aksi berikutnya diizinkan setelah kunci habis (0,8 s)",
              gate.registerAction(at: t0.addingTimeInterval(0.80)))
        gate.release()
        check("release() membuka kunci lebih awal saat gestur berakhir",
              gate.registerAction(at: t0.addingTimeInterval(0.85)))

        // 11. Store notifikasi island
        let notifStore = IslandNotificationStore()
        notifStore.autoDismiss = 999
        let first = notifStore.post(source: "Uji", title: "Halo", body: "isi", symbol: "bell.fill")
        check("notifikasi tercatat dan aktif", first != nil && notifStore.active?.title == "Halo",
              notifStore.active?.title ?? "-")
        check("notifikasi identik dalam 3 detik ditolak",
              notifStore.post(source: "Uji", title: "Halo", body: "isi", symbol: "bell.fill") == nil)
        for index in 0..<20 {
            _ = notifStore.post(source: "Uji", title: "n\(index)", body: "", symbol: "bell.fill")
        }
        check("daftar notifikasi dibatasi 12", notifStore.items.count == 12,
              "items=\(notifStore.items.count)")
        notifStore.dismissActive()
        check("dismissActive melepas pill aktif", notifStore.active == nil)
        notifStore.clear()
        check("clear mengosongkan daftar notifikasi", notifStore.items.isEmpty)

        // 12. Perangkat keluaran, MediaRemote, dan Wi-Fi
        let devices = VolumeMonitor.outputDeviceList()
        check("daftar perangkat keluaran terbaca", !devices.isEmpty, "\(devices.count) perangkat")
        check("ada tepat satu perangkat default", devices.filter { $0.isDefault }.count == 1,
              devices.first(where: { $0.isDefault })?.name ?? "-")
        check("mesin MediaRemote termuat (untuk playback browser)", MediaRemoteEngine.shared.available)
        let wifi = CWWiFiClient.shared().interface()?.powerOn()
        check("status Wi-Fi terbaca", wifi != nil, wifi.map { "powerOn=\($0)" } ?? "nil")

        // 13. Anggaran lebar pill: timer + klaster status tidak boleh bertabrakan
        let collapsedSize = IslandGeometry.size(for: .collapsed, settings: settings)
        let timerFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        let timerText = ("88:88" as NSString).size(withAttributes: [.font: timerFont]).width
        let timerWidth = 9 + 5 + timerText + 5 + 18            // ikon + jeda + teks + jeda + bar
        let statusIconOnly = 12 + 4 + 9 + 4 + 9.5              // Wi-Fi + Bluetooth + ikon baterai
        let statusWithPercent = statusIconOnly + 3 + 22        // + "100%" saat cas
        let needed = timerWidth + 6 + max(statusWithPercent, statusIconOnly) + 4
        check("timer + status muat dalam pill (tanpa menabrak)",
              needed <= collapsedSize.width,
              "butuh \(Int(needed)) dari \(Int(collapsedSize.width)) pt")
        check("klaster status menyisakan ruang untuk konten kiri",
              collapsedSize.width - statusWithPercent - 6 >= timerWidth,
              "sisa \(Int(collapsedSize.width - statusWithPercent - 6)) vs timer \(Int(timerWidth)) pt")

        // 13. Jam digital: draft timer dan aturan posisi klaster ikon
        var draft = TimerDraft()
        draft.hours = 1; draft.minutes = 30; draft.seconds = 15
        check("draft timer menghitung total detik", draft.totalSeconds == 5415,
              "\(draft.totalSeconds) detik")
        draft.bump(.minutes, by: 40)
        check("menit membungkus di 60", draft.minutes == 10, "menit jadi \(draft.minutes)")
        draft.minutes = 0; draft.bump(.minutes, by: -1)
        check("menit turun dari 0 membungkus ke 59", draft.minutes == 59, "menit jadi \(draft.minutes)")
        draft.hours = 0; draft.minutes = 0; draft.seconds = 0
        check("draft nol dikenali (tombol Mulai nonaktif)", draft.isZero)

        let idleState = IslandState()
        check("idle: konten kiri kosong → klaster ikon di tengah",
              !idleState.hasCollapsedLeading)
        idleState.activity = Activity(label: "Uji", total: 60, remaining: 60, startedAt: Date())
        check("timer aktif: konten kiri terisi → klaster bergeser",
              idleState.hasCollapsedLeading)
        idleState.activity = nil

        print("---")
        print(failures == 0 ? "SEMUA \(checks) PEMERIKSAAN LULUS" : "\(failures) dari \(checks) pemeriksaan GAGAL")
        return Int32(failures)
    }
}
