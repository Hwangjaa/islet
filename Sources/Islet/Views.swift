import AppKit
import SwiftUI

struct IslandActions {
    var playPause: () -> Void
    var next: () -> Void
    var previous: () -> Void
    var setVolume: (Float) -> Void
    var toggleMute: () -> Void
    var cycleModule: () -> Void
    var openSettings: () -> Void
    var startActivity: (Int) -> Void
    var stopActivity: () -> Void
    var revealShelf: () -> Void
    var removeShelf: (ShelfItem) -> Void
    var clearShelf: () -> Void
    var selectOutput: (UInt32) -> Void
    var openAccessibilitySettings: () -> Void
    var refreshMirror: () -> Void
}

// MARK: - Tampilan island

struct IslandView: View {

    @ObservedObject var state: IslandState
    let actions: IslandActions

    @State private var dragStart: CGPoint?

    private var screen: NSScreen? { IslandGeometry.targetScreen }
    private var topInset: CGFloat { IslandGeometry.topInset(screen: screen, settings: state.settings) }
    private var notched: Bool { IslandGeometry.hasRealNotch(screen: screen, settings: state.settings) }

    var body: some View {
        ZStack(alignment: .top) {
            background
            VStack(spacing: 0) {
                Color.clear.frame(height: topInset)   // area notch: hitam, tanpa konten
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onHover { _ in }   // hover ditangani HoverMonitor (jendela berubah ukuran; onHover memicu osilasi)
        .animation(IslandAnim.panel, value: state.isExpanded)
        .animation(IslandAnim.content, value: state.module)
        .animation(IslandAnim.content, value: state.hud)
        .animation(IslandAnim.panel, value: state.activeNotification)
        .animation(IslandAnim.micro, value: state.battery.charging)
    }

    // MARK: Latar — menyatu dengan notch

    private var islandShape: AnyShape {
        let radius: CGFloat = state.isExpanded ? 26 : 17
        if notched {
            return AnyShape(UnevenRoundedRectangle(topLeadingRadius: 0,
                                                  bottomLeadingRadius: radius,
                                                  bottomTrailingRadius: radius,
                                                  topTrailingRadius: 0,
                                                  style: .continuous))
        }
        // Tanpa notch: island mengambang sedikit dari tepi atas.
        return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .offset(y: IslandGeometry.floatingGap))
    }

    private var background: some View {
        islandShape
            .fill(Color.black.opacity(0.96))
            .overlay(islandShape.stroke(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(state.hovering || state.isExpanded ? 0.45 : 0.25),
                    radius: state.isExpanded ? 14 : 8,
                    y: state.isExpanded ? 6 : 3)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { togglePin() }
            .scaleEffect(state.hovering && !state.isExpanded ? 1.02 : 1.0, anchor: .top)
    }

    // MARK: Isi

    @ViewBuilder
    private var content: some View {
        if let note = state.activeNotification, !state.isExpanded {
            notificationPill(note)
                .frame(height: IslandGeometry.collapsedContentHeight)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)),
                                        removal: .opacity))
        } else if let hud = state.hud, !state.isExpanded {
            hudView(hud)
                .frame(height: IslandGeometry.collapsedContentHeight)
                .transition(.opacity)
        } else if state.isExpanded {
            expanded
                .frame(height: IslandGeometry.expandedContentHeight)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)),
                                        removal: .opacity))
        } else {
            collapsed
                .frame(height: IslandGeometry.collapsedContentHeight)
                .transition(.opacity)
        }
    }

    // MARK: Collapsed

    private var collapsed: some View {
        ZStack {
            // Tiga ikon status (Wi-Fi, Bluetooth, baterai) selalu di tengah pill.
            HStack(spacing: 6) {
                connectivityIcons
                if state.settings.showBattery && state.battery.available {
                    batteryBadge
                }
            }
            // Konten kiri (media/timer/tangkapan) menempel kiri, lebarnya dibatasi
            // supaya tidak menabrak kelompok tengah.
            HStack(spacing: 0) {
                collapsedLeading
                    .frame(maxWidth: 92, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
    }

    /// Ikon Wi-Fi & Bluetooth di tengah pill (dicoret saat tidak aktif).
    private var connectivityIcons: some View {
        HStack(spacing: 5) {
            Image(systemName: state.connectivity.wifi ? "wifi" : "wifi.slash")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(state.connectivity.wifi ? Color.white.opacity(0.88)
                                                         : Color.white.opacity(0.35))

            ZStack {
                BluetoothGlyph()
                    .stroke(style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                    .frame(width: 8, height: 11)
                if state.connectivity.bluetoothKnown && !state.connectivity.bluetooth {
                    Rectangle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 12, height: 1.2)
                        .rotationEffect(.degrees(-45))
                }
            }
            .foregroundStyle(state.connectivity.bluetooth ? Color.blue.opacity(0.95)
                                                          : Color.white.opacity(0.35))
        }
        .animation(IslandAnim.micro, value: state.connectivity)
    }

    @ViewBuilder
    private var collapsedLeading: some View {
        if let activity = state.activity {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange)
                Text(timeString(remaining(of: activity)))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white).monospacedDigit()
                MiniBar(progress: activity.progress, tint: .orange, width: 30)
            }
        } else if state.settings.showNowPlaying && state.nowPlaying.known {
            HStack(spacing: 6) {
                if state.nowPlaying.isPlaying {
                    EqualizerBars(playing: true)
                } else {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.nowPlaying.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white).lineLimit(1)
                    if !state.nowPlaying.artist.isEmpty {
                        Text(state.nowPlaying.artist)
                            .font(.system(size: 8)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                }
            }
        } else if let item = state.shelfItems.first, Date().timeIntervalSince(item.addedAt) < 300 {
            HStack(spacing: 5) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                Text("1 tangkapan").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var batteryBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: batterySymbol).font(.system(size: 10, weight: .semibold))
            Text("\(state.battery.percent)%")
                .font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(state.battery.charging ? .green
                         : (state.battery.percent <= 20 ? .red : .white.opacity(0.75)))
    }

    private var batterySymbol: String {
        if state.battery.charging || state.battery.onAC { return "bolt.fill" }
        switch state.battery.percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    // MARK: HUD

    private func hudView(_ hud: HUDState) -> some View {
        HStack(spacing: 9) {
            Image(systemName: hudSymbol(hud))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hud.kind == .charging ? .green : .white)
            if hud.kind.isBatteryFamily {
                Text("\(Int(hud.value * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white).monospacedDigit()
                Text(hud.kind.caption)
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.7))
            } else {
                MiniBar(progress: Double(hud.value), tint: .white, width: 92)
                Text(hud.kind == .mute ? "Mute" : "\(Int(hud.value * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85)).monospacedDigit()
            }
        }
    }

    private func hudSymbol(_ hud: HUDState) -> String {
        switch hud.kind {
        case .mute: return "speaker.slash.fill"
        case .battery: return batterySymbol
        case .charging: return "bolt.fill"
        case .onAC: return "bolt.slash.fill"
        case .volume:
            switch hud.value {
            case 0: return "speaker.fill"
            case ..<0.34: return "speaker.wave.1.fill"
            case ..<0.67: return "speaker.wave.2.fill"
            default: return "speaker.wave.3.fill"
            }
        }
    }

    // MARK: Expanded

    private var expanded: some View {
        VStack(spacing: 6) {
            header
            ZStack {
                moduleContent
                    .id(state.module)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)),
                                            removal: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(.top, 6)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: state.module.symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16, alignment: .center)

            // Lebar tetap: judul yang panjangnya berbeda tidak boleh menggeser tombol lain.
            Text(state.module.title)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: IslandLayout.headerTitleWidth, alignment: .leading)

            Spacer(minLength: 0)

            Button { togglePin() } label: {
                Image(systemName: state.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(state.pinned ? .orange : .white.opacity(0.7))
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(state.pinned ? "Lepas kunci" : "Kunci island tetap terbuka")

            Button(action: actions.openSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11))
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Pengaturan Islet")
        }
        .foregroundStyle(.white.opacity(0.88))
    }

    private func moduleStepButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: IslandLayout.stepButtonSize.width,
                       height: IslandLayout.stepButtonSize.height)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.09)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch state.module {
        case .nowPlaying: nowPlayingView
        case .shelf: shelfView
        case .notifications: notificationsView
        case .volume: volumeView
        case .battery: batteryView
        case .calendar: calendarView
        case .activity: activityView
        }
    }

    // MARK: Notifikasi (gaya Dynamic Island)

    /// Pill ringkas saat notifikasi baru datang: ikon + sumber + judul.
    private func notificationPill(_ note: IslandNotification) -> some View {
        HStack(spacing: 8) {
            Image(systemName: note.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(note.mirrored ? .yellow : .blue)
            Text(note.source)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            Text(note.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Klik pill: buka modul Notifikasi dalam keadaan terkunci (tanpa mengubah apa pun
            // kalau pengguna hanya ingin melihat sekilas).
            state.module = .notifications
            state.pinned = true
            state.setExpanded(true)
        }
        .help("Klik untuk membuka modul Notifikasi")
    }

    private var notificationsView: some View {
        VStack(spacing: 5) {
            if let note = state.notificationItems.first {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: note.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(note.mirrored ? .yellow : .blue)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white).lineLimit(1)
                        if !note.body.isEmpty {
                            Text(note.body)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(2)
                        }
                        Text("\(note.source) · \(note.date.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer(minLength: 0)
                }
                if state.notificationItems.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(state.notificationItems.prefix(6)) { item in
                            Circle()
                                .fill(item.id == note.id ? Color.white.opacity(0.9) : Color.white.opacity(0.25))
                                .frame(width: 5, height: 5)
                        }
                        Spacer()
                        Text("\(state.notificationItems.count) terakhir")
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                    }
                }
                HStack(spacing: 12) {
                    Button("Tutup pill") { state.notifications.dismissActive() }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    Button("Bersihkan") { state.notifications.clear() }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 0)
                }
            } else {
                Image(systemName: "bell.slash").foregroundStyle(.white.opacity(0.5))
                Text("Belum ada notifikasi.")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.65))
                Text("Kirim dari terminal: islet-notify \"Judul\" \"Isi pesan\"")
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }

            // Bantuan izin cermin notifikasi macOS (2 langkah, sejelas mungkin)
            Divider().overlay(Color.white.opacity(0.08))
            HStack(spacing: 7) {
                Image(systemName: AccessibilityNotificationMirror.hasPermission
                      ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AccessibilityNotificationMirror.hasPermission ? .green : .orange)
                Text(AccessibilityNotificationMirror.hasPermission
                     ? "Cermin aktif — izin Accessibility sudah ada"
                     : "Cermin butuh izin Accessibility")
                    .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 0)
                Button("Buka Pengaturan") { actions.openAccessibilitySettings() }
                    .buttonStyle(.plain).font(.system(size: 9.5)).foregroundStyle(.blue.opacity(0.9))
                if !AccessibilityNotificationMirror.hasPermission {
                    Button("Cek ulang") { actions.refreshMirror() }
                        .buttonStyle(.plain).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    // MARK: Tangkapan layar (shelf)

    private var shelfView: some View {
        VStack(spacing: 6) {
            if let item = state.shelfItems.first {
                HStack(spacing: 10) {
                    if let thumb = NSImage(contentsOf: item.url) {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 74, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1))
                            .onDrag { NSItemProvider(object: item.url as NSURL) }
                            .help("Tarik keluar untuk memakai gambar ini")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(item.pixelSize.width))×\(Int(item.pixelSize.height)) px")
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
                        Text("\(item.addedAt.formatted(date: .omitted, time: .shortened)) · \(state.shelfItems.count) tersimpan")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                        Text("tarik gambar ke atas untuk drag")
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                }
                HStack(spacing: 12) {
                    Button("Buka di Finder") { actions.revealShelf() }
                        .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.blue.opacity(0.9))
                    Button("Hapus ini") { actions.removeShelf(item) }
                        .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                    Button("Bersihkan") { actions.clearShelf() }
                        .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
            } else {
                Image(systemName: "camera.viewfinder").foregroundStyle(.white.opacity(0.5))
                Text("Belum ada tangkapan.")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.65))
                Text("Ambil screenshot (⌘⌃⇧4) — gambarnya tersimpan di sini dan bisa ditarik keluar.")
                    .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var nowPlayingView: some View {
        VStack(spacing: 7) {
            if state.nowPlaying.known {
                Text(state.nowPlaying.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
                Text(state.nowPlaying.artist.isEmpty
                     ? state.nowPlaying.app
                     : "\(state.nowPlaying.artist) · \(state.nowPlaying.app)")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                HStack(spacing: 20) {
                    controlButton("backward.fill", actions.previous)
                    controlButton(state.nowPlaying.isPlaying ? "pause.fill" : "play.fill", actions.playPause, large: true)
                    controlButton("forward.fill", actions.next)
                }
                .padding(.top, 1)
            } else if state.nowPlaying.denial {
                Image(systemName: "lock.shield").foregroundStyle(.orange)
                Text("Izin otomasi ke \(state.nowPlaying.app.isEmpty ? "aplikasi musik" : state.nowPlaying.app) belum diberikan.")
                    .font(.system(size: 10.5)).multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
                Text("System Settings → Privacy & Security → Automation → izinkan Islet.")
                    .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "music.note.list").foregroundStyle(.white.opacity(0.5))
                Text("Tidak ada media yang diputar.")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.65))
                Text("Buka Music atau Spotify, lalu putar lagu.")
                    .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var volumeView: some View {
        VStack(spacing: 7) {
            HStack(spacing: 9) {
                Button(action: actions.toggleMute) {
                    Image(systemName: state.volume.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)

                Slider(value: Binding(get: { Double(state.volume.muted ? 0 : state.volume.level) },
                                      set: { actions.setVolume(Float($0)) }), in: 0...1)

                Text("\(Int((state.volume.muted ? 0 : state.volume.level) * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85)).monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }

            // Pemilih perangkat keluaran — bagian "Perangkat" yang digabung ke sini.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(state.outputDevices) { device in
                        Button {
                            actions.selectOutput(device.id)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: device.isBluetooth ? "hifispeaker.fill" : "hifispeaker")
                                    .font(.system(size: 9))
                                Text(device.name)
                                    .font(.system(size: 9.5, weight: device.isDefault ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(device.isDefault ? Color.white.opacity(0.22) : Color.white.opacity(0.07)))
                            .foregroundStyle(device.isDefault ? Color.white : Color.white.opacity(0.7))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(device.isDefault ? "Perangkat keluaran aktif" : "Jadikan perangkat keluaran")
                    }
                    if state.outputDevices.isEmpty {
                        Text("tidak ada perangkat keluaran")
                            .font(.system(size: 9.5)).foregroundStyle(.orange.opacity(0.85))
                    }
                }
                .padding(.horizontal, 1)
            }
            .frame(height: 22)

            HStack(spacing: 12) {
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                    Button("\(Int(level * 100))%") { actions.setVolume(Float(level)) }
                        .buttonStyle(.plain).font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                if !state.volume.available {
                    Text("volume tidak terbaca").font(.system(size: 9)).foregroundStyle(.orange.opacity(0.85))
                }
            }
        }
    }

    private var batteryView: some View {
        VStack(spacing: 7) {
            if state.battery.available {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(state.battery.percent)%")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white).monospacedDigit()
                    Image(systemName: batterySymbol)
                        .foregroundStyle(state.battery.charging ? .green : .white.opacity(0.7))
                }
                ProgressView(value: Double(state.battery.percent), total: 100)
                    .progressViewStyle(.linear)
                    .tint(state.battery.percent <= 20 ? .red : (state.battery.charging ? .green : .white.opacity(0.7)))
                    .frame(width: 220)
                    .animation(.easeInOut(duration: 0.3), value: state.battery.percent)
                Text(statusText).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.65))
                if state.battery.charging && state.battery.percent >= 80 {
                    Text("Sudah di atas 80% — mencabut adaptor membantu menjaga kesehatan baterai.")
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("Tidak ada baterai internal yang terdeteksi.")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var statusText: String {
        if state.battery.charging { return "Mengisi daya" }
        if state.battery.onAC { return "Tersambung adaptor (tidak mengisi)" }
        if let minutes = state.battery.minutesRemaining {
            return "Ga lagi ngecas cok · sisa \(minutes / 60)j \(minutes % 60)m"
        }
        return "Ga lagi ngecas cok"
    }

    private var calendarView: some View {
        VStack(spacing: 5) {
            if let event = state.nextEvent {
                Text(event.title).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.center)
                Text("\(event.calendar) · \(event.start.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(relative(from: context.date, to: event.start))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Button("Buka Kalender") { openCalendar() }
                    .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.blue.opacity(0.9))
            } else {
                Image(systemName: "calendar.badge.clock").foregroundStyle(.white.opacity(0.5))
                Text("Tidak ada agenda mendatang, atau izin kalender belum diberikan.")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var activityView: some View {
        VStack(spacing: 6) {
            if let activity = state.activity {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, activity.startedAt.addingTimeInterval(activity.total).timeIntervalSince(context.date))
                    let progress = activity.total > 0 ? remaining / activity.total : 0
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
                            Circle()
                                .trim(from: 0, to: CGFloat(progress))
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text(timeString(remaining))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white).monospacedDigit()
                        }
                        .frame(width: 62, height: 62)
                        Text("Hitung waktu \(activity.label)")
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                        Button("Stop") { actions.stopActivity() }
                            .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.orange)
                    }
                }
            } else {
                Image(systemName: "timer").foregroundStyle(.white.opacity(0.5))
                Text("Belum ada hitung waktu aktif.")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 10) {
                    ForEach([1, 5, 25], id: \.self) { minutes in
                        Button("\(minutes) menit") { actions.startActivity(minutes) }
                            .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
    }

    private var deviceView: some View { EmptyView() }

    private var footer: some View {
        HStack(spacing: 0) {
            ForEach(state.availableModules) { module in
                Button {
                    state.module = module
                } label: {
                    Circle()
                        .fill(module == state.module ? Color.white.opacity(0.95) : Color.white.opacity(0.28))
                        .frame(width: IslandLayout.moduleDotSize, height: IslandLayout.moduleDotSize)
                        .padding(IslandLayout.moduleDotPadding)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(module.title)
            }

            Spacer(minLength: 8)

            // Dua tombol navigasi berdampingan di ujung kanan footer. Karena tidak ada lagi
            // teks berubah-lebar di depannya, posisinya tidak pernah bergeser antar modul.
            moduleStepButton("chevron.left", help: "Modul sebelumnya") {
                state.module = state.previousModule()
            }
            moduleStepButton("chevron.right", help: "Modul berikutnya") {
                state.module = state.nextModule()
            }
        }
    }

    private func controlButton(_ symbol: String, _ action: @escaping () -> Void, large: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: large ? 15 : 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: large ? 32 : 26, height: large ? 32 : 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Hover & pin

    private func togglePin() {
        state.pinned.toggle()
        state.setExpanded(state.pinned)
        SoundPlayer.shared.play(.toggle)
    }

    // MARK: Util

    private func remaining(of activity: Activity) -> TimeInterval {
        max(0, activity.startedAt.addingTimeInterval(activity.total).timeIntervalSinceNow)
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func relative(from now: Date, to date: Date) -> String {
        let delta = date.timeIntervalSince(now)
        if delta <= 0 { return "sedang berlangsung" }
        let minutes = Int(delta / 60)
        if minutes < 60 { return "mulai dalam \(minutes) menit" }
        return "mulai dalam \(minutes / 60)j \(minutes % 60)m"
    }

    private func openCalendar() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
}

// MARK: - Komponen kecil

/// Glyph Bluetooth (rune ᛒ) digambar sendiri: SF Symbols di macOS ini tidak punya "bluetooth",
/// dan memakai ikon generik membuat fitur ini tidak terbaca.
struct BluetoothGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        path.move(to: point(0.22, 0.68))
        path.addLine(to: point(0.74, 0.26))
        path.addLine(to: point(0.50, 0.05))
        path.addLine(to: point(0.50, 0.95))
        path.addLine(to: point(0.74, 0.74))
        path.addLine(to: point(0.22, 0.32))
        return path
    }
}

struct MiniBar: View {
    var progress: Double
    var tint: Color
    var width: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(tint)
                    .frame(width: max(2, geo.size.width * CGFloat(max(0, min(1, progress)))))
                    .animation(.easeOut(duration: 0.12), value: progress)
            }
        }
        .frame(width: width, height: 5)
    }
}

