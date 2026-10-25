import AppKit
import Combine
import SwiftUI

// MARK: - Modul yang bisa ditampilkan di dalam island

enum IslandModule: String, CaseIterable, Identifiable {
    case nowPlaying, shelf, notifications, volume, battery, calendar, activity
    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: return "Media"
        case .shelf: return "Tangkapan"
        case .notifications: return "Notifikasi"
        case .volume: return "Volume"
        case .battery: return "Baterai"
        case .calendar: return "Agenda"
        case .activity: return "Aktivitas"
        }
    }

    /// Ikon untuk indikator modul di footer. Dipisah dari `symbol` supaya ikon header
    /// tidak ikut berubah.
    var footerSymbol: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .shelf: return "camera.viewfinder"
        case .notifications: return "bell.fill"
        case .volume: return "airplayaudio"
        case .battery: return "battery.75"
        case .calendar: return "calendar"
        case .activity: return "timer"
        }
    }

    var symbol: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .shelf: return "photo.on.rectangle.angled"
        case .notifications: return "bell.badge.fill"
        case .volume: return "speaker.wave.2.fill"
        case .battery: return "battery.75"
        case .calendar: return "calendar"
        case .activity: return "timer"
        }
    }
}

// MARK: - Preferensi pengguna (UserDefaults)

private func settingBool(_ defaults: UserDefaults, _ key: String, _ fallback: Bool) -> Bool {
    defaults.object(forKey: key) as? Bool ?? fallback
}

private func settingDouble(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double {
    defaults.object(forKey: key) as? Double ?? fallback
}

final class IslandSettings: ObservableObject {

    @Published var showNowPlaying: Bool { didSet { save() } }
    @Published var showShelf: Bool { didSet { save() } }
    @Published var showNotifications: Bool { didSet { save() } }
    @Published var mirrorSystemNotifications: Bool { didSet { save() } }
    @Published var showVolumeHUD: Bool { didSet { save() } }
    @Published var showBattery: Bool { didSet { save() } }
    @Published var showCalendar: Bool { didSet { save() } }
    @Published var showOutputDevice: Bool { didSet { save() } }
    @Published var hoverToExpand: Bool { didSet { save() } }
    @Published var playSounds: Bool { didSet { save() } }
    @Published var forceSimulatedNotch: Bool { didSet { save() } }
    @Published var extraWidth: Double { didSet { save() } }
    @Published var notchInset: Double { didSet { save() } }
    @Published var swipeToCycle: Bool { didSet { save() } }

    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        // v2: default "lebar tambahan" dikembalikan ke 0 supaya collapsed pas dengan notch.
        if d.integer(forKey: "settingsVersion") < 2 {
            d.set(0, forKey: "extraWidth")
            d.set(2, forKey: "settingsVersion")
        }
        showNowPlaying = settingBool(d, "showNowPlaying", true)
        showShelf = settingBool(d, "showShelf", true)
        showNotifications = settingBool(d, "showNotifications", true)
        mirrorSystemNotifications = settingBool(d, "mirrorSystemNotifications", false)
        showVolumeHUD = settingBool(d, "showVolumeHUD", true)
        showBattery = settingBool(d, "showBattery", true)
        showCalendar = settingBool(d, "showCalendar", true)
        showOutputDevice = settingBool(d, "showOutputDevice", true)
        hoverToExpand = settingBool(d, "hoverToExpand", true)
        playSounds = settingBool(d, "playSounds", true)
        forceSimulatedNotch = settingBool(d, "forceSimulatedNotch", false)
        extraWidth = settingDouble(d, "extraWidth", 46)
        notchInset = settingDouble(d, "notchInset", 0)
        swipeToCycle = settingBool(d, "swipeToCycle", true)
    }

    private func save() {
        defaults.set(showNowPlaying, forKey: "showNowPlaying")
        defaults.set(showShelf, forKey: "showShelf")
        defaults.set(showNotifications, forKey: "showNotifications")
        defaults.set(mirrorSystemNotifications, forKey: "mirrorSystemNotifications")
        defaults.set(showVolumeHUD, forKey: "showVolumeHUD")
        defaults.set(showBattery, forKey: "showBattery")
        defaults.set(showCalendar, forKey: "showCalendar")
        defaults.set(showOutputDevice, forKey: "showOutputDevice")
        defaults.set(hoverToExpand, forKey: "hoverToExpand")
        defaults.set(playSounds, forKey: "playSounds")
        defaults.set(forceSimulatedNotch, forKey: "forceSimulatedNotch")
        defaults.set(extraWidth, forKey: "extraWidth")
        defaults.set(notchInset, forKey: "notchInset")
        defaults.set(swipeToCycle, forKey: "swipeToCycle")
    }
}

