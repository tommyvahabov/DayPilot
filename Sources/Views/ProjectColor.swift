import SwiftUI

enum ProjectColor {
    private static let palette: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .mint, .brown]

    /// Deterministic djb2 hash — `String.hashValue` is seeded per process, which
    /// made project colors change on every launch.
    static func color(for name: String) -> Color {
        var hash: UInt64 = 5381
        for byte in name.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