struct EqualizerBars: View {
    var playing: Bool

    var body: some View {
        if playing {
            // Dihitung dari waktu, bukan animasi repeatForever: gerakannya halus dan
            // tidak pernah "patah" saat state berubah.
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(Color.green)
                            .frame(width: 2.5,
                                   height: 3 + 8 * abs(sin(t * 2.2 + Double(index) * 0.9)))
                    }
                }
                .frame(height: 12, alignment: .bottom)
            }
        } else {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(Color.white.opacity(0.35)).frame(width: 2.5, height: 3)
                }
            }
            .frame(height: 12, alignment: .bottom)
        }
    }
}

// MARK: - Pengaturan

struct SettingsView: View {
    @ObservedObject var settings: IslandSettings
    var onChange: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Modul").font(.headline)
                Toggle("Media (Now Playing)", isOn: $settings.showNowPlaying)
                Toggle("Tangkapan layar (shelf)", isOn: $settings.showShelf)
                Toggle("Notifikasi island", isOn: $settings.showNotifications)
                Toggle("Cermin notifikasi macOS (butuh izin Accessibility)", isOn: $settings.mirrorSystemNotifications)
                Toggle("HUD volume", isOn: $settings.showVolumeHUD)
                Toggle("Baterai", isOn: $settings.showBattery)
                Toggle("Agenda kalender", isOn: $settings.showCalendar)
                Toggle("Perangkat audio", isOn: $settings.showOutputDevice)

                Text("Perilaku island").font(.headline).padding(.top, 6)
                Toggle("Perluas saat kursor mendekat", isOn: $settings.hoverToExpand)
                Toggle("Geser untuk ganti modul", isOn: $settings.swipeToCycle)
                Toggle("Bunyi sistem", isOn: $settings.playSounds)
                Toggle("Paksa notch palsu", isOn: $settings.forceSimulatedNotch)

                Text("Ukuran").font(.headline).padding(.top, 6)
                HStack {
                    Text("Lebar tambahan")
                    Slider(value: $settings.extraWidth, in: 0...160).frame(width: 200)
                    Text("\(Int(settings.extraWidth)) pt")
                        .font(.system(.caption, design: .monospaced))
                }
                Text("Klik island untuk mengunci posisi terbuka; klik lagi untuk melepas.")
                    .font(.caption).foregroundStyle(.secondary)

                Divider()
                Text("Privasi: aplikasi ini tidak punya sistem lisensi, tidak mengirim data ke mana pun, dan hanya membaca yang kamu izinkan (kalender, kontrol media).")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Terapkan") { onChange() }
            }
            .padding(20)
        }
        .frame(width: 440, height: 520)
    }
}