// MARK: - Model data

struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var app: String          // "Music" atau "Spotify"
    var known: Bool          // false bila tidak ada media/akses ditolak
    var denial: Bool = false // true bila otomasi ditolak TCC
}

struct VolumeInfo: Equatable {
    var level: Float = 0
    var muted: Bool = false
    var available: Bool = false
}

struct BatteryInfo: Equatable {
    var percent: Int = 0
    var charging: Bool = false
    var onAC: Bool = false
    var minutesRemaining: Int?
    var available: Bool = false
}

struct AgendaItem: Equatable {
    var title: String
    var start: Date
    var calendar: String
    var isAllDay: Bool = false
}

struct OutputDeviceInfo: Equatable {
    var name: String = ""
    var isBluetooth: Bool = false
    var isAirPodsLike: Bool = false
}

struct ConnectivityInfo: Equatable {
    var wifi: Bool = false
    var bluetooth: Bool = false
    var bluetoothKnown: Bool = false
    var available: Bool = false
}

struct AudioOutputDevice: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let isBluetooth: Bool
    let isDefault: Bool
}

struct Activity: Equatable {
    var label: String
    var total: TimeInterval
    var remaining: TimeInterval
    var startedAt: Date
    /// Saat dijeda, sisa waktu dibekukan di sini (detik).
    var pausedRemaining: TimeInterval? = nil
    var isPaused: Bool { pausedRemaining != nil }
    var progress: Double { total > 0 ? max(0, min(1, remaining / total)) : 0 }
}

/// Isi jam digital di modul Aktivitas sebelum timer dimulai.
struct TimerDraft: Equatable {
    var hours = 0
    var minutes = 5
    var seconds = 0

    var totalSeconds: Int { hours * 3600 + minutes * 60 + seconds }
    var isZero: Bool { totalSeconds == 0 }

    mutating func bump(_ unit: Unit, by delta: Int) {
        switch unit {
        case .hours: hours = ((hours + delta) % 24 + 24) % 24
        case .minutes: minutes = ((minutes + delta) % 60 + 60) % 60
        case .seconds: seconds = ((seconds + delta) % 60 + 60) % 60
        }
    }

    enum Unit { case hours, minutes, seconds }
}

enum HUDKind: Equatable { case volume, mute, battery, charging, onAC }

extension HUDKind {
    /// Status daya punya tiga nuansa: mengisi, tersambung tapi tidak mengisi, atau lepas adaptor.
    var isBatteryFamily: Bool { self == .battery || self == .charging || self == .onAC }

    var caption: String {
        switch self {
        case .charging: return "Mengisi daya"
        case .onAC: return "Tersambung adaptor"
        case .battery: return "Ga lagi ngecas cok"
        case .mute: return "Mute"
        case .volume: return "Volume"
        }
    }
}

struct HUDState: Equatable {
    var kind: HUDKind
    var value: Float
    var until: Date
}

// MARK: - State utama

final class IslandState: ObservableObject {

    let settings = IslandSettings()

