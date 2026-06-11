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
    /// Agent-proposed `- [?]` tasks awaiting accept/reject.
    private(set) var proposals: [TodoItem] = []

    private var fileWatcher: FileWatcher?
    private let schedulerDir: String
    private let git: GitService
    private var tickTimer: Timer?

    /// Minute tick. Views (esp. the menubar HUD label) read this so @Observable
    /// re-renders them as time passes — MenuBarExtra labels can't host
    /// TimelineView (it fails to render in an NSStatusItem).
    private(set) var now: Date = Date()

    var todosPath: String { "\(schedulerDir)/todos.md" }
    var memoryPath: String { "\(schedulerDir)/memory.md" }
    var donePath: String { "\(schedulerDir)/done.md" }
    var briefingPath: String { "\(schedulerDir)/briefing.md" }

    /// Claude's morning briefing body, only when briefing.md is dated today.
    private(set) var briefing: String?

    private var started = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    init() {
        self.schedulerDir = NSHomeDirectory() + "/scheduler"
        self.git = GitService(directory: schedulerDir)
    }

    func start() {
        guard !started else { return }
        started = true
        bootstrapSchedulerDirectory()
        ClaudeIntegration.ensureRegistered()
        recompute()
        setupFileWatcher()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    private func bootstrapSchedulerDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: schedulerDir) {
            try? fm.createDirectory(atPath: schedulerDir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: todosPath) {
            let starter = """
            # Todos

            - [ ] Welcome to DayPilot — try editing this list | project: DayPilot | effort: 5m
            - [ ] Open ~/scheduler/memory.md and set your projects + capacity | project: DayPilot | effort: 10m

            """
            try? starter.write(toFile: todosPath, atomically: true, encoding: .utf8)
        }
        if !fm.fileExists(atPath: memoryPath) {
            let starter = """
            # Memory

            ## Projects
            - DayPilot | priority: 1

            ## Settings
            daily_capacity: 4h

            ## Energy pattern
            Best focus 9am-12pm, lighter work afternoons, admin in the evening.

            ## Current focus
            Getting set up with DayPilot.

            """
            try? starter.write(toFile: memoryPath, atomically: true, encoding: .utf8)
        }
        if !fm.fileExists(atPath: donePath) {
            try? "".write(toFile: donePath, atomically: true, encoding: .utf8)
        }
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
            proposals = TodoParser.proposals(lines: rawTodoLines)
            briefing = readBriefing()

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
    func setDailyCapacity(_ capacity: String) {
        guard FileManager.default.fileExists(atPath: memoryPath) else { return }
        guard let content = try? String(contentsOfFile: memoryPath, encoding: .utf8) else { return }

        var lines = content.components(separatedBy: .newlines)

        // Remove ALL existing daily_capacity lines
        lines.removeAll { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("daily_capacity:") }

        // Insert one fresh line after ## Settings
        if let settingsIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## Settings" }) {
            lines.insert("daily_capacity: \(capacity)", at: settingsIdx + 1)
        } else {
            lines.append(contentsOf: ["", "## Settings", "daily_capacity: \(capacity)"])
        }

        fileWatcher?.isSelfEditing = true
        let result = lines.joined(separator: "\n")
        try? result.write(toFile: memoryPath, atomically: true, encoding: .utf8)
        recompute()
    }

    func saveProjectIfNew(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if context.projects.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return
        }

        let fm = FileManager.default
        let content = (try? String(contentsOfFile: memoryPath, encoding: .utf8)) ?? "# Memory\n"
        var lines = content.components(separatedBy: .newlines)

        let newEntry = "- \(trimmed) | priority: \(context.projects.count + 1)"

        if let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## Projects" }) {
            var insertAt = lines.count
            for i in (header + 1)..<lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("##") {
                    insertAt = i
                    break
                }
                if !t.isEmpty { insertAt = i + 1 }
            }
            lines.insert(newEntry, at: insertAt)
        } else {
            if !lines.last!.isEmpty { lines.append("") }
            lines.append("## Projects")
            lines.append(newEntry)
            lines.append("")
        }

        fileWatcher?.isSelfEditing = true
        let result = lines.joined(separator: "\n")
        if !fm.fileExists(atPath: memoryPath) {
            try? fm.createDirectory(atPath: schedulerDir, withIntermediateDirectories: true)
        }
        try? result.write(toFile: memoryPath, atomically: true, encoding: .utf8)
        recompute()
    }

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

    /// Edit a task's core fields in place, preserving every other token on the
    /// line (carried, by, defer, …). Empty project/effort/deadline removes the
    /// token.
    func updateTask(_ item: TodoItem, title: String, project: String, effort: String, deadline: String) {
        guard item.lineIndex >= 0, item.lineIndex < rawTodoLines.count else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        var line = TodoParser.setTitle(line: rawTodoLines[item.lineIndex], title: trimmedTitle)
        let fields = [("project", project), ("effort", effort), ("deadline", deadline)]
        for (key, raw) in fields {
            let value = raw.trimmingCharacters(in: .whitespaces)
            line = TodoParser.setToken(line: line, key: key, value: value.isEmpty ? nil : value)
        }
        rawTodoLines[item.lineIndex] = line
        if !project.trimmingCharacters(in: .whitespaces).isEmpty {
            saveProjectIfNew(project.trimmingCharacters(in: .whitespaces))
        }
        fileWatcher?.isSelfEditing = true
        writeBack()
        recompute()
    }

    /// Delete a task and its notes from todos.md.
    func removeTask(_ item: TodoItem) {
        guard item.lineIndex >= 0, item.lineIndex < rawTodoLines.count else { return }
        let len = 1 + TodoParser.noteLineCount(lines: rawTodoLines, at: item.lineIndex)
        rawTodoLines.removeSubrange(item.lineIndex..<(item.lineIndex + len))
        fileWatcher?.isSelfEditing = true
        writeBack()
        recompute()
    }

    func updateNotes(for item: TodoItem, notes: [String]) {
        fileWatcher?.isSelfEditing = true
        TodoParser.updateNotes(lines: &rawTodoLines, at: item.lineIndex, notes: notes)
        writeBack()
        recompute()
    }

    /// Persist a manual reorder by moving the task's line block (task + notes)
    /// within todos.md. File order is the scheduler's tiebreak, so the new
    /// order survives recomputes and restarts.
    func moveTask(id: UUID, toIndex: Int, in section: Section) {
        let items: [TodoItem]
        switch section {
        case .today: items = queue.today
        case .tomorrow: items = queue.tomorrow
        case .backlog: items = queue.backlog
        }
        guard let fromIndex = items.firstIndex(where: { $0.id == id }),
              fromIndex != toIndex, toIndex >= 0, toIndex < items.count else { return }

        let moving = items[fromIndex]
        let target = items[toIndex]
        let blockLen = 1 + TodoParser.noteLineCount(lines: rawTodoLines, at: moving.lineIndex)
        let block = Array(rawTodoLines[moving.lineIndex..<(moving.lineIndex + blockLen)])
        rawTodoLines.removeSubrange(moving.lineIndex..<(moving.lineIndex + blockLen))

        var targetLine = target.lineIndex
        if targetLine > moving.lineIndex { targetLine -= blockLen }
        let insertAt: Int
        if fromIndex < toIndex {  // moving down → land after the target's block
            insertAt = targetLine + 1 + TodoParser.noteLineCount(lines: rawTodoLines, at: targetLine)
        } else {                  // moving up → land before the target
            insertAt = targetLine
        }
        rawTodoLines.insert(contentsOf: block, at: insertAt)
        fileWatcher?.isSelfEditing = true
        writeBack()
        recompute()
    }

    enum Section {
        case today, tomorrow, backlog
    }

    // MARK: - Go-Around

    struct GoAroundSummary: Equatable {
        var kept: Int
        var diverted: Int
    }

    var lastGoAround: GoAroundSummary?

    /// Replan around reality: repack what's left of today from NOW; anything
    /// that no longer fits is deferred to tomorrow with its carry count bumped.
    func goAround() {
        let open = TodoParser.parse(lines: rawTodoLines)
        let result = Scheduler.reflow(todos: open, context: context, now: Date(), minutesDoneToday: minutesDoneToday)
        let tomorrow = Self.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        for item in result.diverted {
            var line = TodoParser.setToken(line: rawTodoLines[item.lineIndex], key: "defer", value: tomorrow)
            line = TodoParser.setToken(line: line, key: "carried", value: String(item.carried + 1))
            rawTodoLines[item.lineIndex] = line
        }
        fileWatcher?.isSelfEditing = true
        writeBack()
        recompute()
        lastGoAround = GoAroundSummary(kept: result.kept.count, diverted: result.diverted.count)
    }

    // MARK: - Flight math

    /// Calibrated remaining minutes — what the ETA and caution math believe.
    var remainingTodayMinutes: Int {
        queue.today.reduce(0) { $0 + Scheduler.effectiveEffort($1, context: context) }
    }

    var minutesDoneToday: Int {
        queue.completedToday.reduce(0) { $0 + $1.effortMinutes }
    }

    var wheelsDownDate: Date {
        Scheduler.wheelsDown(now: now, remainingMinutes: remainingTodayMinutes)
    }

    var cautionActive: Bool {
        !queue.today.isEmpty && Scheduler.cautionActive(
            now: now,
            remainingMinutes: remainingTodayMinutes,
            minutesDoneToday: minutesDoneToday,
            context: context
        )
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
            lines.insert(doneEntry(for: item), at: insertAt)
        } else {
            var insertAt = 0
            if let first = lines.first, first.hasPrefix("# ") {
                insertAt = 1
                if insertAt < lines.count && lines[insertAt].isEmpty {
                    insertAt = 2
                }
            }
            lines.insert(contentsOf: [header, doneEntry(for: item), ""], at: insertAt)
        }

        let content = lines.joined(separator: "\n")
        try? content.write(toFile: donePath, atomically: true, encoding: .utf8)
    }

    private func doneEntry(for item: TodoItem) -> String {
        var entry = "- [x] \(item.title)"
        if let p = item.project { entry += " | project: \(p)" }
        entry += " | effort: \(DurationParser.format(minutes: item.effortMinutes))"
        entry += " | at: \(Self.clockFormatter.string(from: Date()))"
        return entry
    }

    /// Append a `> marker` line under today's header in done.md, creating the
    /// header if needed. Used for ritual/audit markers (preflight, closed, …).
    private func appendDayMarker(_ marker: String) {
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
            lines.insert("> \(marker)", at: insertAt)
        } else {
            var insertAt = 0
            if let first = lines.first, first.hasPrefix("# ") {
                insertAt = 1
                if insertAt < lines.count && lines[insertAt].isEmpty { insertAt = 2 }
            }
            lines.insert(contentsOf: [header, "> \(marker)", ""], at: insertAt)
        }
        try? lines.joined(separator: "\n").write(toFile: donePath, atomically: true, encoding: .utf8)
    }

    func markPreflight() {
        appendDayMarker("preflight \(Self.clockFormatter.string(from: Date()))")
        recompute()
    }

    private func readBriefing() -> String? {
        guard let content = try? String(contentsOfFile: briefingPath, encoding: .utf8) else { return nil }
        var lines = content.components(separatedBy: .newlines)
        guard let first = lines.first else { return nil }
        let today = Self.dateFormatter.string(from: Date())
        guard first.hasPrefix("# Briefing"), first.contains(today) else { return nil }
        lines.removeFirst()
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    // MARK: - Proposals

    func acceptProposal(_ item: TodoItem) {
        guard item.lineIndex >= 0, item.lineIndex < rawTodoLines.count else { return }
        rawTodoLines[item.lineIndex] = rawTodoLines[item.lineIndex]
            .replacingOccurrences(of: "- [?] ", with: "- [ ] ")
        fileWatcher?.isSelfEditing = true
        writeBack()
        recompute()
    }

    func rejectProposal(_ item: TodoItem) {
        guard item.lineIndex >= 0, item.lineIndex < rawTodoLines.count else { return }
        let len = 1 + TodoParser.noteLineCount(lines: rawTodoLines, at: item.lineIndex)
        rawTodoLines.removeSubrange(item.lineIndex..<(item.lineIndex + len))
        fileWatcher?.isSelfEditing = true
        writeBack()
        appendDayMarker("rejected: \(item.title)")
        recompute()
    }

    private var todayDoneDay: DoneDay? {
        let today = Self.dateFormatter.string(from: Date())
        return doneLog.first { $0.date == today }
    }

    var preflightDoneToday: Bool { todayDoneDay?.preflight != nil }
    var dayClosedToday: Bool { todayDoneDay?.closed != nil }

    enum EndOfDayChoice {
        case tomorrow, backlog, scrap
    }

    /// Post-flight: walk today's leftovers with a conscious choice per task,
    /// then stamp the day closed. The anti-guilt-pile.
    func closeDay(decisions: [UUID: EndOfDayChoice]) {
        let shipped = queue.completedToday.count
        var diverted = 0
        var scrapped = 0
        var scrapTitles: [String] = []
        let tomorrowStr = Self.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)

        // Descending lineIndex so removals never invalidate pending indexes.
        for item in queue.today.sorted(by: { $0.lineIndex > $1.lineIndex }) {
            switch decisions[item.id] ?? .tomorrow {
            case .tomorrow:
                var line = TodoParser.setToken(line: rawTodoLines[item.lineIndex], key: "defer", value: tomorrowStr)
                line = TodoParser.setToken(line: line, key: "carried", value: String(item.carried + 1))
                rawTodoLines[item.lineIndex] = line
                diverted += 1
            case .backlog:
                let len = 1 + TodoParser.noteLineCount(lines: rawTodoLines, at: item.lineIndex)
                let block = Array(rawTodoLines[item.lineIndex..<(item.lineIndex + len)])
                rawTodoLines.removeSubrange(item.lineIndex..<(item.lineIndex + len))
                rawTodoLines.append(contentsOf: block)  // bottom of file = lowest tiebreak
            case .scrap:
                let len = 1 + TodoParser.noteLineCount(lines: rawTodoLines, at: item.lineIndex)
                rawTodoLines.removeSubrange(item.lineIndex..<(item.lineIndex + len))
                scrapTitles.append(item.title)
                scrapped += 1
            }
        }

        fileWatcher?.isSelfEditing = true
        writeBack()
        for title in scrapTitles { appendDayMarker("scrapped: \(title)") }
        appendDayMarker("closed \(Self.clockFormatter.string(from: Date())) | shipped: \(shipped) | diverted: \(diverted) | scrapped: \(scrapped)")
        recompute()
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
        return DoneLogParser.parse(content: content)
    }

    // MARK: - Private

    private func writeBack() {
        let content = rawTodoLines.joined(separator: "\n")
        try? content.write(toFile: todosPath, atomically: true, encoding: .utf8)
        git.commitSoon("app: update todos")
    }

    private func setupFileWatcher() {
        let dir = schedulerDir
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let paths = [todosPath, memoryPath].filter { FileManager.default.fileExists(atPath: $0) }
        fileWatcher = FileWatcher(filePaths: paths) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.recompute()
                self.git.commitSoon("external edit (claude/mcp or manual)")
            }
        }
    }
}
