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

    init() {
        self.schedulerDir = NSHomeDirectory() + "/scheduler"
    }

    func start() {
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
        recompute()
    }

    func addTask(raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        fileWatcher?.isSelfEditing = true
        TodoParser.append(lines: &rawTodoLines, raw: trimmed)
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