    @Published var isExpanded = false
    /// Kursor sedang di atas pill. Dipakai hanya untuk efek visual (shadow/scale),
    /// bukan untuk memutuskan buka-tutup — itu tugas HoverMonitor di AppDelegate.
    @Published var hovering = false
    @Published var pinned = false
    @Published var module: IslandModule = .nowPlaying
    @Published var nowPlaying = NowPlayingInfo(title: "", artist: "", isPlaying: false, app: "", known: false)
    @Published var volume = VolumeInfo()
    @Published var battery = BatteryInfo()
    @Published var nextEvent: AgendaItem?
    @Published var shelfItems: [ShelfItem] = []
    let notifications = IslandNotificationStore()
    @Published var device = OutputDeviceInfo()
    @Published var outputDevices: [AudioOutputDevice] = []
    @Published var connectivity = ConnectivityInfo()
    @Published var activity: Activity? {
        didSet { onLayoutChange?(true) }
    }
    @Published var hud: HUDState?
    /// Isi jam digital modul Aktivitas (jam/menit/detik) sebelum dimulai.
    @Published var timerDraft = TimerDraft()

    /// Ada konten di zona kiri pill? Kalau tidak, klaster status kembali ke tengah.
    var hasCollapsedLeading: Bool {
        if activity != nil { return true }
        if settings.showNowPlaying && nowPlaying.known { return true }
        if let item = shelfItems.first, Date().timeIntervalSince(item.addedAt) < 300 { return true }
        return false
    }

    var onLayoutChange: ((Bool) -> Void)?
    private var hudToken = 0

    /// Salinan yang di-publish dari store notifikasi. Store-nya sendiri bukan ObservableObject,
    /// supaya tidak ada penerusan objectWillChange (penyebab "Publishing changes from within
    /// view updates" dan re-entrancy SwiftUI).
    @Published var notificationItems: [IslandNotification] = []
    @Published var activeNotification: IslandNotification?

    init() {
        notifications.onChange = { [weak self] in
            guard let self else { return }
            self.notificationItems = self.notifications.items
            self.activeNotification = self.notifications.active
        }
    }

    func showHUD(_ kind: HUDKind, value: Float) {
        hudToken += 1
        let token = hudToken
        hud = HUDState(kind: kind, value: value, until: Date().addingTimeInterval(1.4))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.hudToken == token else { return }
            self.hud = nil
        }
    }

    var availableModules: [IslandModule] {
        var list: [IslandModule] = []
        if settings.showNowPlaying { list.append(.nowPlaying) }
        if settings.showShelf { list.append(.shelf) }
        if settings.showNotifications { list.append(.notifications) }
        if settings.showVolumeHUD { list.append(.volume) }
        if settings.showBattery { list.append(.battery) }
        if settings.showCalendar { list.append(.calendar) }
        list.append(.activity)
        return list
    }

    func nextModule() -> IslandModule { nextModule(from: module) }
    func previousModule() -> IslandModule { previousModule(from: module) }

    func nextModule(from current: IslandModule) -> IslandModule {
        let list = availableModules
        guard !list.isEmpty else { return current }
        guard let idx = list.firstIndex(of: current) else { return list[0] }
        return list[(idx + 1) % list.count]
    }

    func previousModule(from current: IslandModule) -> IslandModule {
        let list = availableModules
        guard !list.isEmpty else { return current }
        guard let idx = list.firstIndex(of: current) else { return list[0] }
        return list[(idx - 1 + list.count) % list.count]
    }

    /// Ringkasan state untuk verifikasi otomatis (dipakai kanal debug & selftest).
    func snapshot() -> [String: Any] {
        var out: [String: Any] = [
            "expanded": isExpanded,
            "pinned": pinned,
            "module": module.rawValue,
            "availableModules": availableModules.map { $0.rawValue },
            "hud": hud.map { ["kind": "\($0.kind)", "value": Double($0.value)] } as Any,
            "hasActivity": activity != nil,
            "activityPaused": activity?.isPaused ?? false,
            "activityRemaining": activity.map { Int($0.pausedRemaining ?? max(0, $0.startedAt.addingTimeInterval($0.total).timeIntervalSinceNow)) } ?? -1,
            "nowPlayingKnown": nowPlaying.known,
            "nowPlayingTitle": nowPlaying.title,
            "volumeAvailable": volume.available,
            "volumeLevel": Double(volume.level),
            "volumeMuted": volume.muted,
            "batteryAvailable": battery.available,
            "batteryPercent": battery.percent,
            "batteryCharging": battery.charging,
            "batteryOnAC": battery.onAC,
            "outputDevice": device.name,
            "outputDeviceBluetooth": device.isBluetooth,
            "nextEvent": nextEvent.map { $0.title } as Any,
            "shelfCount": shelfItems.count,
            "outputDevices": outputDevices.map { "\($0.name)\($0.isDefault ? " (default)" : "")" },
            "connectivity": ["wifi": connectivity.wifi,
                             "bluetooth": connectivity.bluetooth,
                             "bluetoothKnown": connectivity.bluetoothKnown],
            "notificationCount": notifications.items.count,
            "activeNotification": notifications.active.map { "\($0.source): \($0.title)" } as Any
        ]
        if let panel = NSApp.windows.first {
            let frame = panel.frame
            out["panelFrame"] = ["x": frame.origin.x, "y": frame.origin.y,
                                 "width": frame.size.width, "height": frame.size.height]
        }
        return out
    }

    func cycleModule() {
        let list = availableModules
        guard !list.isEmpty else { return }
        if let idx = list.firstIndex(of: module) {
            module = list[(idx + 1) % list.count]
        } else {
            module = list[0]
        }
    }

    func cycleModulePrevious() {
        let list = availableModules
        guard !list.isEmpty else { return }
        if let idx = list.firstIndex(of: module) {
            module = list[(idx - 1 + list.count) % list.count]
        } else {
            module = list[0]
        }
    }

    func setExpanded(_ value: Bool, animated: Bool = true) {
        guard isExpanded != value else { return }
        isExpanded = value
        onLayoutChange?(animated)
        if value, module == .nowPlaying, !nowPlaying.known {
            module = availableModules.first ?? .nowPlaying
        }
    }
}

