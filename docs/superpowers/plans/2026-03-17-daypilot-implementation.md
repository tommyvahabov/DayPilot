# DayPilot Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menubar app that reads local markdown files and presents a priority-queue daily schedule.

**Architecture:** Single Swift Package with executable target + test target. Models and services are pure Swift (testable), views are SwiftUI. `@Observable` ScheduleStore bridges services to views.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit (MenuBarExtra), Swift Package Manager

**Spec:** `docs/superpowers/specs/2026-03-17-daypilot-scheduler-design.md`

---

## File Structure

```
DayPilot/
├── Package.swift
├── Sources/
│   ├── DayPilotApp.swift
│   ├── Models/
│   │   ├── TodoItem.swift
│   │   ├── MemoryContext.swift
│   │   └── DayQueue.swift
│   ├── Services/
│   │   ├── DurationParser.swift
│   │   ├── TodoParser.swift
│   │   ├── MemoryParser.swift
│   │   ├── Scheduler.swift
│   │   └── FileWatcher.swift
│   ├── ScheduleStore.swift
│   └── Views/
│       ├── ScheduleView.swift
│       ├── TaskSectionView.swift
│       ├── TaskRowView.swift
│       └── AddTaskView.swift
├── Tests/
│   ├── DurationParserTests.swift
│   ├── TodoParserTests.swift
│   ├── MemoryParserTests.swift
│   └── SchedulerTests.swift
```

**Responsibilities:**
- `DurationParser.swift` — Parses duration strings ("4h", "30m", "1h30m") into minutes
- `TodoItem.swift` — Task model with title, project, effort, deadline, completion status, line index
- `MemoryContext.swift` — Holds projects list and daily_capacity
- `DayQueue.swift` — Three arrays: today, tomorrow, backlog
- `TodoParser.swift` — Reads/writes todos.md, preserves non-task lines
- `MemoryParser.swift` — Reads memory.md, extracts projects + settings
- `Scheduler.swift` — Pure function: sorts tasks, fills capacity buckets
- `FileWatcher.swift` — Per-file DispatchSource monitoring with debounce, lock-protected state, and self-edit guard
- `ScheduleStore.swift` — @Observable, orchestrates parse → schedule → state
- Views — SwiftUI popover UI

---

### Task 1: Package.swift + Project Skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/DayPilotApp.swift`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DayPilot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DayPilot",
            path: "Sources",
            swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]
        ),
        .testTarget(
            name: "DayPilotTests",
            dependencies: ["DayPilot"],
            path: "Tests"
        ),
    ]
)
```

- [ ] **Step 2: Create minimal app entry point**

```swift
import SwiftUI

