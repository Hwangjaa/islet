import Foundation

/// Penulis jejak debug ke berkas. Dipakai saat menguji perilaku hover/ekspansi:
/// NSLog kadang tidak terlihat lewat `log show`, sedangkan berkas selalu bisa dibaca.
enum Debug {
    static let path = "/tmp/islet-hover.log"
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func trace(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: path)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