/// Gerbang "satu aksi per gestur".
///
/// Satu gestur trackpad memicu beberapa event sekaligus: `.swipe` dan deretan `.scrollWheel`
/// (termasuk ekor momentum). Tanpa gerbang ini, satu geseran bisa memindahkan dua modul.
/// Logikanya dipisah ke tipe sendiri supaya bisa diuji otomatis.
struct GestureGate {
    /// Jeda minimum antar aksi (detik).
    var minimumInterval: TimeInterval = 0.45
    /// Berapa lama kunci ditahan setelah satu aksi dijalankan (detik).
    var holdAfterAction: TimeInterval = 0.7

    private var lockedUntil: Date = .distantPast

    /// Boleh menjalankan aksi sekarang?
    func allowsAction(at now: Date) -> Bool {
        now >= lockedUntil
    }

    /// Catat satu aksi. Mengembalikan `false` bila masih terkunci (aksi harus diabaikan).
    mutating func registerAction(at now: Date) -> Bool {
        guard allowsAction(at: now) else { return false }
        lockedUntil = now.addingTimeInterval(max(minimumInterval, holdAfterAction))
        return true
    }

    /// Buka kunci lebih awal (mis. saat event gestur menyatakan `.ended`).
    mutating func release() {
        lockedUntil = .distantPast
    }
}

// MARK: - Animasi bersama (biar transisi konsisten, tidak kaku)

enum IslandAnim {
    /// Untuk perubahan ukuran/posisi di dalam island.
    static let panel = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// Untuk konten yang berganti (modul, HUD, pill notifikasi).
    static let content = Animation.spring(response: 0.30, dampingFraction: 0.88)
    /// Untuk efek kecil (hover, warna).
    static let micro = Animation.easeInOut(duration: 0.18)
    /// Durasi animasi jendela AppKit saat melebar/menyempit.
    static let windowDuration: TimeInterval = 0.30
}

// MARK: - Geometri panel (menyesuaikan notch layar)

