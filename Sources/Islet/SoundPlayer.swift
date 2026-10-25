import AppKit

// Suara memakai bunyi sistem bawaan macOS (NSSound named:) — tidak memakai berkas
// audio milik aplikasi lain.

final class SoundPlayer {

    static let shared = SoundPlayer()

    enum Cue {
        case activityStart
        case activityEnd
        case lowBattery
        case toggle
    }

    private init() {}

    private func enabled() -> Bool {
        UserDefaults.standard.object(forKey: "playSounds") as? Bool ?? true
    }

    func play(_ cue: Cue) {
        guard enabled() else { return }
        let name: String
        switch cue {
        case .activityStart: name = "Pop"
        case .activityEnd: name = "Glass"
        case .lowBattery: name = "Funk"
        case .toggle: name = "Tink"
        }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
