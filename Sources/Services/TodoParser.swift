import Foundation

enum TodoParser {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(lines: [String]) -> [TodoItem] {
        var items: [TodoItem] = []
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") {
                let content = String(trimmed.dropFirst(6))
                var item = parseFields(content, lineIndex: i, completed: false)
                i += 1
                item.notes = collectNotes(lines: lines, from: &i)
                items.append(item)
            } else {
                i += 1
            }
        }
        return items
    }

    static func parseAll(lines: [String]) -> [TodoItem] {
        var items: [TodoItem] = []
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") {
                let content = String(trimmed.dropFirst(6))
                var item = parseFields(content, lineIndex: i, completed: false)
                i += 1
                item.notes = collectNotes(lines: lines, from: &i)
                items.append(item)
            } else if trimmed.hasPrefix("- [x] ") {
                let content = String(trimmed.dropFirst(6))
                var item = parseFields(content, lineIndex: i, completed: true)
                i += 1
                item.notes = collectNotes(lines: lines, from: &i)
                items.append(item)
            } else {
                i += 1
            }
        }
        return items
    }

    /// Collect indented lines following a task as notes
    private static func collectNotes(lines: [String], from i: inout Int) -> [String] {
        var notes: [String] = []
        while i < lines.count {
            let line = lines[i]
            // Note lines must start with whitespace (indented) and not be a task
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty,
                  (line.hasPrefix("  ") || line.hasPrefix("\t")),
                  !trimmed.hasPrefix("- [ ] "),
                  !trimmed.hasPrefix("- [x] ") else {
                break
            }
            notes.append(trimmed)
            i += 1
        }
        return notes
    }

    private static func parseFields(_ content: String, lineIndex: Int, completed: Bool) -> TodoItem {
        let parts = content.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let title = parts[0]
        var project: String?
        var effort = 15
        var deadline: Date?

        for part in parts.dropFirst() {
            let lower = part.lowercased()
            if lower.hasPrefix("project:") {
                project = part.dropFirst(8).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("effort:") {
                let val = part.dropFirst(7).trimmingCharacters(in: .whitespaces)
                effort = DurationParser.parseMinutes(val)
            } else if lower.hasPrefix("deadline:") {
                let val = part.dropFirst(9).trimmingCharacters(in: .whitespaces)
                deadline = dateFormatter.date(from: val)
            }
        }

        return TodoItem(
            title: title,
            project: project,
            effortMinutes: effort,
            deadline: deadline,
            isCompleted: completed,
            lineIndex: lineIndex
        )
    }

    static func markComplete(lines: inout [String], at lineIndex: Int) {
        guard lineIndex >= 0, lineIndex < lines.count else { return }
        lines[lineIndex] = lines[lineIndex].replacingOccurrences(of: "- [ ] ", with: "- [x] ")
    }

    static func markIncomplete(lines: inout [String], at lineIndex: Int) {
        guard lineIndex >= 0, lineIndex < lines.count else { return }
        lines[lineIndex] = lines[lineIndex].replacingOccurrences(of: "- [x] ", with: "- [ ] ")
    }

    static func append(lines: inout [String], raw: String, notes: [String] = []) {
        lines.append("- [ ] \(raw)")
        for note in notes {
            lines.append("  \(note)")
        }
    }

    static func updateNotes(lines: inout [String], at lineIndex: Int, notes: [String]) {
        guard lineIndex >= 0, lineIndex < lines.count else { return }
        // Remove existing note lines
        var removeCount = 0
        var j = lineIndex + 1
        while j < lines.count {
            let line = lines[j]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty,
                  (line.hasPrefix("  ") || line.hasPrefix("\t")),
                  !trimmed.hasPrefix("- [ ] "),
                  !trimmed.hasPrefix("- [x] ") else {
                break
            }
            removeCount += 1
            j += 1
        }
        lines.removeSubrange((lineIndex + 1)..<(lineIndex + 1 + removeCount))
        // Insert new notes
        for (offset, note) in notes.enumerated() {
            lines.insert("  \(note)", at: lineIndex + 1 + offset)
        }
    }
}
