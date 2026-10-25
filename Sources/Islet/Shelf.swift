import AppKit
import CryptoKit
import Foundation

/// Satu tangkapan yang tersimpan di shelf.
struct ShelfItem: Identifiable, Equatable {
    let id: String            // sha256 dari data PNG
    let url: URL
    let addedAt: Date
    let pixelSize: NSSize

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool { lhs.id == rhs.id }
}

/// Menyimpan gambar yang masuk ke clipboard (termasuk hasil screenshot macOS) ke folder
/// lokal, lalu menyediakannya untuk ditampilkan di island dan di-drag keluar.
/// Tidak ada data yang dikirim ke jaringan.
final class ScreenshotShelf: ObservableObject {

    @Published private(set) var items: [ShelfItem] = []

    /// Folder penyimpanan: ~/Library/Application Support/Islet/Shelf
    let directory: URL

    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    private let limit = 20

    /// Dipanggil setiap kali ada item baru tersimpan (dipakai untuk "peek" di island).
    var onNewItem: ((ShelfItem) -> Void)?

    init(pasteboard: NSPasteboard = .general, directory: URL? = nil) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = base.appendingPathComponent("Islet/Shelf", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        loadExisting()
    }

    // MARK: Siklus hidup

    func start() {
        let t = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    func stop() { timer?.invalidate(); timer = nil }

    // MARK: Deteksi clipboard

    func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        ingest(from: pasteboard)
    }

    /// Inti deteksi: dipakai juga oleh pengujian dengan pasteboard terpisah.
    @discardableResult
    func ingest(from board: NSPasteboard) -> ShelfItem? {
        // 1. Gambar mentah di clipboard (jalur utama screenshot: Cmd+Ctrl+Shift+3/4).
        if let image = NSImage(pasteboard: board), looksLikeImage(board) {
            if let item = save(image: image) { return item }
        }
        // 2. Berkas gambar yang di-copy (mis. screenshot yang sudah tersimpan di Desktop).
        if let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls where looksLikeScreenshotFile(url) && !isInsideShelf(url) {
                if let item = save(fileURL: url) { return item }
            }
        }
        return nil
    }

    private func looksLikeImage(_ board: NSPasteboard) -> Bool {
        let imageTypes: Set<NSPasteboard.PasteboardType> = [.png, .tiff]
        let available = Set(board.types ?? [])
        // Jangan ambil berkas (ditangani di langkah 2) dan jangan ambil teks biasa.
        return !available.isDisjoint(with: imageTypes)
    }

    private func looksLikeScreenshotFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let prefixes = ["screenshot", "screen shot", "cleanshot", "bildschirmfoto", "tangkapan layar"]
        guard prefixes.contains(where: { name.hasPrefix($0) }) else { return false }
        let imageExtensions = ["png", "jpg", "jpeg", "tiff", "heic"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    private func isInsideShelf(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path)
    }

    // MARK: Simpan

    @discardableResult
    private func save(image: NSImage) -> ShelfItem? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return write(data: png, pixelSize: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    }

    @discardableResult
    private func save(fileURL: URL) -> ShelfItem? {
        guard let data = try? Data(contentsOf: fileURL),
              let rep = NSBitmapImageRep(data: data),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return write(data: png, pixelSize: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    }

    /// Menyimpan data PNG ke shelf. Dipakai oleh jalur clipboard maupun pengujian.
    @discardableResult
    func write(data png: Data, pixelSize: NSSize) -> ShelfItem? {
        let id = Self.hash(png)
        if items.contains(where: { $0.id == id }) { return nil }   // sudah ada, jangan gandakan

        let stamp = Self.stampFormatter.string(from: Date())
        let url = directory.appendingPathComponent("Islet-\(stamp)-\(id.prefix(6)).png")
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        let item = ShelfItem(id: id, url: url, addedAt: Date(), pixelSize: pixelSize)
        items.insert(item, at: 0)
        prune()
        onNewItem?(item)
        return item
    }

    private func prune() {
        while items.count > limit {
            let victim = items.removeLast()
            try? FileManager.default.removeItem(at: victim.url)
        }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: item.url)
    }

    func clearAll() {
        for item in items { try? FileManager.default.removeItem(at: item.url) }
        items.removeAll()
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(items.map { $0.url })
    }

    private func loadExisting() {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: keys,
                                                                     options: [.skipsHiddenFiles]) else { return }
        var found: [ShelfItem] = []
        for url in urls where url.pathExtension.lowercased() == "png" {
            guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else { continue }
            let date = (try? url.resourceValues(forKeys: Set(keys)).creationDate) ?? Date.distantPast
            found.append(ShelfItem(id: Self.hash(data),
                                   url: url,
                                   addedAt: date,
                                   pixelSize: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)))
        }
        items = found.sorted { $0.addedAt > $1.addedAt }
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