/// Konstanta tata letak yang dipakai bersama oleh view, dokumentasi, dan pengujian.
/// Aturan penting: **tidak boleh ada elemen berlebar berubah** sebelum tombol navigasi,
/// supaya posisi tombol tidak bergeser saat modul berganti.
enum IslandLayout {
    static let headerTitleWidth: CGFloat = 104
    static let stepButtonSize = NSSize(width: 32, height: 24)
    static let moduleDotSize: CGFloat = 7
    static let moduleDotPadding: CGFloat = 6
    static let horizontalPadding: CGFloat = 14
    static let rowSpacing: CGFloat = 5

    /// Lebar panel saat expanded (dipakai juga oleh perhitungan posisi tombol).
    static func expandedWidth(settings: IslandSettings) -> CGFloat {
        420 + CGFloat(settings.extraWidth)
    }

    /// Posisi X (relatif kiri panel) untuk kedua tombol navigasi pada baris footer.
    /// Tidak menerima parameter modul — inilah alasan posisinya tidak pernah berubah.
    static func stepButtonOrigins(settings: IslandSettings) -> (previous: CGFloat, next: CGFloat) {
        let rightEdge = expandedWidth(settings: settings) - horizontalPadding
        let next = rightEdge - stepButtonSize.width
        let previous = next - stepButtonSize.width
        return (previous, next)
    }
}

enum IslandGeometry {

    enum Mode { case collapsed, expanded }

    /// Tinggi area konten di bawah notch.
    static let collapsedContentHeight: CGFloat = 20
    static let expandedContentHeight: CGFloat = 156
    /// Tonjolan hitam di kiri/kanan notch saat collapsed ("telinga"), supaya island
    /// menyatu dengan notch alih-alih menggantung di bawahnya.
    static let earWidth: CGFloat = 10
    /// Jarak dari tepi atas layar saat tidak ada notch nyata (island mengambang).
    static let floatingGap: CGFloat = 6

    static var targetScreen: NSScreen? {
        // Layar utama; bila tidak ada notch, pakai layar ber-notch pertama bila ada.
        if let main = NSScreen.main, main.hasNotch { return main }
        return NSScreen.screens.first(where: { $0.hasNotch }) ?? NSScreen.main
    }

    static func notchHeight(screen: NSScreen?, settings: IslandSettings) -> CGFloat {
        guard let screen else { return 0 }
        if settings.forceSimulatedNotch { return 32 }
        return screen.safeAreaInsets.top
    }

    static func hasRealNotch(screen: NSScreen?, settings: IslandSettings) -> Bool {
        notchHeight(screen: screen, settings: settings) > 0
    }

    /// Offset konten dari tepi atas jendela: setinggi notch, atau celah kecil saat mengambang.
    static func topInset(screen: NSScreen?, settings: IslandSettings) -> CGFloat {
        let notch = notchHeight(screen: screen, settings: settings)
        return notch > 0 ? notch : floatingGap
    }

    static func size(for mode: Mode, settings: IslandSettings) -> NSSize {
        let screen = targetScreen
        let content = mode == .collapsed ? collapsedContentHeight : expandedContentHeight
        let width: CGFloat
        if mode == .collapsed {
            let notchWidth = screen?.notchWidth ?? 0
            width = notchWidth > 0
                ? notchWidth + earWidth * 2 + CGFloat(settings.extraWidth)
                : 150 + CGFloat(settings.extraWidth)
        } else {
            width = 420 + CGFloat(settings.extraWidth)
        }
        let height = topInset(screen: screen, settings: settings) + content
        return NSSize(width: width.rounded(), height: height.rounded())
    }

    static func frame(for mode: Mode, settings: IslandSettings) -> NSRect {
        let screen = targetScreen ?? NSScreen.main!
        let size = self.size(for: mode, settings: settings)
        let visible = screen.frame
        let x = (visible.midX - size.width / 2).rounded()
        let y = (visible.maxY - size.height).rounded()
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

extension NSScreen {
    var hasNotch: Bool { safeAreaInsets.top > 0 }

    var notchWidth: CGFloat {
        guard hasNotch else { return 0 }
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return 180 }
        return max(0, frame.width - left.width - right.width)
    }
}

// MARK: - Panel mengambang

final class IslandPanel: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
}
