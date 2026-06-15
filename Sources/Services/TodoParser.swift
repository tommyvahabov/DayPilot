import Foundation

enum TodoParser {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(lines: [String]) -> [TodoItem] {
        var items: [TodoItem] = []
        var seen: [String: Int] = [:]
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") {
                let content = String(trimmed.dropFirst(6))
                var item = parseFields(content, lineIndex: i, completed: false, id: nextStableID(for: trimmed, seen: &seen))
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
        var seen: [String: Int] = [:]
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") {
                let content = String(trimmed.dropFirst(6))
                var item = parseFields(content, lineIndex: i, completed: false, id: nextStableID(for: trimmed, seen: &seen))
                i += 1
                item.notes = collectNotes(lines: lines, from: &i)
                items.append(item)
            } else if trimmed.hasPrefix("- [x] ") {
                let content = String(trimmed.dropFirst(6))
                var item = parseFields(content, lineIndex: i, completed: true, id: nextStableID(for: trimmed, seen: &seen))
                i += 1
                item.notes = collectNotes(lines: lines, from: &i)
                items.append(item)
            } else {
                i += 1
            }
        }
        return items
    }

    /// Agent-proposed tasks (`- [?] `), awaiting human accept/reject.
    static func proposals(lines: [String]) -> [TodoItem] {
        var items: [TodoItem] = []
        var seen: [String: Int] = [:]
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [?] ") {
                let content = String(trimmed.dropFirst(6))
                var item = parseFields(content, lineIndex: i, completed: false, id: nextStableID(for: trimmed, seen: &seen))
                item.isProposed = true
                i += 1
                item.notes = collectNotes(lines: lines, from: &i)
                items.append(item)
            } else {
                i += 1
            }
        }
        return items
    }

    /// A deterministic id derived from the task's full line text (so it survives
    /// re-parsing on every recompute/file-watch — SwiftUI @State on a card,
    /// including an open editor sheet, then persists). Identical lines are
    /// disambiguated by occurrence so duplicates still get distinct ids.
    private static func nextStableID(for lineKey: String, seen: inout [String: Int]) -> UUID {
        let n = seen[lineKey, default: 0]
        seen[lineKey] = n + 1
        return stableID(lineKey + "##\(n)")
    }

    private static func stableID(_ key: String) -> UUID {
        func hash(_ seed: UInt64, _ mul: UInt64) -> UInt64 {
            var h = seed
            for b in key.utf8 { h = h &* mul &+ UInt64(b) }
            return h
        }
        let hi = hash(0xcbf2_9ce4_8422_2325, 0x0000_0100_0000_01b3)  // FNV-1a constants
        let lo = hash(5381, 33)                                       // djb2
        func bytes(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8((v >> (8 * UInt64($0))) & 0xff) } }
        let b = bytes(hi) + bytes(lo)
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// Strip characters that would break a single task line: the `|` token
    /// separator and any newlines. Used everywhere a user-supplied title is
    /// composed into todos.md.
    static func sanitizeTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
                  !trimmed.hasPrefix("- [x] "),
                  !trimmed.hasPrefix("- [?] ") else {
                break
            }
            notes.append(trimmed)
            i += 1
        }
        return notes
    }

    private static func parseFields(_ content: String, lineIndex: Int, completed: Bool, id: UUID = UUID()) -> TodoItem {
        let parts = content.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let title = parts[0]
        var project: String?
        var effort = 15
        var deadline: Date?
        var deferUntil: Date?
        var carried = 0
        var addedBy: String?
        var attachments: [Attachment] = []

        for part in parts.dropFirst() {
            let lower = part.lowercased()
            if lower.hasPrefix("attach:") {
                let val = part.dropFirst(7).trimmingCharacters(in: .whitespaces)
                attachments = val
                    .split(separator: ";")
                    .map { Attachment(relativePath: $0.trimmingCharacters(in: .whitespaces)) }
                    .filter { !$0.relativePath.isEmpty }
            } else if lower.hasPrefix("project:") {
                project = part.dropFirst(8).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("effort:") {
                let val = part.dropFirst(7).trimmingCharacters(in: .whitespaces)
                effort = DurationParser.parseMinutes(val)
            } else if lower.hasPrefix("deadline:") {
                let val = part.dropFirst(9).trimmingCharacters(in: .whitespaces)
                deadline = dateFormatter.date(from: val)
            } else if lower.hasPrefix("defer:") {
                let val = part.dropFirst(6).trimmingCharacters(in: .whitespaces)
                deferUntil = dateFormatter.date(from: val)
            } else if lower.hasPrefix("carried:") {
                let val = part.dropFirst(8).trimmingCharacters(in: .whitespaces)
                carried = Int(val) ?? 0
            } else if lower.hasPrefix("by:") {
                addedBy = part.dropFirst(3).trimmingCharacters(in: .whitespaces)
            }
        }

        return TodoItem(
            id: id,
            title: title,
            project: project,
            effortMinutes: effort,
            deadline: deadline,
            isCompleted: completed,
            lineIndex: lineIndex,
            attachments: attachments,
            deferUntil: deferUntil,
            carried: carried,
            addedBy: addedBy
        )
    }

    /// Serialize attachment paths into the value for an `attach:` token, or nil
    /// to drop the token when there are none.
    static func attachToken(for attachments: [Attachment]) -> String? {
        let paths = attachments.map(\.relativePath).filter { !$0.isEmpty }
        return paths.isEmpty ? nil : paths.joined(separator: "; ")
    }

    /// Replace the title segment of a task line, preserving the checkbox state
    /// and every pipe token after it.
    static func setTitle(line: String, title: String) -> String {
        let safe = sanitizeTitle(title)
        var parts = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = parts.first else { return line }
        for prefix in ["- [ ] ", "- [x] ", "- [?] "] where first.hasPrefix(prefix) {
            parts[0] = prefix + safe
            return parts.joined(separator: " | ")
        }
        return line
    }

    /// Set, replace, or (with nil) remove a `key: value` token on a task line.
    /// The checkbox + title segment is left untouched.
    static func setToken(line: String, key: String, value: String?) -> String {
        var parts = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let prefix = "\(key.lowercased()):"
        parts.removeAll { $0.lowercased().hasPrefix(prefix) }
        if let value { parts.append("\(key): \(value)") }
        return parts.joined(separator: " | ")
    }

    /// Number of indented note lines following the task at `lineIndex`.
    static func noteLineCount(lines: [String], at lineIndex: Int) -> Int {
        var count = 0
        var j = lineIndex + 1
        while j < lines.count {
            let line = lines[j]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty,
                  (line.hasPrefix("  ") || line.hasPrefix("\t")),
                  !trimmed.hasPrefix("- [ ] "),
                  !trimmed.hasPrefix("- [x] "),
                  !trimmed.hasPrefix("- [?] ") else {
                break
            }
            count += 1
            j += 1
        }
        return count
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
                  !trimmed.hasPrefix("- [x] "),
                  !trimmed.hasPrefix("- [?] ") else {
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
