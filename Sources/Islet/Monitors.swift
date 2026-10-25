import AppKit
import CoreAudio
import CoreBluetooth
import CoreWLAN
import EventKit
import IOKit.ps

// MARK: - Volume sistem (CoreAudio, API publik)

final class VolumeMonitor {
    private let state: IslandState
    var enabled = true { didSet { if !enabled { state.volume.available = false } else { poll() } } }

    private var timer: Timer?
    private var device = AudioDeviceID(0)
    private var lastLevel: Float?

    init(state: IslandState) { self.state = state }

    func start() {
        device = Self.defaultOutputDevice()
        let t = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    private func poll() {
        guard enabled else { return }
        if device == 0 || !Self.deviceIsAlive(device) { device = Self.defaultOutputDevice() }
        guard let reading = Self.read(device) else {
            state.volume.available = false
            return
        }
        var info = VolumeInfo(level: reading.level, muted: reading.muted, available: true)
        if reading.muted { info.level = 0 }
        let changed = lastLevel.map { abs($0 - reading.level) > 0.01 } ?? false
        lastLevel = reading.level
        state.volume = info
        if changed, enabled {
            state.showHUD(reading.muted ? .mute : .volume, value: reading.muted ? 0 : reading.level)
        }
    }

    func setVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        Self.write(device, level: clamped)
        if clamped > 0 { Self.writeMute(device, muted: false) }
        lastLevel = clamped
        state.volume = VolumeInfo(level: clamped, muted: false, available: true)
        state.showHUD(.volume, value: clamped)
    }

    func toggleMute() {
        let muted = state.volume.muted
        Self.writeMute(device, muted: !muted)
        state.volume.muted = !muted
        state.showHUD(!muted ? .mute : .volume, value: !muted ? 0 : state.volume.level)
    }

    // MARK: CoreAudio helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : 0
    }

    /// Pembacaan ringkas untuk verifikasi/vselftest: volume perangkat keluaran default.
    static func currentOutputVolume() -> (level: Float, muted: Bool)? {
        let device = defaultOutputDevice()
        guard device != 0 else { return nil }
        return read(device)
    }

    /// Daftar perangkat keluaran yang bisa dipilih (untuk modul Volume).
    static func outputDeviceList() -> [AudioOutputDevice] {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return []
        }
        let current = defaultOutputDevice()
        return ids.compactMap { id in
            guard hasOutput(id), let name = deviceName(id) else { return nil }
            return AudioOutputDevice(id: id,
                                     name: name,
                                     isBluetooth: isBluetooth(id),
                                     isDefault: id == current)
        }
        .sorted { $0.isDefault && !$1.isDefault }
    }

    static func hasOutput(_ device: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    static func setDefaultOutputDevice(_ device: AudioDeviceID) {
        var value = device
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                       UInt32(MemoryLayout<AudioDeviceID>.size), &value)
    }

    static func deviceIsAlive(_ device: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyDeviceIsAlive)
        var alive = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &alive)
        return status == noErr && alive == 1
    }

    static func deviceName(_ device: AudioDeviceID) -> String? {
        var addr = address(kAudioObjectPropertyName)
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr -> OSStatus in
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, UnsafeMutableRawPointer(ptr))
        }
        return status == noErr ? (name as String) : nil
    }

    static func isBluetooth(_ device: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &transport)
        guard status == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func read(_ device: AudioDeviceID) -> (level: Float, muted: Bool)? {
        guard device != 0 else { return nil }
        var volAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var level = Float(0)
        var size = UInt32(MemoryLayout<Float>.size)
        var status = AudioObjectGetPropertyData(device, &volAddr, 0, nil, &size, &level)
        if status != noErr {
            // Sebagian perangkat hanya punya volume per-kanal.
            let left = readChannel(device, 1)
            let right = readChannel(device, 2)
            switch (left, right) {
            case let (l?, r?): level = (l + r) / 2; status = noErr
            case let (l?, nil): level = l; status = noErr
            case let (nil, r?): level = r; status = noErr
            default: break
            }
        }
        guard status == noErr else { return nil }
        var muteAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                  mScope: kAudioDevicePropertyScopeOutput,
                                                  mElement: kAudioObjectPropertyElementMain)
        var mute = UInt32(0)
        var msize = UInt32(MemoryLayout<UInt32>.size)
        let mstatus = AudioObjectGetPropertyData(device, &muteAddr, 0, nil, &msize, &mute)
        return (level, mstatus == noErr && mute == 1)
    }

    private static func readChannel(_ device: AudioDeviceID, _ channel: UInt32) -> Float? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: channel)
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var level = Float(0)
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &level)
        return status == noErr ? level : nil
    }

    private static func write(_ device: AudioDeviceID, level: Float) {
        guard device != 0 else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var value = level
        let size = UInt32(MemoryLayout<Float>.size)
        if AudioObjectHasProperty(device, &addr) {
            let status = AudioObjectSetPropertyData(device, &addr, 0, nil, size, &value)
            if status == noErr { return }
        }
        for channel: UInt32 in [1, 2] {
            var chAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                    mScope: kAudioDevicePropertyScopeOutput,
                                                    mElement: channel)
            if AudioObjectHasProperty(device, &chAddr) {
                _ = AudioObjectSetPropertyData(device, &chAddr, 0, nil, size, &value)
            }
        }
    }

    private static func writeMute(_ device: AudioDeviceID, muted: Bool) {
        guard device != 0 else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &addr) else { return }
        var value: UInt32 = muted ? 1 : 0
        _ = AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

