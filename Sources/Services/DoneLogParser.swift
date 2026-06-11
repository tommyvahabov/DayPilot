import Foundation

/// Parses done.md: `## yyyy-MM-dd` day headers, `- [x]` completion entries
/// (with optional pipe tokens), and `>` ritual/audit markers.
enum DoneLogParser {
    static func parse(content: String) -> [DoneDay] {
        let lines = content.components(separatedBy: .newlines)
        var days: [DoneDay] = []
        var current: DoneDay?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                if let day = current { days.append(day) }
                let date = String(trimmed.dropFirst(3))
                current = DoneDay(id: date, date: date, entries: [])
            } else if trimmed.hasPrefix("- [x] "), current != nil {
                current?.entries.append(parseEntry(String(trimmed.dropFirst(6))))
            } else if trimmed.hasPrefix("> preflight "), current != nil {
                current?.preflight = String(trimmed.dropFirst(12)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("> closed "), current != nil {
                current?.closed = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            }
        }
        if let day = current { days.append(day) }
        return days
    }

    private static func parseEntry(_ raw: String) -> DoneEntry {
        let parts = raw.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let title = parts[0]
        var project: String?
        var effort = ""
        var at: String?
        for part in parts.dropFirst() {
            let lower = part.lowercased()
            if lower.hasPrefix("project:") {
                project = part.dropFirst(8).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("effort:") {
                effort = part.dropFirst(7).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("at:") {
                at = part.dropFirst(3).trimmingCharacters(in: .whitespaces)
            }
        }
        return DoneEntry(title: title, project: project, effort: effort, at: at)
    }
}
