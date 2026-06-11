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
        var energy = EnergyBlocks()
        var calibration: [String: Double] = [:]
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
                let lower = trimmed.lowercased()
                if lower.hasPrefix("daily_capacity:") {
                    let val = trimmed.dropFirst(15).trimmingCharacters(in: .whitespaces)
                    dailyCapacity = DurationParser.parseMinutes(val)
                } else if lower.hasPrefix("deep_work:") {
                    if let range = parseHourRange(String(trimmed.dropFirst(10))) {
                        energy.deepWorkStart = range.0
                        energy.deepWorkEnd = range.1
                    }
                } else if lower.hasPrefix("light:") {
                    if let range = parseHourRange(String(trimmed.dropFirst(6))) {
                        energy.lightEnd = range.1
                    }
                } else if lower.hasPrefix("admin:") {
                    if let range = parseHourRange(String(trimmed.dropFirst(6))) {
                        energy.adminEnd = range.1
                    }
                }
            case "calibration":
                // "- ProjectName: 1.8"
                if trimmed.hasPrefix("- "), let colon = trimmed.lastIndex(of: ":") {
                    let name = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<colon])
                        .trimmingCharacters(in: .whitespaces).lowercased()
                    let value = Double(trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces))
                    if !name.isEmpty, let value, value > 0 {
                        calibration[name] = value
                    }
                }
            default:
                break
            }
        }

        return MemoryContext(projects: projects, dailyCapacityMinutes: dailyCapacity, energy: energy, calibration: calibration)
    }

    /// "9-12" → (9, 12); tolerant of spaces. Nil when malformed or out of range.
    private static func parseHourRange(_ raw: String) -> (Int, Int)? {
        let parts = raw.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let start = Int(parts[0]), let end = Int(parts[1]),
              (0...24).contains(start), (0...24).contains(end), start < end else { return nil }
        return (start, end)
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