// MARK: - Baterai (IOKit power sources, API publik)

final class BatteryMonitor {
    private let state: IslandState
    var enabled = true { didSet { if enabled { poll(announce: false) } else { state.battery.available = false } } }

    private var timer: Timer?
    private var runLoopSource: CFRunLoopSource?
    private var lastPercent: Int?
    private var lastCharging: Bool?
    private var lastOnAC: Bool?
    private var warnedLow = false

    /// Penghitung untuk verifikasi: bukti jalur notifikasi IOKit benar-benar dipakai.
    private(set) var pollCount = 0
    private(set) var notificationCount = 0
    private(set) var changeCount = 0
    private(set) var lastChangeAt: Date?

    func debugInfo() -> [String: Any] {
        ["polls": pollCount,
         "ioKitNotifications": notificationCount,
         "powerChanges": changeCount,
         "lastChangeSecondsAgo": lastChangeAt.map { Int(Date().timeIntervalSince($0)) } as Any,
         "charging": lastCharging as Any,
         "onAC": lastOnAC as Any]
    }

    init(state: IslandState) { self.state = state }

    func start() {
        // Notifikasi IOKit: adaptor dicabut/dicolok langsung terdeteksi, tidak menunggu polling.
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { monitor.poll(announce: true) }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?
            .takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }

        // Polling cadangan untuk persentase dan sisa waktu.
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll(announce: false) }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll(announce: false)
    }

    private func poll(announce: Bool) {
        guard enabled else { state.battery.available = false; return }
        pollCount += 1
        if announce { notificationCount += 1 }
        guard let info = Self.snapshot() else { state.battery.available = false; return }

        let powerChanged = (lastCharging != nil && lastCharging != info.charging)
            || (lastOnAC != nil && lastOnAC != info.onAC)

        if powerChanged { changeCount += 1; lastChangeAt = Date() }
        if announce || powerChanged {
            let kind: HUDKind = info.charging ? .charging : (info.onAC ? .onAC : .battery)
            state.showHUD(kind, value: Float(info.percent) / 100)
        }
        if powerChanged {
            changeCount += 1
            lastChangeAt = Date()
            // Sengaja tidak dikirim sebagai notifikasi island: status daya sudah punya HUD sendiri.
            SoundPlayer.shared.play(.toggle)
        }
        if let last = lastPercent, last != info.percent, info.percent <= 20, !info.charging, !warnedLow {
            warnedLow = true
            SoundPlayer.shared.play(.lowBattery)
        }
        if info.percent > 25 { warnedLow = false }

        lastPercent = info.percent
        lastCharging = info.charging
        lastOnAC = info.onAC
        state.battery = info
    }

    static func snapshot() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard (desc[kIOPSIsPresentKey] as? Bool) ?? true else { continue }
            guard (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
            let onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let tte = desc[kIOPSTimeToEmptyKey] as? Int

            var info = BatteryInfo()
            info.percent = maxCap > 0 ? Int((Double(current) / Double(maxCap) * 100).rounded()) : current
            info.charging = charging
            info.onAC = onAC
            info.minutesRemaining = (tte ?? 0) > 0 ? tte : nil
            info.available = true
            return info
        }
        return nil
    }
}