@main
struct DayPilotApp: App {
    var body: some Scene {
        MenuBarExtra("DayPilot", systemImage: "checklist.checked") {
            Text("DayPilot loading...")
                .padding()
        }
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `cd /Users/rahmonberdivahabov/Projects/DayPilot && swift build 2>&1`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git init
git add Package.swift Sources/DayPilotApp.swift
git commit -m "feat: scaffold Swift package with menubar entry point"
```

---

### Task 2: Duration Parser (TDD)

**Files:**
- Create: `Sources/Services/DurationParser.swift`
- Create: `Tests/DurationParserTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
@testable import DayPilot

@Suite("DurationParser")
struct DurationParserTests {
    @Test func parsesMinutesOnly() {
        #expect(DurationParser.parseMinutes("30m") == 30)
    }

    @Test func parsesHoursOnly() {
        #expect(DurationParser.parseMinutes("4h") == 240)
    }

    @Test func parsesHoursAndMinutes() {
        #expect(DurationParser.parseMinutes("1h30m") == 90)
    }

    @Test func invalidStringDefaults() {
        #expect(DurationParser.parseMinutes("garbage") == 15)
    }

    @Test func emptyStringDefaults() {
        #expect(DurationParser.parseMinutes("") == 15)
    }

    @Test func formatsMinutesAsString() {
        #expect(DurationParser.format(minutes: 90) == "1h 30m")
        #expect(DurationParser.format(minutes: 30) == "30m")
        #expect(DurationParser.format(minutes: 120) == "2h")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -20`
Expected: Compilation error — `DurationParser` not found

- [ ] **Step 3: Implement DurationParser**

```swift
import Foundation

enum DurationParser {
    private static let pattern = /^(?:(\d+)h)?(?:(\d+)m)?$/

    static func parseMinutes(_ string: String) -> Int {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.wholeMatch(of: pattern),
              (match.1 != nil || match.2 != nil) else {
            return 15
        }
        let hours = match.1.map { Int($0)! } ?? 0
        let mins = match.2.map { Int($0)! } ?? 0
        return hours * 60 + mins
    }

    static func format(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        switch (h, m) {
        case (0, let m): return "\(m)m"
        case (let h, 0): return "\(h)h"
        case (let h, let m): return "\(h)h \(m)m"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -20`
Expected: All 6 tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/Services/DurationParser.swift Tests/DurationParserTests.swift
git commit -m "feat: add DurationParser with TDD"
```

---

### Task 3: TodoItem Model

**Files:**
- Create: `Sources/Models/TodoItem.swift`

- [ ] **Step 1: Create TodoItem model**

```swift
import Foundation

struct TodoItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var project: String?
    var effortMinutes: Int
    var deadline: Date?
    var isCompleted: Bool
    var lineIndex: Int  // position in the original file for write-back

    init(
        id: UUID = UUID(),
        title: String,
        project: String? = nil,
        effortMinutes: Int = 15,
        deadline: Date? = nil,
        isCompleted: Bool = false,
        lineIndex: Int = -1
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.effortMinutes = effortMinutes
        self.deadline = deadline
        self.isCompleted = isCompleted
        self.lineIndex = lineIndex
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/Models/TodoItem.swift
git commit -m "feat: add TodoItem model"
```

---

### Task 4: TodoParser (TDD)

**Files:**
- Create: `Sources/Services/TodoParser.swift`
- Create: `Tests/TodoParserTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
import Foundation
@testable import DayPilot

@Suite("TodoParser")
struct TodoParserTests {
    @Test func parsesFullTask() {
        let lines = ["- [ ] Build UI | project: DayPilot | effort: 1h | deadline: 2026-03-20"]
        let result = TodoParser.parse(lines: lines)
        #expect(result.count == 1)
        #expect(result[0].title == "Build UI")
        #expect(result[0].project == "DayPilot")
        #expect(result[0].effortMinutes == 60)
        #expect(result[0].isCompleted == false)
    }

    @Test func parsesMinimalTask() {
        let lines = ["- [ ] Quick thing"]
        let result = TodoParser.parse(lines: lines)
        #expect(result.count == 1)
        #expect(result[0].title == "Quick thing")
        #expect(result[0].project == nil)
        #expect(result[0].effortMinutes == 15)
        #expect(result[0].deadline == nil)
    }

    @Test func skipsCompletedTasks() {
        let lines = [
            "- [x] Done task",
            "- [ ] Open task",
        ]
        let result = TodoParser.parse(lines: lines)
        #expect(result.count == 1)
        #expect(result[0].title == "Open task")
    }

    @Test func skipsNonTaskLines() {
        let lines = [
            "# My Todos",
            "",
            "- [ ] Real task",
            "Some random text",
        ]
        let result = TodoParser.parse(lines: lines)
        #expect(result.count == 1)
        #expect(result[0].title == "Real task")
    }

    @Test func marksTaskComplete() {
        var lines = [
            "- [ ] Task one",
            "- [ ] Task two",
        ]
        TodoParser.markComplete(lines: &lines, at: 0)
        #expect(lines[0] == "- [x] Task one")
        #expect(lines[1] == "- [ ] Task two")
    }

    @Test func appendsNewTask() {
        var lines = ["- [ ] Existing"]
        TodoParser.append(lines: &lines, raw: "New task | project: Test | effort: 45m")
        #expect(lines.count == 2)
        #expect(lines[1] == "- [ ] New task | project: Test | effort: 45m")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -20`
Expected: Compilation error — `TodoParser` not found

- [ ] **Step 3: Implement TodoParser**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -20`
Expected: All 6 TodoParser tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/Services/TodoParser.swift Tests/TodoParserTests.swift
git commit -m "feat: add TodoParser with TDD"
```

---

### Task 5: MemoryContext Model + MemoryParser (TDD)

**Files:**
- Create: `Sources/Models/MemoryContext.swift`
- Create: `Sources/Services/MemoryParser.swift`
- Create: `Tests/MemoryParserTests.swift`

- [ ] **Step 1: Create MemoryContext model**

```swift
import Foundation

struct ProjectInfo: Equatable {
    let name: String
    let priority: Int
    let deadline: Date?
}

struct MemoryContext: Equatable {
    var projects: [ProjectInfo]
    var dailyCapacityMinutes: Int

    init(projects: [ProjectInfo] = [], dailyCapacityMinutes: Int = 240) {
        self.projects = projects
        self.dailyCapacityMinutes = dailyCapacityMinutes
    }

    func priority(for projectName: String?) -> Int {
        guard let name = projectName,
              let project = projects.first(where: { $0.name == name }) else {
            return Int.max
        }
        return project.priority
    }
}
```

- [ ] **Step 2: Write failing MemoryParser tests**

```swift
import Testing
import Foundation
@testable import DayPilot

@Suite("MemoryParser")
struct MemoryParserTests {
    @Test func parsesProjects() {
        let content = """
        ## Projects
        - QuizPilot | priority: 1 | deadline: 2026-04-01
        - DayPilot | priority: 2

        ## Settings
        daily_capacity: 4h
        """
        let ctx = MemoryParser.parse(content: content)
        #expect(ctx.projects.count == 2)
        #expect(ctx.projects[0].name == "QuizPilot")
        #expect(ctx.projects[0].priority == 1)
        #expect(ctx.projects[1].name == "DayPilot")
        #expect(ctx.projects[1].priority == 2)
        #expect(ctx.projects[1].deadline == nil)
    }

    @Test func parsesDailyCapacity() {
        let content = """
        ## Settings
        daily_capacity: 6h
        """
        let ctx = MemoryParser.parse(content: content)
        #expect(ctx.dailyCapacityMinutes == 360)
    }

    @Test func defaultsWhenEmpty() {
        let ctx = MemoryParser.parse(content: "")
        #expect(ctx.projects.isEmpty)
        #expect(ctx.dailyCapacityMinutes == 240)
    }

    @Test func ignoresUnknownSections() {
        let content = """
        ## Random Stuff
        blah blah

        ## Settings
        daily_capacity: 2h
        """
        let ctx = MemoryParser.parse(content: content)
        #expect(ctx.dailyCapacityMinutes == 120)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -20`
Expected: Compilation error — `MemoryParser` not found

- [ ] **Step 4: Implement MemoryParser**

```swift
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -20`
Expected: All 4 MemoryParser tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/Models/MemoryContext.swift Sources/Services/MemoryParser.swift Tests/MemoryParserTests.swift
git commit -m "feat: add MemoryContext model and MemoryParser with TDD"
```

---

### Task 6: DayQueue Model + Scheduler (TDD)

**Files:**
- Create: `Sources/Models/DayQueue.swift`
- Create: `Sources/Services/Scheduler.swift`
- Create: `Tests/SchedulerTests.swift`

- [ ] **Step 1: Create DayQueue model**

```swift
struct DayQueue: Equatable {
    var today: [TodoItem]
    var tomorrow: [TodoItem]
    var backlog: [TodoItem]

    init(today: [TodoItem] = [], tomorrow: [TodoItem] = [], backlog: [TodoItem] = []) {
        self.today = today
        self.tomorrow = tomorrow
        self.backlog = backlog
    }

    var todayEffort: Int { today.reduce(0) { $0 + $1.effortMinutes } }
    var tomorrowEffort: Int { tomorrow.reduce(0) { $0 + $1.effortMinutes } }
}
```

- [ ] **Step 2: Write failing Scheduler tests**

```swift
import Testing
import Foundation
@testable import DayPilot

@Suite("Scheduler")
struct SchedulerTests {
    let context = MemoryContext(
        projects: [
            ProjectInfo(name: "Alpha", priority: 1, deadline: nil),
            ProjectInfo(name: "Beta", priority: 2, deadline: nil),
        ],
        dailyCapacityMinutes: 60
    )

    @Test func fillsTodayUpToCapacity() {
        let todos = [
            TodoItem(title: "A", project: "Alpha", effortMinutes: 30),
            TodoItem(title: "B", project: "Alpha", effortMinutes: 30),
            TodoItem(title: "C", project: "Alpha", effortMinutes: 30),
        ]
        let queue = Scheduler.schedule(todos: todos, context: context)
        #expect(queue.today.count == 2)
        #expect(queue.todayEffort == 60)
        #expect(queue.tomorrow.count == 1)
    }

    @Test func sortsDeadlineFirst() {
        let soon = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let later = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        let todos = [
            TodoItem(title: "Later", project: "Alpha", effortMinutes: 30, deadline: later),
            TodoItem(title: "Soon", project: "Alpha", effortMinutes: 30, deadline: soon),
        ]
        let queue = Scheduler.schedule(todos: todos, context: context)
        #expect(queue.today[0].title == "Soon")
        #expect(queue.today[1].title == "Later")
    }

    @Test func noDeadlineSortsLast() {
        let soon = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let todos = [
            TodoItem(title: "No deadline", project: "Alpha", effortMinutes: 30),
            TodoItem(title: "Has deadline", project: "Alpha", effortMinutes: 30, deadline: soon),
        ]
        let queue = Scheduler.schedule(todos: todos, context: context)
        #expect(queue.today[0].title == "Has deadline")
        #expect(queue.today[1].title == "No deadline")
    }

    @Test func projectPriorityBreaksTies() {
        let todos = [
            TodoItem(title: "Beta task", project: "Beta", effortMinutes: 30),
            TodoItem(title: "Alpha task", project: "Alpha", effortMinutes: 30),
        ]
        let queue = Scheduler.schedule(todos: todos, context: context)
        #expect(queue.today[0].title == "Alpha task")
        #expect(queue.today[1].title == "Beta task")
    }

    @Test func overflowGoesToBacklog() {
        let todos = (1...5).map { i in
            TodoItem(title: "Task \(i)", project: "Alpha", effortMinutes: 30)
        }
        let queue = Scheduler.schedule(todos: todos, context: context)
        #expect(queue.today.count == 2)
        #expect(queue.tomorrow.count == 2)
        #expect(queue.backlog.count == 1)
    }

    @Test func emptyTodosReturnsEmptyQueue() {
        let queue = Scheduler.schedule(todos: [], context: context)
        #expect(queue.today.isEmpty)
        #expect(queue.tomorrow.isEmpty)
        #expect(queue.backlog.isEmpty)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -20`
Expected: Compilation error — `Scheduler` not found

- [ ] **Step 4: Implement Scheduler**

```swift
import Foundation

enum Scheduler {
    static func schedule(todos: [TodoItem], context: MemoryContext) -> DayQueue {
        let sorted = todos.sorted { a, b in
            let aDeadline = a.deadline ?? Date.distantFuture
            let bDeadline = b.deadline ?? Date.distantFuture
            if aDeadline != bDeadline { return aDeadline < bDeadline }

            let aPriority = context.priority(for: a.project)
            let bPriority = context.priority(for: b.project)
            if aPriority != bPriority { return aPriority < bPriority }

            return a.effortMinutes < b.effortMinutes
        }

        var today: [TodoItem] = []
        var tomorrow: [TodoItem] = []
        var backlog: [TodoItem] = []
        var todayTotal = 0
        var tomorrowTotal = 0
        let cap = context.dailyCapacityMinutes

        for item in sorted {
            if todayTotal + item.effortMinutes <= cap {
                today.append(item)
                todayTotal += item.effortMinutes
            } else if tomorrowTotal + item.effortMinutes <= cap {
                tomorrow.append(item)
                tomorrowTotal += item.effortMinutes
            } else {
                backlog.append(item)
            }
        }

        return DayQueue(today: today, tomorrow: tomorrow, backlog: backlog)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -20`
Expected: All 6 Scheduler tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/Models/DayQueue.swift Sources/Services/Scheduler.swift Tests/SchedulerTests.swift
git commit -m "feat: add DayQueue model and Scheduler with TDD"
```

---

### Task 7: FileWatcher

**Files:**
- Create: `Sources/Services/FileWatcher.swift`

- [ ] **Step 1: Implement FileWatcher**

```swift
import Foundation

/// Watches individual files for content changes using DispatchSource per file.
/// Uses a lock to protect mutable state accessed from multiple threads.
final class FileWatcher {
    private let onChange: () -> Void
    private let debounceInterval: TimeInterval = 0.5
    private let lock = NSLock()
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private var debounceWorkItem: DispatchWorkItem?
    private var _isSelfEditing = false

    var isSelfEditing: Bool {
        get { lock.withLock { _isSelfEditing } }
        set { lock.withLock { _isSelfEditing = newValue } }
    }

    init?(filePaths: [String], onChange: @escaping () -> Void) {
        self.onChange = onChange

        for path in filePaths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            fileDescriptors.append(fd)

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete],
                queue: DispatchQueue.global(qos: .utility)
            )
            sources.append(source)

            source.setEventHandler { [weak self] in
                guard let self else { return }
                if self.isSelfEditing {
                    self.isSelfEditing = false
                    return
                }
                self.lock.withLock {
                    self.debounceWorkItem?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        self?.onChange()
                    }
                    self.debounceWorkItem = work
                    DispatchQueue.global(qos: .utility).asyncAfter(
                        deadline: .now() + self.debounceInterval, execute: work
                    )
                }
            }

            source.setCancelHandler {
                close(fd)
            }

            source.resume()
        }

        guard !sources.isEmpty else { return nil }
    }

    deinit {
        for source in sources {
            source.cancel()
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/Services/FileWatcher.swift
git commit -m "feat: add FileWatcher with debounce and self-edit guard"
```

---

### Task 8: ScheduleStore

**Files:**
- Create: `Sources/ScheduleStore.swift`

- [ ] **Step 1: Implement ScheduleStore**

```swift
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
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/ScheduleStore.swift
git commit -m "feat: add ScheduleStore as central state manager"
```

---

### Task 9: Views — TaskRowView + TaskSectionView

**Files:**
- Create: `Sources/Views/TaskRowView.swift`
- Create: `Sources/Views/TaskSectionView.swift`

- [ ] **Step 1: Create TaskRowView**

```swift
import SwiftUI

struct TaskRowView: View {
    let index: Int
    let item: TodoItem
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onComplete) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Text("\(index).")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)

            Text(item.title)
                .lineLimit(1)

            Spacer()

            if let project = item.project {
                Text(project)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(pillColor(for: project).opacity(0.2))
                    .foregroundStyle(pillColor(for: project))
                    .clipShape(Capsule())
            }

            Text(DurationParser.format(minutes: item.effortMinutes))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private func pillColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .mint, .brown]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}
```

- [ ] **Step 2: Create TaskSectionView**

```swift
import SwiftUI

struct TaskSectionView: View {
    let title: String
    let subtitle: String?
    @Binding var items: [TodoItem]
    let section: ScheduleStore.Section
    let store: ScheduleStore
    var collapsible: Bool = false

    @State private var isExpanded: Bool

    init(title: String, subtitle: String?, items: Binding<[TodoItem]>, section: ScheduleStore.Section, store: ScheduleStore, collapsible: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self._items = items
        self.section = section
        self.store = store
        self.collapsible = collapsible
        self._isExpanded = State(initialValue: !collapsible)
    }

    var body: some View {
        if !items.isEmpty || !collapsible {
            VStack(alignment: .leading, spacing: 4) {
                header
                if isExpanded {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        TaskRowView(index: index + 1, item: item) {
                            store.completeTask(item)
                        }
                    }
                    .onMove { source, destination in
                        store.moveTask(from: source, to: destination, in: section)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            if collapsible {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        Text(title)
                            .font(.headline)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(title)
                    .font(.headline)
            }

            Spacer()

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/Views/TaskRowView.swift Sources/Views/TaskSectionView.swift
git commit -m "feat: add TaskRowView and TaskSectionView"
```

---

### Task 10: Views — AddTaskView + ScheduleView

**Files:**
- Create: `Sources/Views/AddTaskView.swift`
- Create: `Sources/Views/ScheduleView.swift`

- [ ] **Step 1: Create AddTaskView**

```swift
import SwiftUI

struct AddTaskView: View {
    let store: ScheduleStore
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("Task | project: X | effort: 30m", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { add() }

            Button("Add") { add() }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        store.addTask(raw: text)
        text = ""
    }
}
```

- [ ] **Step 2: Create ScheduleView**

```swift
import SwiftUI

struct ScheduleView: View {
    @State var store = ScheduleStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = store.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                List {
                    TaskSectionView(
                        title: "Today",
                        subtitle: "\(DurationParser.format(minutes: store.queue.todayEffort)) / \(DurationParser.format(minutes: store.context.dailyCapacityMinutes))",
                        items: $store.queue.today,
                        section: .today,
                        store: store
                    )

                    TaskSectionView(
                        title: "Tomorrow",
                        subtitle: DurationParser.format(minutes: store.queue.tomorrowEffort),
                        items: $store.queue.tomorrow,
                        section: .tomorrow,
                        store: store
                    )

                    if !store.queue.backlog.isEmpty {
                        TaskSectionView(
                            title: "Backlog",
                            subtitle: "\(store.queue.backlog.count) tasks",
                            items: $store.queue.backlog,
                            section: .backlog,
                            store: store,
                            collapsible: true
                        )
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            AddTaskView(store: store)
                .padding(12)

            Button(action: { store.recompute() }) {
                Text("Reschedule")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 320, height: 480)
        .onAppear { store.start() }
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/Views/AddTaskView.swift Sources/Views/ScheduleView.swift
git commit -m "feat: add AddTaskView and ScheduleView"
```

---

### Task 11: Wire Up App Entry Point + Create Sample Files

**Files:**
- Modify: `Sources/DayPilotApp.swift`

- [ ] **Step 1: Update DayPilotApp to use ScheduleView**

```swift
import SwiftUI

@main
struct DayPilotApp: App {
    var body: some Scene {
        MenuBarExtra("DayPilot", systemImage: "checklist.checked") {
            ScheduleView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 2: Create ~/scheduler/ with sample files**

```bash
mkdir -p ~/scheduler

cat > ~/scheduler/todos.md << 'EOF'
# Todos

- [ ] Build DayPilot UI | project: DayPilot | effort: 1h30m | deadline: 2026-03-18
- [ ] Write parser tests | project: DayPilot | effort: 45m
- [ ] Review QuizPilot PR | project: QuizPilot | effort: 30m | deadline: 2026-03-17
- [ ] Plan API endpoints | project: QuizPilot | effort: 1h | deadline: 2026-03-19
- [ ] Read SwiftUI docs | effort: 30m
- [ ] Grocery shopping | effort: 45m
- [x] Set up project skeleton | project: DayPilot | effort: 15m
EOF

cat > ~/scheduler/memory.md << 'EOF'
## Projects
- QuizPilot | priority: 1 | deadline: 2026-04-01
- DayPilot | priority: 2

## Settings
daily_capacity: 4h

## Current Focus
Ship QuizPilot MVP this week
EOF
```

- [ ] **Step 3: Build and run**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds. Run with `swift run` to verify menubar icon appears.

- [ ] **Step 4: Commit**

```bash
git add Sources/DayPilotApp.swift
git commit -m "feat: wire up ScheduleView to MenuBarExtra and create sample data"
```

---

### Task 12: Final Build + Smoke Test

- [ ] **Step 1: Run full test suite**

Run: `cd /Users/rahmonberdivahabov/Projects/DayPilot && swift test 2>&1`
Expected: All tests pass (22 total across 4 test suites)

- [ ] **Step 2: Clean build**

Run: `swift build -c release 2>&1 | tail -10`
Expected: Release build succeeds

- [ ] **Step 3: Run the app**

Run: `swift run &` then manually verify:
- Menubar icon appears (checklist.checked)
- Clicking shows popover with Today/Tomorrow/Backlog
- Sample tasks sorted correctly (QuizPilot review first — deadline today)
- Add task works
- Reschedule works

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: DayPilot v1 — macOS menubar scheduler"
```
