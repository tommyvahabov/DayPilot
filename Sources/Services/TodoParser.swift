import Foundation

enum TodoParser {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(lines: [String]) -> [TodoItem] {
        var items: [TodoItem] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- [ ] ") else { continue }
            let content = String(trimmed.dropFirst(6))
            let item = parseFields(content, lineIndex: index, completed: false)
            items.append(item)
        }
        return items
    }

    static func parseAll(lines: [String]) -> [TodoItem] {
        var items: [TodoItem] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") {
                let content = String(trimmed.dropFirst(6))
                items.append(parseFields(content, lineIndex: index, completed: false))
            } else if trimmed.hasPrefix("- [x] ") {
                let content = String(trimmed.dropFirst(6))
                items.append(parseFields(content, lineIndex: index, completed: true))
            }
        }
        return items
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

    static func append(lines: inout [String], raw: String) {
        lines.append("- [ ] \(raw)")
    }
}