// MARK: - Now Playing (Apple Events ke Music/Spotify — API publik, seperti entitlement Alcove)

final class NowPlayingMonitor {
    private let state: IslandState
    var enabled = true { didSet { if enabled { poll() } else { state.nowPlaying.known = false } } }

    private var timer: Timer?
    private var activeApp: String?

    private static let musicBundleID = "com.apple.Music"
    private static let spotifyBundleID = "com.spotify.client"

    init(state: IslandState) { self.state = state }

    func start() {
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    private func runningTarget() -> String? {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Self.musicBundleID).isEmpty == false { return "Music" }
        if NSRunningApplication.runningApplications(withBundleIdentifier: Self.spotifyBundleID).isEmpty == false { return "Spotify" }
        return nil
    }

    private let appleQueue = DispatchQueue(label: "islet.nowplaying.applescript", qos: .utility)
    private var pollInFlight = false
    private var lastFallback = Date.distantPast
    private var lastPollStart = Date()

    private func poll() {
        guard enabled else { return }
        // Jaring pengaman: kalau callback MediaRemote tidak pernah kembali, jangan biarkan
        // polling mati selamanya.
        if pollInFlight, Date().timeIntervalSince(lastPollStart) > 8 { pollInFlight = false }
        guard !pollInFlight else { return }
        pollInFlight = true
        lastPollStart = Date()

        // Jalur utama: MediaRemote — satu-satunya cara melihat playback browser.
        if MediaRemoteEngine.shared.available {
            MediaRemoteEngine.shared.read { [weak self] info in
                guard let self else { return }
                self.pollInFlight = false
                if let info {
                    self.activeApp = info.app
                    self.state.nowPlaying = NowPlayingInfo(title: info.title,
                                                           artist: info.artist,
                                                           isPlaying: info.isPlaying,
                                                           app: info.app,
                                                           known: true)
                } else {
                    self.fallbackToAppleScript()
                }
            }
            return
        }
        fallbackToAppleScript()
    }

    /// AppleScript dijalankan di queue latar. Di main thread, panggilan ini bisa menggantung
    /// (mis. saat macOS menampilkan dialog izin Automation) dan aplikasi tampak "not responding".
    private func fallbackToAppleScript() {
        guard enabled else { pollInFlight = false; return }
        guard Date().timeIntervalSince(lastFallback) > 5 else {
            pollInFlight = false
            return
        }
        lastFallback = Date()

        guard let app = runningTarget() else {
            activeApp = nil
            state.nowPlaying = NowPlayingInfo(title: "", artist: "", isPlaying: false, app: "", known: false)
            pollInFlight = false
            return
        }
        activeApp = app

        appleQueue.async { [weak self] in
            guard let self else { return }
            let info = Self.appleScriptSnapshot(app: app)
            DispatchQueue.main.async {
                self.pollInFlight = false
                if let info {
                    self.state.nowPlaying = info
                } else {
                    self.state.nowPlaying = NowPlayingInfo(title: "", artist: "", isPlaying: false,
                                                           app: app, known: false, denial: true)
                }
            }
        }
    }

    private static func appleScriptSnapshot(app: String) -> NowPlayingInfo? {
        let script: String
        if app == "Music" {
            script = """
            tell application "Music"
                set st to ""
                try
                    set st to (player state as text)
                end try
                set t to ""
                set a to ""
                try
                    set t to (name of current track)
                    set a to (artist of current track)
                end try
                return t & "|||" & a & "|||" & st
            end tell
            """
        } else {
            script = """
            tell application "Spotify"
                set st to ""
                try
                    set st to (player state as text)
                end try
                set t to ""
                set a to ""
                try
                    set t to (name of current track)
                    set a to (artist of current track)
                end try
                return t & "|||" & a & "|||" & st
            end tell
            """
        }
        guard let result = run(script) else { return nil }
        let parts = result.components(separatedBy: "|||")
        let title = parts.count > 0 ? parts[0] : ""
        let artist = parts.count > 1 ? parts[1] : ""
        let playing = parts.count > 2 && parts[2].lowercased().contains("playing")
        return NowPlayingInfo(title: title, artist: artist, isPlaying: playing, app: app, known: !title.isEmpty)
    }

