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
    /// Free-form ideas / journal entries from ideas.md.
    private(set) var ideas: [Idea] = []

    /// Set by the popover to deep-link the main window to a tab; consumed and
    /// cleared by MainWindowView.
    var route: SidebarTab?

    /// CoPilot: fired with a collab id the moment its accepted task's line flips
    /// [ ]→[x] in todos.md — the zero-click "done" signal. Set by PeerManager,
    /// which relays it back to whoever sent the task. Detection rides the
    /// existing FileWatcher → recompute path, so there's no second watcher on
    /// todos.md (which would race the atomic-write handling in FileWatcher).
    var onCollabTaskDone: ((UUID) -> Void)?

    /// Snapshot of todos.md lines from the previous recompute, for collab flip
    /// detection. nil until the first recompute (so we never fire on launch).
    private var previousTodoLines: [String]?

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
    var ideasPath: String { "\(schedulerDir)/ideas.md" }

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
        if !fm.fileExists(atPath: ideasPath) {
            try? "# Ideas\n".write(toFile: ideasPath, atomically: true, encoding: .utf8)
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
            let newLines = todoContent.components(separatedBy: .newlines)
            // Spot collab tasks that just got ticked off, before we overwrite the
            // snapshot. First recompute compares against itself → no flips.
            let doneCollabIDs = CollabBridge.newlyCompletedCollabIDs(
                old: previousTodoLines ?? newLines, new: newLines
            )
            previousTodoLines = newLines
            rawTodoLines = newLines
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
            ideas = readIdeas()
            for id in doneCollabIDs { onCollabTaskDone?(id) }
        } catch {
            errorMessage = "Failed to read files: \(error.localizedDescription)"
        }
    }

    // MARK: - CoPilot

    /// Land an accepted shared task in todos.md as a line that reads exactly like
    /// a hand-written one (plus the hidden `collab:` tag). Goes through the same
    /// writeBack/recompute/git path as every other edit so the file watcher,
    /// auto-commit, and done-detection all stay consistent.
    func appendSharedTask(_ task: SharedTask) {
        fileWatcher?.isSelfEditing = true
        rawTodoLines.append(CollabBridge.todoLine(for: task))
        for note in CollabBridge.notes(for: task) {
            rawTodoLines.append("  \(note)")
        }
        writeBack()
        recompute()
    }

    /// Tick off a collab task by its tracking id (the CoPilot inbox "Done"
    /// button). Routes through the same checkbox flip that the FSEvents watcher
    /// catches, so the "done" ack is sent down one path whether the coworker
    /// checks the box in DayPilot or taps Done in CoPilot.
    func completeCollabTask(id: UUID) {
        for (i, line) in rawTodoLines.enumerated() {
            guard line.trimmingCharacters(in: .whitespaces).hasPrefix("- [ ] "),
                  CollabBridge.collabID(from: line) == id else { continue }
            let item = TodoParser.parse(lines: [line]).first
            fileWatcher?.isSelfEditing = true
            TodoParser.markComplete(lines: &rawTodoLines, at: i)
            writeBack()
            if let item { logCompletion(item) }
            recompute()
            return
        }
    }

    func completeTask(_ item: TodoItem) {
        // Re-resolve: the captured lineIndex can go stale during the 0.8s
        // completion animation if todos.md changed underneath us.
        let idx = resolveLineIndex(for: item, openOnly: true)
        guard idx >= 0 else { recompute(); return }
        fileWatcher?.isSelfEditing = true
        TodoParser.markComplete(lines: &rawTodoLines, at: idx)
        writeBack()
        logCompletion(item)
        recompute()
    }

    /// Re-resolve a task's line index at action time by matching its (original)
    /// title, since a captured lineIndex can go stale when todos.md changes
    /// between render and action (external MCP edit, completion animation, an
    /// open editor sheet). Returns -1 if the task can't be located.
    private func resolveLineIndex(for item: TodoItem, openOnly: Bool = false) -> Int {
        let prefixes = openOnly ? ["- [ ] "] : ["- [ ] ", "- [x] ", "- [?] "]
        func matches(_ trimmed: String) -> Bool {
            for p in prefixes where trimmed.hasPrefix(p) {
                let content = trimmed.dropFirst(6)
                let parsed = content.split(separator: "|").first
                    .map { $0.trimmingCharacters(in: .whitespaces) } ?? String(content)
                return parsed == item.title
            }
            return false
        }
        if item.lineIndex >= 0, item.lineIndex < rawTodoLines.count,
           matches(rawTodoLines[item.lineIndex].trimmingCharacters(in: .whitespaces)) {
            return item.lineIndex
        }
        for (i, line) in rawTodoLines.enumerated() where matches(line.trimmingCharacters(in: .whitespaces)) {
            return i
        }
        return -1
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

    /// Full edit from the task editor modal, applied in a single write: title +
    /// tokens on the task line, the notes block below it, the `attach:` token,
    /// and on-disk cleanup of any removed attachment files.
    func applyTaskEdit(
        _ item: TodoItem,
        title: String,
        project: String,
        effort: String,
        deadline: String,
        deferUntil: String,
        priority: Int?,
        notes: [String],
        attachments: [Attachment]
    ) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // Re-resolve in case the line moved (external edit while the modal was open).
        let lineIndex = resolveLineIndex(for: item)
        guard lineIndex >= 0 else { recompute(); return }

        var line = TodoParser.setTitle(line: rawTodoLines[lineIndex], title: title)
        let fields: [(String, String)] = [
            ("project", project), ("effort", effort),
            ("deadline", deadline), ("defer", deferUntil),
            ("priority", priority.map(String.init) ?? ""),
        ]
        for (key, raw) in fields {
            let value = raw.trimmingCharacters(in: .whitespaces)
            line = TodoParser.setToken(line: line, key: key, value: value.isEmpty ? nil : value)
        }
        line = TodoParser.setToken(line: line, key: "attach", value: TodoParser.attachToken(for: attachments))
        rawTodoLines[lineIndex] = line

        // Notes live in the indented block directly below the task line.
        TodoParser.updateNotes(lines: &rawTodoLines, at: lineIndex, notes: notes)

        fileWatcher?.isSelfEditing = true
        writeBack()

        // Delete files for attachments the user removed — but only if no other
        // task still references them.
        let kept = Set(attachments.map(\.relativePath))
        for gone in item.attachments where !kept.contains(gone.relativePath) {
            deleteAttachmentFileIfUnreferenced(gone)
        }

        let proj = project.trimmingCharacters(in: .whitespaces)
        if !proj.isEmpty { saveProjectIfNew(proj) }
        recompute()
    }

    /// Delete an attachment's backing file only when no remaining task line
    /// references it, so a duplicated path can't orphan a still-used file.
    private func deleteAttachmentFileIfUnreferenced(_ attachment: Attachment) {
        let stillReferenced = rawTodoLines.contains { $0.contains(attachment.relativePath) }
        if !stillReferenced { AttachmentService.deleteFile(attachment) }
    }

    /// Delete a task, its notes, and any attachment files from todos.md.
    func removeTask(_ item: TodoItem) {
        let lineIndex = resolveLineIndex(for: item)
        guard lineIndex >= 0 else { recompute(); return }
        let len = 1 + TodoParser.noteLineCount(lines: rawTodoLines, at: lineIndex)
        rawTodoLines.removeSubrange(lineIndex..<(lineIndex + len))
        fileWatcher?.isSelfEditing = true
        writeBack()
        for attachment in item.attachments {
            deleteAttachmentFileIfUnreferenced(attachment)
        }
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

    // MARK: - Ideas

    private func readIdeas() -> [Idea] {
        guard let content = try? String(contentsOfFile: ideasPath, encoding: .utf8) else { return [] }
        return Self.sortIdeas(IdeasParser.parse(content: content))
    }

    private static func sortIdeas(_ list: [Idea]) -> [Idea] {
        list.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            return a.id > b.id  // stable tiebreak so equal timestamps never reorder
        }
    }

    private func writeIdeas(_ list: [Idea]) {
        let ordered = Self.sortIdeas(list)
        fileWatcher?.isSelfEditing = true
        try? IdeasParser.serialize(ordered).write(toFile: ideasPath, atomically: true, encoding: .utf8)
        ideas = ordered
        git.commitSoon("app: update ideas")
    }

    @discardableResult
    func addIdea(title: String, body: String) -> Idea? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(t.isEmpty && b.isEmpty) else { return nil }
        let idea = Idea(
            id: IdeasParser.newID(),
            title: t.isEmpty ? Self.deriveTitle(from: b) : t,
            body: b,
            createdAt: Date(),
            pinned: false
        )
        writeIdeas([idea] + ideas)
        return idea
    }

    func updateIdea(_ id: String, title: String, body: String) {
        guard let idx = ideas.firstIndex(where: { $0.id == id }) else { return }
        var list = ideas
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        list[idx].title = t.isEmpty ? Self.deriveTitle(from: b) : t
        list[idx].body = b
        writeIdeas(list)
    }

    func deleteIdea(_ id: String) {
        writeIdeas(ideas.filter { $0.id != id })
    }

    func toggleIdeaPin(_ id: String) {
        guard let idx = ideas.firstIndex(where: { $0.id == id }) else { return }
        var list = ideas
        list[idx].pinned.toggle()
        writeIdeas(list)
    }

    /// Promote an idea into a real task; optionally clear the idea afterward.
    func promoteIdeaToTask(_ idea: Idea, project: String? = nil, removeIdea: Bool) {
        let titleSource = idea.title.isEmpty ? idea.preview : idea.title
        var raw = TodoParser.sanitizeTitle(titleSource)
        if let project, !project.isEmpty { raw += " | project: \(project)" }
        var bodyLines = idea.body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // When the title was derived from the body, its first line already became
        // the title — don't repeat it as a note.
        if idea.title.isEmpty, let first = bodyLines.first, first == idea.preview {
            bodyLines.removeFirst()
        }
        let notes = bodyLines.filter { $0 != idea.title }
        addTask(raw: raw, notes: notes)
        if removeIdea { deleteIdea(idea.id) }
    }

    private static func deriveTitle(from body: String) -> String {
        let first = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? "Untitled"
        return first.count > 60 ? String(first.prefix(60)).trimmingCharacters(in: .whitespaces) + "…" : first
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
        let paths = [todosPath, memoryPath, ideasPath].filter { FileManager.default.fileExists(atPath: $0) }
        fileWatcher = FileWatcher(filePaths: paths) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.recompute()
                self.git.commitSoon("external edit (claude/mcp or manual)")
            }
        }
    }
}
