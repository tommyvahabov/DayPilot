# DayPilot v2 "Flight Deck" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the v2 Flight Deck spec: bug fixes, menubar HUD + ETA, Go-Around reflow, pre/post-flight rituals with ritual streak, and the Claude-symbiosis layer (proposals, provenance, calibration, auto-git, briefing).

**Architecture:** All state flows through markdown files (`~/scheduler/{todos,memory,done,briefing}.md`). New semantics are pipe tokens on task lines (`defer:`, `carried:`, `by:`) plus a `- [?]` proposed state, blockquote ritual markers in done.md, and a `## Calibration` section in memory.md. The Swift `Scheduler` stays deterministic; Claude (via the MCP server) supplies judgment through the same files.

**Tech Stack:** SwiftUI/AppKit (SPM, macOS), XCTest, Carbon HotKey API, `/usr/bin/git` via Process. No new dependencies.

**Build/test commands:** `swift build` and `swift test` from repo root. Commit after each task.

---

## Phase 0 — Fix the lies

### Task 1: Stable project colors

**Files:** Create `Sources/Views/ProjectColor.swift`; Modify `Sources/Views/TaskRowView.swift:157-161`, `Sources/Views/FlightLogView.swift:210-214`

- [ ] Create the helper (djb2 over UTF-8 — `String.hashValue` is process-seeded, colors changed every launch):

```swift
import SwiftUI

enum ProjectColor {
    private static let palette: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .mint, .brown]

    static func color(for name: String) -> Color {
        var hash: UInt64 = 5381
        for byte in name.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
```

- [ ] Delete the private `pillColor(for:)` funcs in TaskRowView and FlightLogView; replace call sites with `ProjectColor.color(for: project)`.
- [ ] `swift build` passes. Commit: `fix: stable project pill colors across launches`

### Task 2: File-order scheduling + persistent manual reorder

**Files:** Modify `Sources/Services/Scheduler.swift:14`, `Sources/ScheduleStore.swift:229-235,412-415`, `Sources/Services/TodoParser.swift`, `Sources/Views/TaskSectionView.swift:51-69`, `Sources/Views/SectionCardView.swift:35-53`; Test `Tests/SchedulerTests.swift`

- [ ] Failing test: equal deadline/priority tasks keep file order, not effort order:

```swift
func testTieBreakIsFileOrder() {
    let todos = [
        TodoItem(title: "Big first", effortMinutes: 60, lineIndex: 1),
        TodoItem(title: "Small second", effortMinutes: 15, lineIndex: 2),
    ]
    let q = Scheduler.schedule(todos: todos, context: MemoryContext())
    XCTAssertEqual(q.today.map(\.title), ["Big first", "Small second"])
}
```

- [ ] In `Scheduler.schedule` replace `return a.effortMinutes < b.effortMinutes` with `return a.lineIndex < b.lineIndex`. Test passes (existing effort-tiebreak tests must be updated to use lineIndex expectations).
- [ ] Expose note-block length in TodoParser (mirror of the private logic in `updateNotes`):

```swift
static func noteLineCount(lines: [String], at lineIndex: Int) -> Int {
    var count = 0
    var j = lineIndex + 1
    while j < lines.count {
        let line = lines[j]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty,
              (line.hasPrefix("  ") || line.hasPrefix("\t")),
              !trimmed.hasPrefix("- [ ] "), !trimmed.hasPrefix("- [x] "), !trimmed.hasPrefix("- [?] ") else { break }
        count += 1
        j += 1
    }
    return count
}
```

- [ ] Replace `ScheduleStore.moveTask` with a persisting version that moves the task's line block in the file:

```swift
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
    if fromIndex < toIndex {  // moving down → place after target block
        insertAt = targetLine + 1 + TodoParser.noteLineCount(lines: rawTodoLines, at: targetLine)
    } else {                  // moving up → place before target
        insertAt = targetLine
    }
    rawTodoLines.insert(contentsOf: block, at: insertAt)
    fileWatcher?.isSelfEditing = true
    writeBack()
    recompute()
}
```

(`rawTodoLines` is `private(set)`; this lives in the store so no access change needed.)

