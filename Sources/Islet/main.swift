import AppKit

// Islet — aplikasi lokal (agent) yang meniru perilaku yang bisa diamati dari sebuah
// "notch island" untuk macOS. Implementasi mandiri: AppKit + SwiftUI + API publik macOS.
// Tidak ada kode, aset, suara, atau ikon pihak lain yang disalin.

// Mode uji tanpa antarmuka: `Islet --selftest` menjalankan pemeriksaan internal lalu keluar.
if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
