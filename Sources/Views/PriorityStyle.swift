import SwiftUI

/// Visual + label mapping for task priority (1 = high … 3 = low).
enum PriorityStyle {
    static let levels = [1, 2, 3]

    static func clamp(_ p: Int) -> Int { min(max(p, 1), 3) }

    /// Compact badge label, e.g. "P1".
    static func badge(_ p: Int) -> String { "P\(clamp(p))" }

    /// Human label, e.g. "High".
    static func name(_ p: Int) -> String {
        ["High", "Medium", "Low"][clamp(p) - 1]
    }

    static func color(_ p: Int) -> Color {
        [Color.red, Color.orange, Color.blue][clamp(p) - 1]
    }
}