- [ ] In both `TaskSectionView` and `SectionCardView`, replace the `dropDestination` body's `items.move(...)` with `store.moveTask(id:toIndex:in:)`. `SectionCardView` needs a `let section: ScheduleStore.Section` property added; pass `.today`/`.tomorrow`/`.backlog` from `TodayView`/`RunwayDashboardView` call sites to match each card.
- [ ] `swift test` green. Commit: `fix: manual reorder persists to todos.md; file order is the scheduling tiebreak`

### Task 3: Phase-0 small fixes batch

**Files:** Modify `Sources/Views/ProgressBarView.swift`, `Sources/DayPilotApp.swift:83`, `Sources/Views/SettingsView.swift:102`, `Sources/Views/MainWindowView.swift:103-117`, `Sources/Views/TodayView.swift:6-8,86-93`, `Sources/Views/ScheduleContentView.swift`, `Sources/Views/TaskRowView.swift:17-31`

- [ ] ProgressBarView — completion semantics (green throughout, no red at 100%):

```swift
private var color: Color {
    progress >= 1.0 ? .green : .green.opacity(0.9)
}
```

and fill background `Color.primary.opacity(0.08)`.
- [ ] `defaultSize(width: 980, height: 600)` in DayPilotApp.
- [ ] SettingsView about subtitle: `"DayPilot v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") — by Pilot AI"`.
- [ ] MainWindowView footer status dot: green + "Watching files" when `store.errorMessage == nil`, red + "File error" otherwise (store already exposes `errorMessage`).
- [ ] TodayView greeting: add `private static var greetingShownThisLaunch = false`; skip the flip (start with `showGreeting = false`) when already shown; set it true in `onAppear`.
- [ ] ScheduleContentView: delete `expandedLayout` and the `compact` branch (always compact); error state gets `arrow.trianglehead.2.clockwise` Retry button calling `store.recompute()` and its own icon `doc.questionmark`.
- [ ] TaskRowView `triggerComplete`: flight `easeIn(duration: 0.7)`, title fade `0.4` delay `0.25`, `asyncAfter(.now() + 0.8)`.
- [ ] Done-section double-dim: remove `.opacity(0.6)` (ScheduleContentView) and `.opacity(0.85)` (TodayView/RunwayDashboardView around "Done today" cards).
- [ ] `swift build`. Commit: `fix: phase-0 polish (progress color, window size, version, status dot, greeting, error retry, anim timing)`

## Phase 1 — HUD + ETA + caution

### Task 4: Store flight math

**Files:** Modify `Sources/ScheduleStore.swift`, `Sources/Models/MemoryContext.swift`; Test `Tests/SchedulerTests.swift` (pure helpers)

- [ ] Add to MemoryContext (defaults preserve current NowCard behavior):

```swift
struct EnergyBlocks: Equatable {
    var deepWorkStart = 5, deepWorkEnd = 12
    var lightEnd = 17
    var adminEnd = 22
}
// in MemoryContext:
var energy = EnergyBlocks()
```

- [ ] Pure helper in Scheduler + failing tests first:

```swift
static func wheelsDown(now: Date, remainingMinutes: Int) -> Date {
    now.addingTimeInterval(TimeInterval(remainingMinutes * 60))
}

static func cautionActive(now: Date, remainingMinutes: Int, minutesDoneToday: Int, context: MemoryContext) -> Bool {
    let cal = Calendar.current
    let endOfDay = cal.date(bySettingHour: context.energy.adminEnd, minute: 0, second: 0, of: now) ?? now
    let overrunsDay = wheelsDown(now: now, remainingMinutes: remainingMinutes) > endOfDay
    let overCapacity = remainingMinutes > max(0, context.dailyCapacityMinutes - minutesDoneToday)
    return overrunsDay || overCapacity
}
```

Tests: remaining fits before adminEnd and under capacity → false; past 22:00 → true; remaining > capacity−done → true.
- [ ] Store computed properties (effective effort comes in Task 12; raw for now):

```swift
var remainingTodayMinutes: Int { queue.today.reduce(0) { $0 + $1.effortMinutes } }
var minutesDoneToday: Int { queue.completedToday.reduce(0) { $0 + $1.effortMinutes } }
var wheelsDownDate: Date { Scheduler.wheelsDown(now: Date(), remainingMinutes: remainingTodayMinutes) }
var cautionActive: Bool {
    !queue.today.isEmpty && Scheduler.cautionActive(now: Date(), remainingMinutes: remainingTodayMinutes, minutesDoneToday: minutesDoneToday, context: context)
}
```

