import Foundation

enum MemoryParser {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(content: String) -> MemoryContext {
        let lines = content.components(separatedBy: .newlines)
        var projects: [ProjectInfo] = []
        var dailyCapacity = 240
        var currentSection: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                currentSection = String(trimmed.dropFirst(3)).lowercased()
                continue
            }

            switch currentSection {
            case "projects":
                if trimmed.hasPrefix("- ") {
                    if let project = parseProject(String(trimmed.dropFirst(2))) {
                        projects.append(project)
                    }
                }
            case "settings":
                if trimmed.lowercased().hasPrefix("daily_capacity:") {
                    let val = trimmed.dropFirst(15).trimmingCharacters(in: .whitespaces)
                    dailyCapacity = DurationParser.parseMinutes(val)
                }
            default:
                break
            }
        }

        return MemoryContext(projects: projects, dailyCapacityMinutes: dailyCapacity)
    }

    private static func parseProject(_ content: String) -> ProjectInfo? {
        let parts = content.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let name = parts.first, !name.isEmpty else { return nil }

        var priority = Int.max
        var deadline: Date?

        for part in parts.dropFirst() {
            let lower = part.lowercased()
            if lower.hasPrefix("priority:") {
                let val = part.dropFirst(9).trimmingCharacters(in: .whitespaces)
                priority = Int(val) ?? Int.max
            } else if lower.hasPrefix("deadline:") {
                let val = part.dropFirst(9).trimmingCharacters(in: .whitespaces)
                deadline = dateFormatter.date(from: val)
            }
        }

        return ProjectInfo(name: name, priority: priority, deadline: deadline)
    }
}
