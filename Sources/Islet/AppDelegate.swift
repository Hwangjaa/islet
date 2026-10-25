import AppKit
import CoreAudio
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    static let shared = AppDelegate()

    let state = IslandState()
    private var panel: IslandPanel?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?

    private var volumeMonitor: VolumeMonitor!
    private var batteryMonitor: BatteryMonitor!
    private var nowPlayingMonitor: NowPlayingMonitor!
    private var calendarMonitor: CalendarMonitor!
    private var outputDeviceMonitor: OutputDeviceMonitor!
    private var shelf: ScreenshotShelf!
    private var notificationMirror = AccessibilityNotificationMirror()
    private var connectivityMonitor: ConnectivityMonitor!

    private var timers: [Timer] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        buildStatusItem()
        startMonitors()
        installEventMonitor()
        installDebugChannel()
        installNotificationPipeline()

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        applySettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timers.forEach { $0.invalidate() }
    }

    // MARK: - Panel

    private func buildPanel() {
        let panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 44))
        let host = NSHostingView(rootView: IslandView(state: state, actions: IslandActions(
            playPause: { [weak self] in self?.nowPlayingMonitor.togglePlayPause() },
            next: { [weak self] in self?.nowPlayingMonitor.nextTrack() },
            previous: { [weak self] in self?.nowPlayingMonitor.previousTrack() },
            setVolume: { [weak self] v in self?.volumeMonitor.setVolume(v) },
            toggleMute: { [weak self] in self?.volumeMonitor.toggleMute() },
            cycleModule: { [weak self] in self?.state.cycleModule() },
            openSettings: { [weak self] in self?.showSettings() },
            startActivity: { [weak self] minutes in self?.startActivity(minutes: minutes) },
            stopActivity: { [weak self] in self?.state.activity = nil },
            revealShelf: { [weak self] in self?.openShelfFolder() },
            removeShelf: { [weak self] item in
                self?.shelf.remove(item)
                self?.syncShelf()
            },
            clearShelf: { [weak self] in
                self?.shelf.clearAll()
                self?.syncShelf()
            },
            selectOutput: { [weak self] id in self?.selectOutputDevice(id) },
            openAccessibilitySettings: { [weak self] in self?.openAccessibilitySettings() },
            refreshMirror: { [weak self] in self?.refreshMirror() }
        )))
        host.frame = panel.frame
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()
        panel.setFrame(IslandGeometry.frame(for: .collapsed, settings: state.settings), display: true)
        self.panel = panel
    }

    @objc private func screensChanged() {
        layout(animated: false)
    }

    private func layout(animated: Bool) {
        guard let panel else { return }
        let mode: IslandGeometry.Mode = state.isExpanded ? .expanded : .collapsed
        let frame = IslandGeometry.frame(for: mode, settings: state.settings)
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }
        // Animasi jendela dengan kurva easing, bukan animasi bawaan AppKit yang terasa kaku.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = IslandAnim.windowDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - Status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.inset.filled", accessibilityDescription: "Islet")
        let menu = NSMenu()

        menu.addItem(withTitle: "Buka Panel (Island)", action: #selector(toggleIsland), keyEquivalent: "i").target = self
        menu.addItem(NSMenuItem.separator())

        let timerItem = NSMenuItem(title: "Mulai Hitung Waktu", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        for minutes in [1, 5, 10, 25] {
            let mi = NSMenuItem(title: "\(minutes) menit", action: #selector(startTimerFromMenu(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = minutes
            timerMenu.addItem(mi)
        }
        timerItem.submenu = timerMenu
        menu.addItem(timerItem)
        menu.addItem(withTitle: "Stop Hitung Waktu", action: #selector(stopTimer), keyEquivalent: "").target = self

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Tampilkan Tangkapan", action: #selector(showShelf), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Buka Folder Tangkapan", action: #selector(openShelfFolder), keyEquivalent: "").target = self

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Pengaturan…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Keluar Islet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.menu = menu
        statusItem = item
    }

    @objc private func toggleIsland() {
        state.isExpanded.toggle()
        layout(animated: true)
    }

    @objc private func startTimerFromMenu(_ sender: NSMenuItem) {
        startActivity(minutes: sender.tag)
    }

    @objc private func stopTimer() {
        state.activity = nil
    }

    private func startActivity(minutes: Int) {
        let total = TimeInterval(minutes * 60)
        state.activity = Activity(label: "\(minutes) menit", total: total, remaining: total, startedAt: Date())
        state.isExpanded = true
        layout(animated: true)
        SoundPlayer.shared.play(.activityStart)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Pengaturan Islet"
            window.contentView = NSHostingView(rootView: SettingsView(settings: state.settings, onChange: { [weak self] in
                self?.applySettings()
            }))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func applySettings() {
        panel?.ignoresMouseEvents = false
        // Ukuran panel mengikuti preferensi pengguna.
        layout(animated: true)
        volumeMonitor.enabled = state.settings.showVolumeHUD
        batteryMonitor.enabled = state.settings.showBattery
        nowPlayingMonitor.enabled = state.settings.showNowPlaying
        calendarMonitor.enabled = state.settings.showCalendar
        outputDeviceMonitor.enabled = state.settings.showOutputDevice
        if let shelf { state.shelfItems = shelf.items }
        syncMirror()
    }

    /// Membuka panel Accessibility, menampilkan Islet.app di Finder, dan menyalin path-nya
    /// ke clipboard. macOS tidak mengizinkan aplikasi menambahkan dirinya sendiri ke daftar
    /// Accessibility (TCC dilindungi), jadi langkah tercepat adalah: drag dari Finder ke daftar.
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        let appURL = Bundle.main.bundleURL
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appURL.path, forType: .string)
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
        AccessibilityNotificationMirror.requestPermission()
        state.notifications.post(source: "Islet",
                                 title: "Langkah izin cermin",
                                 body: "1) System Settings → Accessibility. 2) Tambahkan Islet.app (path sudah disalin). 3) Keluar & buka lagi Islet.",
                                 symbol: "lock.shield.fill")
    }

    private func refreshMirror() {
        notificationMirror.start()
        let granted = AccessibilityNotificationMirror.hasPermission
        state.notifications.post(source: "Islet",
                                 title: granted ? "Izin Accessibility sudah ada" : "Izin belum ada",
                                 body: granted
                                     ? "Kalau notifikasi macOS belum tercermin, keluar dan buka lagi Islet sekali."
                                     : "Tambahkan Islet.app di System Settings → Privacy & Security → Accessibility, lalu buka lagi Islet.",
                                 symbol: granted ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
    }

    private func syncShelf() {
        state.shelfItems = shelf.items
    }

    /// Ganti perangkat keluaran audio dari modul Volume.
    private func selectOutputDevice(_ id: UInt32) {
        VolumeMonitor.setDefaultOutputDevice(AudioDeviceID(id))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.state.outputDevices = VolumeMonitor.outputDeviceList()
            SoundPlayer.shared.play(.toggle)
        }
    }

    @objc private func openShelfFolder() {
        NSWorkspace.shared.open(shelf.directory)
    }

    @objc private func showShelf() {
        state.module = .shelf
        state.setExpanded(true)
    }

    /// Gambar uji sintetis untuk memverifikasi jalur simpan/thumbnail/drag tanpa menyentuh clipboard.
    private func shelfInjectTestImage() {
        let size = NSSize(width: 480, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let label = "Islet shelf test \(Date().formatted(date: .omitted, time: .standard))" as NSString
        label.draw(at: NSPoint(x: 24, y: 140),
                   withAttributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold),
                                    .foregroundColor: NSColor.white])
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        _ = shelf.write(data: png, pixelSize: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        syncShelf()
    }

    // MARK: - Notifikasi island

    private func installNotificationPipeline() {
        // 1. Kanal lokal: aplikasi/script lain boleh mengirim notifikasi ke island.
        IslandNotificationChannel.listen { [weak self] title, body, source, symbol in
            self?.state.notifications.post(source: source, title: title, body: body, symbol: symbol)
        }

        // 2. Setiap notifikasi baru ditampilkan gaya Dynamic Island lalu menutup sendiri.
        state.notifications.onPost = { [weak self] _ in
            guard let self else { return }
            // Notifikasi TIDAK melebarkan capsule — cukup pill kecil di dalam island yang sudah ada,
            // supaya bentuk notch tetap rapi. Klik pill untuk membuka modul Notifikasi.
            if !self.state.isExpanded { SoundPlayer.shared.play(.toggle) }
        }

        // 3. Cermin Notification Center (opt-in, butuh izin Accessibility).
        notificationMirror.onBanner = { [weak self] app, title, body in
            self?.state.notifications.post(source: app, title: title, body: body,
                                           symbol: "app.badge.fill", mirrored: true)
        }
        if state.settings.mirrorSystemNotifications { notificationMirror.start() }

        // 4. Skema URL: islet://notify?title=...&body=...&source=...
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: raw), url.scheme == "islet" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = { (name: String) -> String? in
            components?.queryItems?.first(where: { $0.name == name })?.value
        }
        state.notifications.post(source: query("source") ?? "Islet",
                                title: query("title") ?? "Notifikasi",
                                body: query("body") ?? "",
                                symbol: query("symbol") ?? "bell.fill")
    }

    private func syncMirror() {
        if state.settings.mirrorSystemNotifications {
            notificationMirror.start()
        }
    }

    private var eventMonitor: Any?
    private var gestureGate = GestureGate()
    private var expandGate = GestureGate()

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.swipe, .scrollWheel]) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }

            if event.type == .swipe {
                let dx = event.deltaX
                let dy = event.deltaY
                if abs(dx) > abs(dy) {
                    guard self.state.settings.swipeToCycle else { return nil }
                    self.stepModule(forward: dx < 0)
                } else if dy < 0 {
                    self.stepExpanded(open: true)
                } else {
                    self.stepExpanded(open: false)
                }
                return nil
            }

            // Sisa momentum dari gestur sebelumnya tidak boleh memicu aksi baru.
            if event.momentumPhase != [] { return nil }

            // Akhir gestur: buka kunci lebih awal.
            if event.phase == .ended || event.phase == .cancelled {
                self.gestureGate.release()
                self.expandGate.release()
                return event
            }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            if abs(dx) > abs(dy) * 1.2, abs(dx) > 5 {
                guard self.state.settings.swipeToCycle else { return event }
                self.stepModule(forward: dx < 0)
                return nil
            }
            if abs(dy) > abs(dx) * 1.2, abs(dy) > 5 {
                self.stepExpanded(open: dy < 0)
                return nil
            }
            return event
        }
    }

    /// Satu gestur geser = satu modul. Gerbang menolak event susulan dalam gestur yang sama.
    private func stepModule(forward: Bool) {
        let now = Date()
        guard gestureGate.registerAction(at: now) else { return }
        state.module = forward ? state.nextModule() : state.previousModule()
    }

    private func stepExpanded(open: Bool) {
        let now = Date()
        guard expandGate.registerAction(at: now) else { return }
        state.setExpanded(open)
    }

    // MARK: - Kanal debug (untuk verifikasi otomatis dari CLI)

    private func installDebugChannel() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.rafael.islet.debug"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, let cmd = note.userInfo?["cmd"] as? String else { return }
            switch cmd {
            case "expand":
                self.state.pinned = true
                self.state.setExpanded(true)
            case "hoverSim":
                self.runHoverSimulation()
            case "collapse":
                self.state.pinned = false
                self.state.setExpanded(false)
            case "togglePin":
                self.state.pinned.toggle()
                self.state.setExpanded(self.state.pinned)
            case "next":
                self.state.module = self.state.nextModule()
            case "previous":
                self.state.module = self.state.previousModule()
            case "activity":
                self.startActivity(minutes: (note.userInfo?["minutes"] as? Int) ?? 1)
            case "activityStop":
                self.state.activity = nil
            case "hudVolume":
                let value = (note.userInfo?["value"] as? Double).map(Float.init) ?? 0.5
                self.state.showHUD(.volume, value: value)
            case "hudBattery":
                self.state.showHUD(self.state.battery.charging ? .charging : .battery,
                                   value: Float(self.state.battery.percent) / 100)
            case "settings":
                self.showSettings()
            case "shelfInject":
                self.shelfInjectTestImage()
            case "gestureBurst":
                // Meniru satu gestur yang membanjiri banyak event: hanya satu langkah yang boleh lolos.
                for _ in 0..<5 { self.stepModule(forward: true) }
            case "notify":
                let info = note.userInfo ?? [:]
                self.state.notifications.post(
                    source: (info["source"] as? String) ?? "Uji",
                    title: (info["title"] as? String) ?? "Notifikasi uji",
                    body: (info["body"] as? String) ?? "Isi notifikasi dari kanal debug",
                    symbol: (info["symbol"] as? String) ?? "bell.fill")
            case "notifClear":
                self.state.notifications.clear()
            case "notifList":
                let path = (note.userInfo?["path"] as? String) ?? "/tmp/islet-notifications.json"
                let payload: [String: Any] = [
                    "count": self.state.notifications.items.count,
                    "active": self.state.notifications.active.map { "\($0.source): \($0.title)" } as Any,
                    "mirrorStatus": self.notificationMirror.status,
                    "mirrorPermission": AccessibilityNotificationMirror.hasPermission,
                    "mirrorCaptured": self.notificationMirror.capturedCount,
                    "mirrorLastDump": self.notificationMirror.lastRawDump,
                    "items": self.state.notifications.items.map {
                        ["source": $0.source, "title": $0.title, "body": $0.body,
                         "mirrored": $0.mirrored,
                         "at": $0.date.formatted(date: .omitted, time: .standard)]
                    }
                ]
                if let data = try? JSONSerialization.data(withJSONObject: payload,
                                                          options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            case "mirrorRequest":
                AccessibilityNotificationMirror.requestPermission()
                self.notificationMirror.start()
            case "shelfClear":
                self.shelf.clearAll()
                self.syncShelf()
            case "shelfList":
                let path = (note.userInfo?["path"] as? String) ?? "/tmp/islet-shelf.json"
                let list: [[String: Any]] = self.shelf.items.map {
                    ["file": $0.url.lastPathComponent,
                     "id": String($0.id.prefix(12)),
                     "w": Int($0.pixelSize.width),
                     "h": Int($0.pixelSize.height),
                     "exists": FileManager.default.fileExists(atPath: $0.url.path)]
                }
                let payload: [String: Any] = ["count": list.count,
                                              "directory": self.shelf.directory.path,
                                              "items": list]
                if let data = try? JSONSerialization.data(withJSONObject: payload,
                                                          options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            case "quit":
                NSApp.terminate(nil)
            case "snapshot":
                let path = (note.userInfo?["path"] as? String) ?? "/tmp/islet-snapshot.json"
                var dict = self.state.snapshot()
                dict["batteryDebug"] = self.batteryMonitor.debugInfo()
                if let data = try? JSONSerialization.data(withJSONObject: dict,
                                                          options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            default:
                break
            }
        }
    }

    // MARK: - Hover monitor (tanpa SwiftUI onHover)

    private var hoverTimer: Timer?
    private var hoverEnteredAt: Date?
    private var hoverLeftAt: Date?
    private var lastTransitionAt = Date.distantPast

    /// `onHover` SwiftUI tidak dipakai untuk buka/tutup. Setiap kali jendela berubah ukuran,
    /// tracking area di-reset sehingga event hover bisa berganti masuk/keluar berulang-ulang —
    /// itulah penyebab island membesar-mengecil cepat saat kursor didekatkan.
    /// Monitor ini membaca posisi kursor sebenarnya, dengan histeresis dua zona dan jeda:
    /// masuk = pill (+6 pt, tunggu 0,08 s), keluar = area terbuka (+2 pt, tunggu 0,32 s).
    private func startHoverMonitor() {
        hoverTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 25.0, repeats: true) { [weak self] _ in
            self?.evaluateHover(at: NSEvent.mouseLocation)
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func evaluateHover(at mouse: CGPoint, now: Date = Date()) {
        let collapsed = IslandGeometry.frame(for: .collapsed, settings: state.settings)
        let expanded = IslandGeometry.frame(for: .expanded, settings: state.settings)
        let enterZone = collapsed.insetBy(dx: -6, dy: -6)
        // Zona "tetap terbuka" HARUS memuat zona masuk sepenuhnya. Dulu keduanya hanya
        // "expanded − 2 pt" sehingga ada pita 4 pt di tepi pill yang masuk zona buka tetapi
        // di luar zona tahan → island membesar-mengecil berulang di titik itu.
        let stayZone = expanded.union(enterZone).insetBy(dx: -8, dy: -8)

        let inside = enterZone.contains(mouse)
        if state.hovering != inside { state.hovering = inside }   // hindari publish 25×/detik

        guard state.settings.hoverToExpand else {
            hoverEnteredAt = nil
            hoverLeftAt = nil
            return
        }

        // Jeda minimum antar transisi: jaring pengaman terakhir kalau geometri berubah.
        let coolingDown = now.timeIntervalSince(lastTransitionAt) < 0.35

        if enterZone.contains(mouse) {
            hoverLeftAt = nil
            guard !state.isExpanded, !coolingDown else {
                if state.isExpanded { hoverEnteredAt = nil }
                return
            }
            if hoverEnteredAt == nil { hoverEnteredAt = now }
            if let start = hoverEnteredAt, now.timeIntervalSince(start) >= 0.08 {
                hoverEnteredAt = nil
                lastTransitionAt = now
                state.setExpanded(true)
            }
        } else {
            hoverEnteredAt = nil
            guard !stayZone.contains(mouse), !state.pinned, !coolingDown else {
                hoverLeftAt = nil
                return
            }
            if hoverLeftAt == nil { hoverLeftAt = now }
            if let left = hoverLeftAt, now.timeIntervalSince(left) >= 0.32 {
                hoverLeftAt = nil
                lastTransitionAt = now
                state.setExpanded(false)
            }
        }
    }

    /// Uji deterministik histeresis: untuk setiap titik di tepi pill, jalankan 10 evaluasi
    /// (1 detik) dan hitung berapa kali state berubah. 1 = normal, ≥2 = osilasi.
    private func runHoverSimulation() {
        let pill = IslandGeometry.frame(for: .collapsed, settings: state.settings)
        var points: [CGPoint] = []
        for dy in stride(from: -12.0, through: pill.height + 12.0, by: 2.0) {
            points.append(CGPoint(x: pill.midX, y: pill.minY + dy))
        }
        for dx in stride(from: -12.0, through: pill.width + 12.0, by: 12.0) {
            points.append(CGPoint(x: pill.minX + dx, y: pill.midY))
        }
        var worst = 0
        var oscillating: [String] = []
        for point in points {
            state.pinned = false
            state.setExpanded(false)
            hoverEnteredAt = nil
            hoverLeftAt = nil
            lastTransitionAt = .distantPast
            var flips = 0
            var last = state.isExpanded
            let base = Date()
            for step in 0..<10 {
                evaluateHover(at: point, now: base.addingTimeInterval(Double(step) * 0.1))
                if state.isExpanded != last {
                    flips += 1
                    last = state.isExpanded
                }
            }
            if flips > 1 { oscillating.append("\(flips)× di (\(Int(point.x)),\(Int(point.y)))") }
            worst = max(worst, flips)
        }
        Debug.trace("hoverSim: \(points.count) titik, flip maksimum = \(worst), titik berosilasi = \(oscillating.count)")
        for line in oscillating.prefix(8) { Debug.trace("  osilasi \(line)") }
        state.setExpanded(false)
        state.pinned = false
    }

    // MARK: - Monitors

    private func startMonitors() {
        volumeMonitor = VolumeMonitor(state: state)
        batteryMonitor = BatteryMonitor(state: state)
        nowPlayingMonitor = NowPlayingMonitor(state: state)
        calendarMonitor = CalendarMonitor(state: state)
        outputDeviceMonitor = OutputDeviceMonitor(state: state)

        volumeMonitor.start()
        batteryMonitor.start()
        nowPlayingMonitor.start()
        calendarMonitor.start()
        outputDeviceMonitor.start()

        connectivityMonitor = ConnectivityMonitor(state: state)
        connectivityMonitor.start()

        startHoverMonitor()

        // Shelf tangkapan layar: menangkap gambar yang masuk ke clipboard.
        shelf = ScreenshotShelf()
        shelf.onNewItem = { [weak self] item in
            guard let self else { return }
            self.syncShelf()
            self.state.notifications.post(source: "Islet",
                                          title: "Tangkapan tersimpan",
                                          body: "\(Int(item.pixelSize.width))×\(Int(item.pixelSize.height)) px · tarik dari modul Tangkapan",
                                          symbol: "photo.fill")
            self.state.module = .shelf
            self.state.setExpanded(true)
            SoundPlayer.shared.play(.toggle)
            // Tampilkan sebentar; tutup lagi kalau pengguna tidak mengunci.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
                guard let self, !self.state.pinned else { return }
                self.state.setExpanded(false)
            }
        }
        shelf.start()
        syncShelf()

        // Perubahan state yang mengubah ukuran panel.
        state.onLayoutChange = { [weak self] animated in self?.layout(animated: animated) }
    }
}