- [ ] `swift test` green. Commit: `feat: wheels-down ETA and master-caution math`

### Task 5: Menubar HUD label + Settings card + NowCard ETA

**Files:** Create `Sources/Views/MenubarHUDLabel.swift`; Modify `Sources/DayPilotApp.swift:60-75`, `Sources/Views/SettingsView.swift`, `Sources/Views/NowCardView.swift:160-167` (footer)

- [ ] New label view (TimelineView drives minute refresh; observation drives data refresh):

```swift
import SwiftUI

struct MenubarHUDLabel: View {
    let store: ScheduleStore
    @AppStorage("hudMode") private var mode: String = "compact"

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "H:mm"; return f
    }()

    var body: some View {
        TimelineView(.everyMinute) { _ in
            HStack(spacing: 3) {
                if store.cautionActive {
                    Image(systemName: "exclamationmark.triangle.fill")
                } else if let nsImage = DayPilotApp.menubarImage {
                    Image(nsImage: nsImage).renderingMode(.original)
                } else {
                    Image(systemName: "checklist.checked")
                }
                if mode != "icon", let text = hudText {
                    Text(text)
                }
            }
        }
        .onAppear { store.start() }
    }

    private var hudText: String? {
        guard store.errorMessage == nil else { return nil }
        let remaining = store.remainingTodayMinutes
        guard remaining > 0 else { return nil }
        let time = store.cautionActive
            ? "↓\(Self.timeFormatter.string(from: store.wheelsDownDate))"
            : DurationParser.format(minutes: remaining)
        if mode == "full", let top = store.queue.today.first {
            return "\(String(top.title.prefix(28))) · \(time)"
        }
        return time
    }
}
```

- [ ] DayPilotApp: replace the `label:` group with `MenubarHUDLabel(store: store).modifier(WindowOpenerBinder())`.
- [ ] SettingsView: new card "Menubar HUD" (icon `gauge.open.with.lines.needle.33percent`) with a segmented `Picker` over `@AppStorage("hudMode")`: Icon only / Time left / Task + time.
- [ ] NowCardView footer: third stat `stat(value: wheelsDownString, label: "wheels down")` colored `.red` when `store.cautionActive` (NowCardView already holds `store`; compute from `store.wheelsDownDate`).
- [ ] `swift build`; run app, verify label modes. Commit: `feat: menubar HUD with ETA and master caution`

## Phase 2 — tokens, defer, Go-Around

### Task 6: Token round-trip helpers + new TodoItem fields

**Files:** Modify `Sources/Services/TodoParser.swift`, `Sources/Models/TodoItem.swift`; Test `Tests/TodoParserTests.swift`

- [ ] Failing tests:

```swift
func testParsesNewTokens() {
    let items = TodoParser.parse(lines: ["- [ ] T | project: X | defer: 2026-06-12 | carried: 2 | by: claude"])
    XCTAssertEqual(items[0].carried, 2)
    XCTAssertEqual(items[0].addedBy, "claude")
    XCTAssertNotNil(items[0].deferUntil)
}

func testSetTokenReplacesAndRemoves() {
    let line = "- [ ] T | effort: 30m | carried: 1"
    let bumped = TodoParser.setToken(line: line, key: "carried", value: "2")
    XCTAssertTrue(bumped.contains("carried: 2"))
    XCTAssertFalse(bumped.contains("carried: 1"))
    XCTAssertTrue(bumped.contains("effort: 30m"))
    let removed = TodoParser.setToken(line: bumped, key: "carried", value: nil)
    XCTAssertFalse(removed.contains("carried:"))
}

func testProposedTasksParseSeparately() {
    let lines = ["- [?] Maybe | project: X", "- [ ] Real"]
    XCTAssertEqual(TodoParser.parse(lines: lines).map(\.title), ["Real"])
    XCTAssertEqual(TodoParser.proposals(lines: lines).map(\.title), ["Maybe"])
}
```

