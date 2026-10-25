import AppKit
import ApplicationServices
import Foundation

// MARK: - Model notifikasi island

struct IslandNotification: Identifiable, Equatable {
    let id: String
    let source: String        // nama aplikasi atau "Islet"
    let title: String
    let body: String
    let symbol: String        // SF Symbol
    let date: Date
    var mirrored: Bool = false   // berasal dari cermin Notification Center (izin Accessibility)

    static func == (lhs: IslandNotification, rhs: IslandNotification) -> Bool { lhs.id == rhs.id }
}

// MARK: - Penyimpanan + penjadwalan tampil

final class IslandNotificationStore {

    private(set) var items: [IslandNotification] = []
    /// Notifikasi yang sedang tampil sebagai pill di island.
    private(set) var active: IslandNotification?
    /// Dipanggil setiap daftar/aktif berubah. Pemilik (IslandState) yang mem-publish ulang,
    /// jadi tidak ada ObservableObject bersarang — pola itu memicu
    /// "Publishing changes from within view updates" dan membuat SwiftUI re-entrant.
    var onChange: (() -> Void)?

    let limit = 12
    var autoDismiss: TimeInterval = 5.0
    var onPost: ((IslandNotification) -> Void)?

    private var dismissWork: DispatchWorkItem?
    private var recentKeys: [String: Date] = [:]
    private var counter = 0

    /// Menaruh notifikasi baru. Notifikasi identik dalam 3 detik terakhir diabaikan (anti-spam).
    @discardableResult
    func post(source: String, title: String, body: String, symbol: String, mirrored: Bool = false) -> IslandNotification? {
        let key = "\(source)|\(title)|\(body)"
        let now = Date()
        if let last = recentKeys[key], now.timeIntervalSince(last) < 3 { return nil }
        recentKeys[key] = now
        recentKeys = recentKeys.filter { now.timeIntervalSince($0.value) < 30 }

        counter += 1
        let item = IslandNotification(id: "\(Int(now.timeIntervalSince1970))-\(counter)",
                                      source: source,
                                      title: title,
                                      body: body,
                                      symbol: symbol,
                                      date: now,
                                      mirrored: mirrored)
        items.insert(item, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
        show(item)
        onPost?(item)
        return item
    }

    func show(_ item: IslandNotification) {
        active = item
        onChange?()
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissActive() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismiss, execute: work)
    }

    func dismissActive() {
        dismissWork?.cancel()
        dismissWork = nil
        guard active != nil else { return }
        active = nil
        onChange?()
    }

    func clear() {
        dismissActive()
        guard !items.isEmpty else { return }
        items.removeAll()
        recentKeys.removeAll()
        onChange?()
    }
}

// MARK: - Kanal lokal (aplikasi/script lain boleh mengirim)

/// Kanal `DistributedNotificationCenter` bernama `com.rafael.islet.notify`.
/// userInfo: title (wajib), body, source, symbol, sound ("0"/"1").
enum IslandNotificationChannel {

    static let name = Notification.Name("com.rafael.islet.notify")

    static func listen(_ handler: @escaping (_ title: String, _ body: String, _ source: String, _ symbol: String) -> Void) {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { note in
            let info = note.userInfo ?? [:]
            let title = (info["title"] as? String) ?? (note.object as? String) ?? "Notifikasi"
            let body = (info["body"] as? String) ?? ""
            let source = (info["source"] as? String) ?? "Aplikasi"
            let symbol = (info["symbol"] as? String) ?? "bell.fill"
            handler(title, body, source, symbol)
        }
    }
}

// MARK: - Cermin Notification Center (opsional, butuh izin Accessibility)

/// Membaca banner Notification Center macOS lewat Accessibility API.
/// Ini satu-satunya jalur publik untuk "menangkap" notifikasi aplikasi lain, dan sifatnya rapuh:
/// struktur UI Notification Center bisa berubah antar versi macOS.
/// Semua kegagalan dilaporkan sebagai status, tidak pernah membuat aplikasi berhenti.
final class AccessibilityNotificationMirror {

    private(set) var status: String = "belum dimulai"
    private(set) var capturedCount = 0
    private(set) var lastRawDump: [String] = []
    var onBanner: ((_ app: String, _ title: String, _ body: String) -> Void)?

    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var seenTitles: [String: Date] = [:]

    static var hasPermission: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard Self.hasPermission else {
            status = "izin Accessibility belum diberikan"
            return
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.notificationcenterui"
        }) else {
            status = "NotificationCenter (com.apple.notificationcenterui) tidak berjalan"
            return
        }
        observedPID = app.processIdentifier

        var obs: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let monitor = Unmanaged<AccessibilityNotificationMirror>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handleWindowCreated(element)
        }
        let created = AXObserverCreate(observedPID, callback, &obs)
        guard created == .success, let obs else {
            status = "AXObserverCreate gagal (kode \(created.rawValue))"
            return
        }
        let appElement = AXUIElementCreateApplication(observedPID)
        let added = AXObserverAddNotification(obs, appElement, kAXWindowCreatedNotification as CFString,
                                              Unmanaged.passUnretained(self).toOpaque())
        guard added == .success else {
            status = "AXObserverAddNotification gagal (kode \(added.rawValue))"
            return
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        status = "aktif (pid \(observedPID))"
    }

    private func handleWindowCreated(_ element: AXUIElement) {
        // Beri waktu singkat: isi banner biasanya baru terisi setelah window muncul.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let texts = self.collectTexts(from: element)
            self.lastRawDump = texts
            guard texts.count >= 2 else { return }

            let app = texts[0]
            let title = texts.count > 1 ? texts[1] : ""
            let body = texts.count > 2 ? texts[2...].joined(separator: " ") : ""
            let key = "\(app)|\(title)|\(body)"
            let now = Date()
            if let last = self.seenTitles[key], now.timeIntervalSince(last) < 4 { return }
            self.seenTitles[key] = now
            self.seenTitles = self.seenTitles.filter { now.timeIntervalSince($0.value) < 30 }

            self.capturedCount += 1
            self.onBanner?(app, title, body)
        }
    }

    /// Menelusuri pohon Accessibility dan mengumpulkan teks yang terlihat.
    private func collectTexts(from element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < 5 else { return [] }
        var out: [String] = []

        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
            if let value = copyAttribute(element, attribute as CFString) as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { out.append(trimmed) }
            }
        }
        if let children = copyAttribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] {
            for child in children {
                out.append(contentsOf: collectTexts(from: child, depth: depth + 1))
            }
        }
        return out
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        return result == .success ? value : nil
    }
}
