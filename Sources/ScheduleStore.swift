import Foundation
import SwiftUI

@Observable
@MainActor
final class ScheduleStore {
    var queue = DayQueue()
    private(set) var context = MemoryContext()
    private(set) var rawTodoLines: [String] = []
    private(set) var errorMessage: String?

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

            if FileManager.default.fileExists(atPath: memoryPath) {
                let memContent = try String(contentsOfFile: memoryPath, encoding: .utf8)
                context = MemoryParser.parse(content: memContent)
            } else {
                context = MemoryContext()
            }

            queue = Scheduler.schedule(todos: todos, context: context)
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

        // Find or create today's section
        if let headerIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) {
            // Insert after header
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
            // Add new date section at top (after title if exists)
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