- [ ] TodoItem gains `var deferUntil: Date?`, `var carried: Int = 0`, `var addedBy: String?`, `var isProposed: Bool = false`, `var rationale: String?` (all with defaults in init; `rationale` excluded from `Equatable` is unnecessary — keep memberwise equality, it's derived but stable per recompute).
- [ ] `parseFields` handles `defer:` (dateFormatter), `carried:` (Int), `by:` (string). `parse`/`parseAll` skip `- [?] `; new `proposals(lines:)` parses `- [?] ` lines with `isProposed: true`. `noteLineCount`/`collectNotes` guards include `- [?] `.
- [ ] `setToken`:

```swift
static func setToken(line: String, key: String, value: String?) -> String {
    var parts = line.split(separator: "|", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
    parts.removeAll { $0.lowercased().hasPrefix("\(key.lowercased()):") }
    if let value { parts.append("\(key): \(value)") }
    return parts.joined(separator: " | ")
}
```

- [ ] `swift test` green. Commit: `feat: defer/carried/by tokens and proposed [?] state in todo parser`

### Task 7: Scheduler honors defer

**Files:** Modify `Sources/Services/Scheduler.swift`; Test `Tests/SchedulerTests.swift`

- [ ] Failing tests: deferUntil tomorrow lands in tomorrow even when today has room; deferUntil +3 days lands in backlog.
- [ ] In the packing loop, before capacity checks:

```swift
let cal = Calendar.current
let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: today))!
// inside loop:
if let d = item.deferUntil, d >= startOfTomorrow {
    if cal.isDate(d, inSameDayAs: startOfTomorrow), tomorrowTotal + item.effortMinutes <= cap {
        tomorrow.append(item); tomorrowTotal += item.effortMinutes
    } else {
        backlog.append(item)
    }
    continue
}
```

`schedule` gains `today: Date = Date()` parameter for testability.
- [ ] `swift test` green. Commit: `feat: scheduler honors defer dates`

### Task 8: Reflow + Go-Around UI

**Files:** Modify `Sources/Services/Scheduler.swift`, `Sources/ScheduleStore.swift`, `Sources/Views/ScheduleView.swift:23-31`, `Sources/Views/RunwayDashboardView.swift:150-155`; Test `Tests/SchedulerTests.swift`

- [ ] Failing tests with fixed `now` (14:00, capacity 6h, 2h done → available = min(8h-to-22:00, 4h) = 4h): tasks fitting 4h kept, rest diverted.

```swift
static func reflow(todos: [TodoItem], context: MemoryContext, now: Date, minutesDoneToday: Int) -> (kept: [TodoItem], diverted: [TodoItem]) {
    let cal = Calendar.current
    let endOfDay = cal.date(bySettingHour: context.energy.adminEnd, minute: 0, second: 0, of: now) ?? now
    let untilEnd = max(0, Int(endOfDay.timeIntervalSince(now) / 60))
    let available = min(untilEnd, max(0, context.dailyCapacityMinutes - minutesDoneToday))
    let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!

    var kept: [TodoItem] = [], diverted: [TodoItem] = [], used = 0
    let sorted = todos.sorted { /* same comparator as schedule */ }
    for item in sorted {
        if let d = item.deferUntil, d >= startOfTomorrow { continue }  // not today's problem
        if used + item.effortMinutes <= available {
            kept.append(item); used += item.effortMinutes
        } else {
            diverted.append(item)
        }
    }
    return (kept, diverted)
}
```

(Extract the shared comparator into `private static func lessThan(_ a: TodoItem, _ b: TodoItem, context: MemoryContext) -> Bool` used by both `schedule` and `reflow`.)
- [ ] Store:

```swift
struct GoAroundSummary: Equatable { var kept: Int; var diverted: Int }
var lastGoAround: GoAroundSummary?

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
```

- [ ] ScheduleView + RunwayDashboardView: button label `Label("Go-Around", systemImage: "arrow.uturn.up")`, action `store.goAround()`; beneath it (popover) / beside it (window) show `"Go-around: N kept · M diverted"` from `store.lastGoAround`, auto-clearing after 4s via `.task(id:)` + `try? await Task.sleep(for: .seconds(4))`.
- [ ] `swift test` green; manual run. Commit: `feat: Go-Around reflows the day from now, diverts overflow to tomorrow`

### Task 9: Global hotkey ⌃⌥G

**Files:** Create `Sources/Services/HotKeyService.swift`; Modify `Sources/DayPilotApp.swift`

- [ ] Carbon hotkey service (no permissions needed, unlike CGEvent taps):

```swift
import Carbon.HIToolbox

final class HotKeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { service.callback() }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4450_4C54), id: 1)  // 'DPLT'
        RegisterEventHotKey(UInt32(kVK_ANSI_G), UInt32(controlKey | optionKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
```

- [ ] DayPilotApp: `@State private var hotKey: HotKeyService?`; in the label's `.onAppear` (after `store.start()`): `if hotKey == nil { hotKey = HotKeyService { store.goAround() } }`. Settings HUD card mentions "⌃⌥G — Go-Around from anywhere".
- [ ] Build, run, verify hotkey fires outside the app. Commit: `feat: global ⌃⌥G go-around hotkey`

## Phase 3 — rituals

### Task 10: done.md timestamps + ritual markers + model

**Files:** Modify `Sources/ScheduleStore.swift` (logCompletion, parseDoneLog), `Sources/Models/DoneEntry.swift`; Test create `Tests/DoneLogTests.swift`

- [ ] Models: `DoneEntry` gains `var at: String?`; `DoneDay` gains `var preflight: String?`, `var closed: String?` (default nil; update initializers/call sites).
- [ ] `logCompletion` appends `| at: HH:mm` (new `static let clockFormatter` with `"HH:mm"`).
- [ ] `parseDoneLog` parses entry `at:` tokens and, per day, `> preflight HH:mm` / `> closed HH:mm ...` blockquote lines into the day fields. Marker write helper:

```swift
private func appendDayMarker(_ marker: String) {
    // same header-finding logic as logCompletion, inserting "> marker" as the
    // first line under today's header (creating the header if missing)
}
func markPreflight() { appendDayMarker("preflight \(Self.clockFormatter.string(from: Date()))"); recompute() }
```

- [ ] Tests (DoneLogTests): round-trip a synthetic done.md string through a new internal `ScheduleStore`-free parser — extract `parseDoneLog` core into `enum DoneLogParser { static func parse(content: String) -> [DoneDay] }` so it's testable without the store; store delegates to it.
- [ ] `swift test` green. Commit: `feat: done.md gains at: timestamps and preflight/closed day markers`

### Task 11: Ritual streak

**Files:** Create `Sources/Services/RitualStreak.swift`; Modify `Sources/Views/RunwayDashboardView.swift:11,72-78,158-187`; Test `Tests/DoneLogTests.swift`

- [ ] Failing tests: 3 consecutive closed days → 3; gap of 1 day mid-week with closed days around → continues (ground day); two gaps in same ISO week → stops at first; today not closed but yesterday closed → counts from yesterday.

```swift
import Foundation

enum RitualStreak {
    /// Consecutive days with a `closed` marker, walking back from today (or
    /// yesterday, if today isn't closed yet). One missing day per ISO week is
    /// forgiven (a "ground day"); two stops the streak.
    static func compute(days: [DoneDay], today: Date = Date(), calendar: Calendar = .current) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let closedDates = Set(days.filter { $0.closed != nil }.compactMap { formatter.date(from: $0.date) }
            .map { calendar.startOfDay(for: $0) })
        guard !closedDates.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: today)
        if !closedDates.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        var streak = 0
        var freezeUsedInWeek: Int? = nil  // ISO week number the freeze was spent in
        while true {
            if closedDates.contains(cursor) {
                streak += 1
            } else {
                let week = calendar.component(.weekOfYear, from: cursor)
                if freezeUsedInWeek == week { break }
                let dayBefore = calendar.date(byAdding: .day, value: -1, to: cursor)!
                guard closedDates.contains(dayBefore) else { break }  // ≥2-day gap ends it
                freezeUsedInWeek = week
            }
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }
}
```

- [ ] RunwayDashboardView: delete `computeStreak`; stat becomes `value: "\(RitualStreak.compute(days: store.doneLog))"`, label "Flight days", sublabel `streak == 0 ? "Close a day to start" : "Pre-flight + close = a flight day"`.
- [ ] `swift test` green. Commit: `feat: ritual streak with weekly ground-day freeze`

### Task 12: Pre-flight card

**Files:** Create `Sources/Views/PreflightCardView.swift`; Modify `Sources/ScheduleStore.swift`, `Sources/Views/ScheduleView.swift`, `Sources/Views/TodayView.swift`

- [ ] Store: `var preflightDoneToday: Bool` — true when today's `DoneDay.preflight != nil`; `markPreflight()` from Task 10.
- [ ] Card view: shown when `!store.preflightDoneToday && hour < 12 && !store.queue.today.isEmpty`:

```swift
struct PreflightCardView: View {
    let store: ScheduleStore
    // Payload vs runway line:
    //   payload = store.remainingTodayMinutes, runway = store.context.dailyCapacityMinutes
    //   overweight when payload > runway → orange warning row
    // [Begin day] button → store.markPreflight()
    // xmark dismiss → @AppStorage("preflightDismissed") date string for today
}
```

Layout mirrors NowCardView's card style (14pt padding, 14 corner radius, `.background.secondary`, accent border `.orange.opacity(0.18)`); content: "PRE-FLIGHT" caps header, payload/runway stat line, optional "Overweight — consider a go-around after lunch" caption, prominent small **Begin day** button.
- [ ] Insert above NowCardView in ScheduleView and above the Today section card in TodayView.
- [ ] Build + manual check both placements. Commit: `feat: pre-flight morning ritual card`

### Task 13: Post-flight (close the day)

**Files:** Create `Sources/Views/PostflightView.swift`; Modify `Sources/ScheduleStore.swift`, `Sources/Views/ScheduleView.swift`, `Sources/Views/TodayView.swift`

- [ ] Store:

```swift
enum EndOfDayChoice { case tomorrow, backlog, scrap }

func closeDay(decisions: [UUID: EndOfDayChoice]) {
    let shipped = queue.completedToday.count
    var diverted = 0, scrapped = 0
    // Process scraps last-to-first so lineIndexes stay valid during removal.
    let items = queue.today
    let tomorrowStr = Self.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
    var scrapTitles: [String] = []
    for item in items.sorted(by: { $0.lineIndex > $1.lineIndex }) {
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
var dayClosedToday: Bool  // today's DoneDay.closed != nil
```

- [ ] PostflightView: list of `store.queue.today` rows, each with a small segmented picker (Tomorrow / Backlog / Scrap, default Tomorrow) bound to a local `@State private var decisions: [UUID: ScheduleStore.EndOfDayChoice]`; carry badge "missed N flights" shown when `item.carried >= 3`; footer **Close the day** button → `store.closeDay(decisions:)` then dismiss. Empty leftovers → just the close button ("All shipped. Close it out.").
- [ ] Entry points: popover footer button "Close the day" (highlighted `.borderedProminent` after 17:00, hidden when `store.dayClosedToday`); same button in TodayView header area. Present as `.sheet`. After closing: footer shows "🛬 Flight closed — see you tomorrow".
- [ ] Build + manual run-through of all three choices; verify todos.md/done.md output. Commit: `feat: post-flight close-the-day ritual`

### Task 14: Carry badge in task rows

**Files:** Modify `Sources/Views/TaskRowView.swift`

- [ ] After the project pill: when `item.carried >= 3`, show `Label("\(item.carried)", systemImage: "arrow.uturn.right.circle")` styled like the pills, `.orange`, with `.help("Carried \(item.carried) days — still worth hauling?")`.
- [ ] Build. Commit: `feat: carry-count badge on chronic rollover tasks`

## Phase 4 — symbiosis

### Task 15: Calibration + energy parsing

**Files:** Modify `Sources/Services/MemoryParser.swift`, `Sources/Models/MemoryContext.swift`; Test `Tests/MemoryParserTests.swift`

- [ ] Failing tests: `## Calibration` lines `- QuizPilot: 1.8` parse into `context.calibration["quizpilot"] == 1.8`; `deep_work: 9-12` etc. override energy defaults; absent sections keep defaults.
- [ ] MemoryContext: `var calibration: [String: Double] = [:]` (lowercased keys) and

```swift
func calibrationMultiplier(for projectName: String?) -> Double {
    guard let name = projectName?.lowercased() else { return 1.0 }
    return calibration[name] ?? 1.0
}
```

- [ ] MemoryParser: `case "calibration":` parse `- Name: 1.8`; in settings, parse `deep_work: 5-12`, `light: 12-17`, `admin: 17-22` via a small `parseHourRange` helper (`"9-12"` → `(9, 12)`).
- [ ] `swift test` green. Commit: `feat: parse calibration multipliers and energy block hours from memory.md`

### Task 16: Scheduler applies calibration + emits rationale

**Files:** Modify `Sources/Services/Scheduler.swift`, `Sources/ScheduleStore.swift` (remainingTodayMinutes → effective), `Sources/Views/TaskRowView.swift`, `Sources/Views/NowCardView.swift`; Test `Tests/SchedulerTests.swift`

- [ ] Failing test: capacity 60m, two 30m tasks in project with multiplier 1.5 (effective 45m) → second task overflows to tomorrow.
- [ ] `effectiveEffort(item, context) = Int((Double(item.effortMinutes) * context.calibrationMultiplier(for: item.project)).rounded())`; packing and `reflow` use it. ETA in store uses `Scheduler.effectiveEffort` sum.
- [ ] Rationale (assigned to `item.rationale` while packing):

```text
today — deadline Jun 13 · P1 QuizPilot · 45m effective (30m × 1.5) · fits 3h10m/6h
tomorrow — over today's capacity (6h)
backlog — deferred to 2026-06-15
```

Built with a small private `rationale(for:placement:)` formatter; deadline omitted when nil, calibration note omitted at ×1.0.
- [ ] Rows get `.help(item.rationale ?? "")`; NowCard "UP NEXT" block gets the same on the title.
- [ ] `swift test` green. Commit: `feat: calibrated packing with per-task scheduling rationale`

### Task 17: Proposals + provenance UI

**Files:** Modify `Sources/ScheduleStore.swift`, `Sources/Views/ScheduleContentView.swift`, `Sources/Views/TodayView.swift`, `Sources/Views/TaskRowView.swift`; Test `Tests/TodoParserTests.swift` (already covers parsing)

- [ ] Store: `var proposals: [TodoItem]` populated in `recompute()` via `TodoParser.proposals`; ops:

```swift
func acceptProposal(_ item: TodoItem) {
    rawTodoLines[item.lineIndex] = rawTodoLines[item.lineIndex].replacingOccurrences(of: "- [?] ", with: "- [ ] ")
    fileWatcher?.isSelfEditing = true; writeBack(); recompute()
}
func rejectProposal(_ item: TodoItem) {
    let len = 1 + TodoParser.noteLineCount(lines: rawTodoLines, at: item.lineIndex)
    rawTodoLines.removeSubrange(item.lineIndex..<(item.lineIndex + len))
    fileWatcher?.isSelfEditing = true; writeBack()
    appendDayMarker("rejected: \(item.title)")
    recompute()
}
```

- [ ] Proposals section (popover top, above Today; and a SectionCard in TodayView when non-empty): header "PROPOSALS" with `sparkles` icon, indigo accent; each row: sparkle, title, project pill, ✓ button (`acceptProposal`) and ✕ button (`rejectProposal`).
- [ ] Provenance badge in TaskRowView: when `item.addedBy == "claude"`, `Image(systemName: "sparkle")` 9pt indigo before the project pill, `.help("Added by Claude" + (item.notes.first.map { " — \($0)" } ?? ""))`.
- [ ] Build + manual test by hand-writing a `- [?]` line. Commit: `feat: Claude proposals with accept/reject and provenance badges`

### Task 18: Auto-git for ~/scheduler

**Files:** Create `Sources/Services/GitService.swift`; Modify `Sources/ScheduleStore.swift`, `Sources/Views/SettingsView.swift`

- [ ] Service:

```swift
import Foundation

/// Debounced auto-commit of ~/scheduler so every change (app, Claude/MCP, manual
/// edit) becomes an auditable diff. Silent no-op when git is missing or disabled.
final class GitService {
    private let dir: String
    private let queue = DispatchQueue(label: "daypilot.git", qos: .utility)
    private var pending: DispatchWorkItem?

    init(directory: String) { self.dir = directory }

    func commitSoon(_ message: String) {
        guard UserDefaults.standard.object(forKey: "autoGitEnabled") as? Bool ?? true else { return }
        pending?.cancel()
        let dir = self.dir
        let work = DispatchWorkItem { GitService.commitNow(dir: dir, message: message) }
        pending = work
        queue.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private static func commitNow(dir: String, message: String) {
        if !FileManager.default.fileExists(atPath: dir + "/.git") {
            run(["init", "-q"], in: dir)
        }
        run(["add", "-A"], in: dir)
        run(["-c", "user.name=DayPilot", "-c", "user.email=daypilot@local", "commit", "-q", "-m", message], in: dir)
    }

    @discardableResult
    private static func run(_ args: [String], in dir: String) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir] + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
```

- [ ] Store: `private let git = GitService(directory: NSHomeDirectory() + "/scheduler")`; call `git.commitSoon("app: <action>")` at the end of `writeBack()` callers' public ops (complete/uncomplete/add/notes/move/goAround/closeDay → one call inside `writeBack()` itself with a settable `nextCommitMessage` is simpler: set `git.commitSoon(message)` right after each `writeBack()`); in the file-watcher callback, `git.commitSoon("external edit")`.
- [ ] SettingsView Files card gains a `Toggle("Auto-commit changes to git", isOn:)` bound to `@AppStorage("autoGitEnabled")` default true, caption "Every change becomes a diff — Claude included."
- [ ] Build; verify `~/scheduler/.git` appears and commits land after edits. Commit: `feat: auto-git audit trail for ~/scheduler`

### Task 19: Briefing rendering

**Files:** Modify `Sources/ScheduleStore.swift`, `Sources/Views/TodayView.swift`, `Sources/Views/ScheduleView.swift`

- [ ] Store: `var briefing: String?` — in `recompute()`, read `\(schedulerDir)/briefing.md`; if first line matches `# Briefing — <today's yyyy-MM-dd>`, expose the remaining lines joined; else nil.
- [ ] TodayView + popover: when present, a SectionCard-styled box "MORNING BRIEFING" (icon `text.alignleft`, indigo) rendering the body via `Text(LocalizedStringKey(briefing))` (markdown-lite is fine), collapsible in the popover (chevron like Done section).
- [ ] Build + manual test with a hand-written briefing.md. Commit: `feat: render Claude's morning briefing when dated today`

### Task 20: MCP server upgrades

**Files:** Modify `Sources/MCPServer/main.swift`

- [ ] `toolAddTask`: append `| by: claude` always; honor `"defer"` string param (`| defer: <v>`); honor `"proposed": true` → prefix `- [?] ` instead of `- [ ] `. Update tool description + schema (`proposed`: boolean — "propose for human review instead of adding directly; shows accept/reject in DayPilot", `defer`: string YYYY-MM-DD).
- [ ] `logDone`: append `| at: HH:mm` (DateFormatter "HH:mm").
- [ ] New tool `write_briefing` (`content` required): writes `# Briefing — <today>\n\n<content>\n` to briefing.md.
- [ ] Bump serverInfo version to "1.1.0". Build. Commit: `feat(mcp): provenance, proposals, defer, timestamps, write_briefing`

### Task 21: Document the conventions

**Files:** Modify `CLAUDE.md` (project), `README.md` (short mention)

- [ ] CLAUDE.md gains a "## Claude ↔ DayPilot conventions" section: calibration workflow (read done.md `at:` timestamps → write `## Calibration` multipliers via update_memory), briefing (write_briefing each morning when asked), proposals (`proposed: true` for anything speculative), negotiated overload (when capacity math fails, present 2–3 named trade-off bundles in chat; never silently rewrite todos.md), memory ratification (propose memory.md edits, never apply silently).
- [ ] Commit: `docs: Claude↔DayPilot symbiosis conventions`

### Task 22: Final verification + version bump

**Files:** Modify version source (check `bundle.sh` / `release.sh` / Info.plist generation for where CFBundleShortVersionString comes from)

- [ ] `swift build && swift test` — all green.
- [ ] Bump app version to 1.12.0 wherever release scripts define it.
- [ ] Run the app; click through: popover (preflight card, HUD modes, go-around, close day), window (Today, Runway streak, Flight Log, Settings).
- [ ] Commit: `chore: bump version to 1.12.0`

---

## Self-review notes

- Spec coverage: every spec section maps to a task (Phase 0 → 1-3, HUD/ETA → 4-5, tokens/defer/go-around/hotkey → 6-9, rituals → 10-14, symbiosis → 15-21, MCP → 20, docs → 21, verify → 22).
- Cross-task type consistency: `TodoParser.setToken`, `noteLineCount`, `proposals` (Task 6) used in Tasks 8/13/17; `EnergyBlocks`/`context.energy` (Task 4) used in Task 8/16; `appendDayMarker`/`clockFormatter` (Task 10) used in 13/17; `EndOfDayChoice` defined once (Task 13).
- Known risk: store `lineIndex` invalidation during batch ops — `closeDay` processes descending lineIndex before any removal-dependent reads; `moveTask` adjusts target index after removal. Both covered above.
