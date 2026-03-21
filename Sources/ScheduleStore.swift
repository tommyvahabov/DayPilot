import Foundation
import SwiftUI

@Observable
@MainActor
final class ScheduleStore {
    var queue = DayQueue()
    private(set) var context = MemoryContext()
    private(set) var rawTodoLines: [String] = []
    private(set) var errorMessage: String?
    private(set) var completedTodayCount: Int = 0
    private(set) var totalTodayCount: Int = 0
    private(set) var doneLog: [DoneDay] = []

    private var fileWatcher: FileWatcher?
    private let schedulerDir: String

    var todosPath: String { "\(schedulerDir)/todos.md" }
    var memoryPath: String { "\(schedulerDir)/memory.md" }
    var donePath: String { "\(schedulerDir)/done.md" }

    private var started = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        self.schedulerDir = NSHomeDirectory() + "/scheduler"
    }

    func start() {
        guard !started else { return }
        started = true
        recompute()
        setupFileWatcher()
    }

    func recompute() {
        errorMessage = nil

        guard FileManager.default.fileExists(atPath: todosPath) else {
            errorMessage = "Create ~/scheduler/todos.md to get started"
            queue = DayQueue()
            return
        }

        do {
            let todoContent = try String(contentsOfFile: todosPath, encoding: .utf8)
            rawTodoLines = todoContent.components(separatedBy: .newlines)
            let todos = TodoParser.parse(lines: rawTodoLines)
            let allTodos = TodoParser.parseAll(lines: rawTodoLines)
            let completed = allTodos.filter { $0.isCompleted }

            if FileManager.default.fileExists(atPath: memoryPath) {
                let memContent = try String(contentsOfFile: memoryPath, encoding: .utf8)
                context = MemoryParser.parse(content: memContent)
            } else {
                context = MemoryContext()
            }

            queue = Scheduler.schedule(todos: todos, context: context)

            // Filter completed to only today's by matching titles in done.md
            let todayTitles = Set(todayDoneTitles())
            queue.completedToday = completed.filter { todayTitles.contains($0.title) }
            let todayStats = computeCompletedToday()
            completedTodayCount = todayStats.count
            totalTodayCount = todayStats.count + queue.today.count
            doneLog = parseDoneLog()
        } catch {
            errorMessage = "Failed to read files: \(error.localizedDescription)"
        }
    }

    func completeTask(_ item: TodoItem) {
        fileWatcher?.isSelfEditing = true
        TodoParser.markComplete(lines: &rawTodoLines, at: item.lineIndex)
        writeBack()
        logCompletion(item)
        recompute()
    }

    func uncompleteTask(_ item: TodoItem) {
        fileWatcher?.isSelfEditing = true
        TodoParser.markIncomplete(lines: &rawTodoLines, at: item.lineIndex)
        writeBack()
        removeFromDoneLog(item)
        recompute()
    }

    /// Uncomplete a task by title match (used by Flight Log where we don't have lineIndex)
    func uncompleteByTitle(_ title: String) {
        fileWatcher?.isSelfEditing = true
        for (i, line) in rawTodoLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [x] ") && trimmed.contains(title) {
                TodoParser.markIncomplete(lines: &rawTodoLines, at: i)
                writeBack()
                let item = TodoItem(title: title, lineIndex: i)
                removeFromDoneLog(item)
                recompute()
                return
            }
        }
    }

    func addTask(raw: String, notes: [String] = []) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        fileWatcher?.isSelfEditing = true
        TodoParser.append(lines: &rawTodoLines, raw: trimmed, notes: notes)
        writeBack()
        recompute()
    }

    func updateNotes(for item: TodoItem, notes: [String]) {
        fileWatcher?.isSelfEditing = true
        TodoParser.updateNotes(lines: &rawTodoLines, at: item.lineIndex, notes: notes)
        writeBack()
        recompute()
    }

    func moveTask(from source: IndexSet, to destination: Int, in section: Section) {
        switch section {
        case .today: queue.today.move(fromOffsets: source, toOffset: destination)
        case .tomorrow: queue.tomorrow.move(fromOffsets: source, toOffset: destination)
        case .backlog: queue.backlog.move(fromOffsets: source, toOffset: destination)
        }
    }

    enum Section {
        case today, tomorrow, backlog
    }

    // MARK: - Daily Summary

    private func logCompletion(_ item: TodoItem) {
        let today = Self.dateFormatter.string(from: Date())
        let header = "## \(today)"

        var lines: [String] = []
        if FileManager.default.fileExists(atPath: donePath) {
            let content = (try? String(contentsOfFile: donePath, encoding: .utf8)) ?? ""
            lines = content.components(separatedBy: .newlines)
        }

        if let headerIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) {
            var insertAt = headerIdx + 1
            while insertAt < lines.count {
                let l = lines[insertAt].trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("## ") || l.isEmpty { break }
                insertAt += 1
            }
            var entry = "- [x] \(item.title)"
            if let p = item.project { entry += " | project: \(p)" }
            entry += " | effort: \(DurationParser.format(minutes: item.effortMinutes))"
            lines.insert(entry, at: insertAt)
        } else {
            var insertAt = 0
            if let first = lines.first, first.hasPrefix("# ") {
                insertAt = 1
                if insertAt < lines.count && lines[insertAt].isEmpty {
                    insertAt = 2
                }
            }
            var entry = "- [x] \(item.title)"
            if let p = item.project { entry += " | project: \(p)" }
            entry += " | effort: \(DurationParser.format(minutes: item.effortMinutes))"
            lines.insert(contentsOf: [header, entry, ""], at: insertAt)
        }

        let content = lines.joined(separator: "\n")
        try? content.write(toFile: donePath, atomically: true, encoding: .utf8)
    }

    private func removeFromDoneLog(_ item: TodoItem) {
        guard FileManager.default.fileExists(atPath: donePath) else { return }
        guard let content = try? String(contentsOfFile: donePath, encoding: .utf8) else { return }

        let today = Self.dateFormatter.string(from: Date())
        let header = "## \(today)"
        var lines = content.components(separatedBy: .newlines)

        guard let headerIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) else { return }

        // Find and remove the LAST matching entry for this task under today's header
        var lastMatch: Int?
        var i = headerIdx + 1
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") || line.isEmpty { break }
            if line.contains(item.title) {
                lastMatch = i
            }
            i += 1
        }

        if let idx = lastMatch {
            lines.remove(at: idx)
            let result = lines.joined(separator: "\n")
            try? result.write(toFile: donePath, atomically: true, encoding: .utf8)
        }
    }

    private func todayDoneTitles() -> [String] {
        guard FileManager.default.fileExists(atPath: donePath) else { return [] }
        guard let content = try? String(contentsOfFile: donePath, encoding: .utf8) else { return [] }

        let today = Self.dateFormatter.string(from: Date())
        let header = "## \(today)"
        let lines = content.components(separatedBy: .newlines)

        guard let headerIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) else { return [] }

        var titles: [String] = []
        var i = headerIdx + 1
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") || line.isEmpty { break }
            if line.hasPrefix("- [x] ") {
                let raw = String(line.dropFirst(6))
                let title = raw.split(separator: "|").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? raw
                titles.append(title)
            }
            i += 1
        }
        return titles
    }

    // MARK: - Completed Today

    private func computeCompletedToday() -> (count: Int, minutes: Int) {
        guard FileManager.default.fileExists(atPath: donePath) else { return (0, 0) }
        guard let content = try? String(contentsOfFile: donePath, encoding: .utf8) else { return (0, 0) }

        let today = Self.dateFormatter.string(from: Date())
        let header = "## \(today)"
        let lines = content.components(separatedBy: .newlines)

        guard let headerIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) else { return (0, 0) }

        var count = 0
        var total = 0
        var i = headerIdx + 1
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") || line.isEmpty { break }
            if line.hasPrefix("- [x] ") {
                count += 1
                if let effortRange = line.range(of: "effort: ") {
                    let rest = String(line[effortRange.upperBound...])
                    let effortStr = rest.split(separator: "|").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? rest
                    total += DurationParser.parseMinutes(effortStr)
                }
            }
            i += 1
        }
        return (count, total)
    }

    // MARK: - Done Log

    private func parseDoneLog() -> [DoneDay] {
        guard FileManager.default.fileExists(atPath: donePath) else { return [] }
        guard let content = try? String(contentsOfFile: donePath, encoding: .utf8) else { return [] }

        let lines = content.components(separatedBy: .newlines)
        var days: [DoneDay] = []
        var currentDate: String?
        var currentEntries: [DoneEntry] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                if let date = currentDate {
                    days.append(DoneDay(id: date, date: date, entries: currentEntries))
                }
                currentDate = String(trimmed.dropFirst(3))
                currentEntries = []
            } else if trimmed.hasPrefix("- [x] "), currentDate != nil {
                let raw = String(trimmed.dropFirst(6))
                let parts = raw.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                let title = parts[0]
                var project: String?
                var effort = ""
                for part in parts.dropFirst() {
                    let lower = part.lowercased()
                    if lower.hasPrefix("project:") {
                        project = part.dropFirst(8).trimmingCharacters(in: .whitespaces)
                    } else if lower.hasPrefix("effort:") {
                        effort = part.dropFirst(7).trimmingCharacters(in: .whitespaces)
                    }
                }
                currentEntries.append(DoneEntry(title: title, project: project, effort: effort))
            }
        }
        if let date = currentDate {
            days.append(DoneDay(id: date, date: date, entries: currentEntries))
        }

        return days
    }

    // MARK: - Private

    private func writeBack() {
        let content = rawTodoLines.joined(separator: "\n")
        try? content.write(toFile: todosPath, atomically: true, encoding: .utf8)
    }

    private func setupFileWatcher() {
        let dir = schedulerDir
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let paths = [todosPath, memoryPath].filter { FileManager.default.fileExists(atPath: $0) }
        fileWatcher = FileWatcher(filePaths: paths) { [weak self] in
            Task { @MainActor in
                self?.recompute()
            }
        }
    }
}
