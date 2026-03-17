import Foundation

enum DurationParser {
    private static let pattern = /^(?:(\d+)h)?(?:(\d+)m)?$/

    static func parseMinutes(_ string: String) -> Int {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.wholeMatch(of: pattern),
              (match.1 != nil || match.2 != nil) else {
            return 15
        }
        let hours = match.1.map { Int($0)! } ?? 0
        let mins = match.2.map { Int($0)! } ?? 0
        return hours * 60 + mins
    }

    static func format(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        switch (h, m) {
        case (0, let m): return "\(m)m"
        case (let h, 0): return "\(h)h"
        case (let h, let m): return "\(h)h \(m)m"
        }
    }
}