    func togglePlayPause() {
        if MediaRemoteEngine.shared.available { MediaRemoteEngine.shared.togglePlayPause(); refreshSoon(); return }
        command("playpause")
    }

    func nextTrack() {
        if MediaRemoteEngine.shared.available { MediaRemoteEngine.shared.nextTrack(); refreshSoon(); return }
        command("next track")
    }

    func previousTrack() {
        if MediaRemoteEngine.shared.available { MediaRemoteEngine.shared.previousTrack(); refreshSoon(); return }
        command("previous track")
    }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.poll() }
    }

    private func command(_ verb: String) {
        guard let app = activeApp ?? runningTarget() else { return }
        appleQueue.async {
            _ = Self.run("tell application \"\(app)\" to \(verb)")
        }
        refreshSoon()
    }

    private static func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return output.stringValue
    }
}

// MARK: - Kalender (EventKit)

final class CalendarMonitor {
    private let state: IslandState
    var enabled = true { didSet { if enabled { poll() } else { state.nextEvent = nil } } }

    private let store = EKEventStore()
    private var timer: Timer?
    private var authorized = false

    init(state: IslandState) { self.state = state }

    func start() {
        requestAccess()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func requestAccess() {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, _ in
                self?.authorized = granted
                DispatchQueue.main.async { self?.poll() }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                self?.authorized = granted
                DispatchQueue.main.async { self?.poll() }
            }
        }
    }

    private func poll() {
        guard enabled, authorized else { return }
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .hour, value: 18, to: now) else { return }
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-60), end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
        guard let next = events.first else {
            state.nextEvent = nil
            return
        }
        state.nextEvent = AgendaItem(title: next.title ?? "(tanpa judul)",
                                     start: next.startDate,
                                     calendar: next.calendar?.title ?? "")
    }
}

// MARK: - Konektivitas (Wi-Fi & Bluetooth) untuk ikon di notch

final class ConnectivityMonitor: NSObject, CBCentralManagerDelegate {
    private let state: IslandState
    var enabled = true { didSet { if enabled { publish() } } }

    private var central: CBCentralManager?
    private var timer: Timer?
    private var bluetoothOn = false
    private var bluetoothKnown = false

    init(state: IslandState) { self.state = state }

    func start() {
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.publish() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        publish()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothKnown = true
        bluetoothOn = (central.state == .poweredOn)
        publish()
    }

    private func publish() {
        guard enabled else { return }
        let wifiOn = CWWiFiClient.shared().interface()?.powerOn() ?? false
        state.connectivity = ConnectivityInfo(wifi: wifiOn,
                                              bluetooth: bluetoothOn,
                                              bluetoothKnown: bluetoothKnown,
                                              available: true)
    }
}

// MARK: - Perangkat audio keluaran (CoreAudio, termasuk deteksi Bluetooth)

final class OutputDeviceMonitor {
    private let state: IslandState
    var enabled = true { didSet { if !enabled { state.device = OutputDeviceInfo() } else { poll() } } }

    private var timer: Timer?

    init(state: IslandState) { self.state = state }

    func start() {
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    private func poll() {
        guard enabled else { return }
        let device = VolumeMonitor.defaultOutputDevice()
        guard device != 0 else { state.device = OutputDeviceInfo(); return }
        let name = VolumeMonitor.deviceName(device) ?? ""
        let bt = VolumeMonitor.isBluetooth(device)
        let airpodsLike = name.localizedCaseInsensitiveContains("airpods")
            || name.localizedCaseInsensitiveContains("beats")
        state.device = OutputDeviceInfo(name: name, isBluetooth: bt, isAirPodsLike: airpodsLike)
        state.outputDevices = VolumeMonitor.outputDeviceList()
    }
}
