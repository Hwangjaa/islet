import AppKit
import Foundation

/// Jembatan ke MediaRemote — framework sistem yang dipakai macOS sendiri untuk "Now Playing".
///
/// Catatan penting dan jujur: ini **bukan** API publik. Ia dimuat secara dinamis dan setiap
/// pemakaian dijaga: kalau simbolnya tidak ada atau berubah, `available` menjadi false dan
/// pemanggil jatuh ke jalur AppleScript (Music/Spotify). Tanpa MediaRemote, playback dari
/// browser tidak bisa dibaca sama sekali — macOS tidak menyediakan jalur publik untuk itu.
final class MediaRemoteEngine {

    typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    typealias GetPlayingFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool
    typealias GetPIDFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void

    static let shared = MediaRemoteEngine()

    private(set) var available = false
    private var getInfo: GetInfoFn?
    private var getPlaying: GetPlayingFn?
    private var send: SendCommandFn?
    private var getPID: GetPIDFn?
    private let queue = DispatchQueue(label: "islet.mediaremote", qos: .utility)
    private let pidQueue = DispatchQueue(label: "islet.mediaremote.pid", qos: .utility)

    // Nilai perintah MediaRemote (dipakai macOS sendiri).
    private enum Command: Int32 {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else { return }
        if let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getInfo = unsafeBitCast(symbol, to: GetInfoFn.self)
        }
        if let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            getPlaying = unsafeBitCast(symbol, to: GetPlayingFn.self)
        }
        if let symbol = dlsym(handle, "MRMediaRemoteSendCommand") {
            send = unsafeBitCast(symbol, to: SendCommandFn.self)
        }
        if let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") {
            getPID = unsafeBitCast(symbol, to: GetPIDFn.self)
        }
        available = (getInfo != nil)
    }

    struct NowPlaying {
        var title: String
        var artist: String
        var isPlaying: Bool
        var app: String
    }

    /// Membaca now-playing sistem (mencakup browser: Safari, Chrome, Brave, Spotify, Music, …).
    /// Completion SELALU dipanggil di main thread — kalau tidak, SwiftUI akan melaporkan
    /// "Publishing changes from background threads".
    func read(completion: @escaping (NowPlaying?) -> Void) {
        let finish: (NowPlaying?) -> Void = { value in
            if Thread.isMainThread {
                completion(value)
            } else {
                DispatchQueue.main.async { completion(value) }
            }
        }
        guard let getInfo else {
            finish(nil)
            return
        }
        getInfo(queue) { info in
            guard let info = info as? [String: Any] else {
                finish(nil)
                return
            }
            let title = (info["kMRMediaRemoteNowPlayingInfoTitle"] as? String) ?? ""
            let artist = (info["kMRMediaRemoteNowPlayingInfoArtist"] as? String) ?? ""
            let rate = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double) ?? 0
            guard !title.isEmpty else {
                finish(nil)
                return
            }
            self.appName { app in
                finish(NowPlaying(title: title,
                                  artist: artist,
                                  isPlaying: rate > 0.01,
                                  app: app.isEmpty ? "Media" : app))
            }
        }
    }

    private func appName(_ completion: @escaping (String) -> Void) {
        guard let getPID else {
            completion("")
            return
        }
        getPID(pidQueue) { pid in
            guard pid > 0,
                  let app = NSRunningApplication(processIdentifier: pid_t(pid)) else {
                completion("")
                return
            }
            completion(app.localizedName ?? "")
        }
    }

    func togglePlayPause() { _ = send?(Command.togglePlayPause.rawValue, nil) }
    func nextTrack() { _ = send?(Command.nextTrack.rawValue, nil) }
    func previousTrack() { _ = send?(Command.previousTrack.rawValue, nil) }
}
