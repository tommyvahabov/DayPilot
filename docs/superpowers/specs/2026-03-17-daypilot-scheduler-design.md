# DayPilot — macOS Menubar Scheduler

## Overview

A native macOS menubar app that reads two local markdown files (`~/scheduler/memory.md` and `~/scheduler/todos.md`) and presents a priority-queue-based daily schedule. No backend, no API, no AI — pure local Swift.

> **Design decision:** The original concept included time-block scheduling with energy patterns (morning = deep work, afternoon = light tasks). This was simplified to a capacity-based queue model — tasks are ranked by priority and fill a daily capacity bucket. No time-of-day assignment. This is simpler, matches how the user actually works (a queue, not a calendar), and avoids the complexity of energy-pattern parsing.

## Tech Stack

- **SwiftUI + AppKit** (macOS 13+ for `MenuBarExtra`)
- **Swift Package** — single executable target, built with `swift build`
- No Xcode project files — just `Package.swift`

## File Sources

| File | Purpose |
|------|---------|
| `~/scheduler/memory.md` | Life context: projects, priorities, daily capacity |
| `~/scheduler/todos.md` | Running task list, read and written by the app |

### todos.md Format

```markdown
- [ ] Task name | project: QuizPilot | effort: 30m | deadline: 2026-03-20
- [x] Completed task name
- [ ] Quick thing
```

**Parsing rules:**
- Each line starting with `- [ ]` or `- [x]` is a task
- Fields after the task name are pipe-delimited and optional: `project:`, `effort:`, `deadline:`
- Lines that don't match this pattern (blanks, headings, comments, malformed) are **preserved as-is** when writing back but **skipped** during parsing
- Minimum valid task: `- [ ] Task name` (no project, effort, or deadline required)

**Defaults for missing fields:**
| Field | Default |
|-------|---------|
| `project` | None — no pill shown |
| `effort` | `15m` — reasonable default so task still counts toward capacity |
| `deadline` | None — sorts after tasks that have deadlines |

### memory.md Format

```markdown
## Projects
- QuizPilot | priority: 1 | deadline: 2026-04-01
- DayPilot | priority: 2

## Settings
daily_capacity: 4h

## Current Focus
Ship QuizPilot MVP this week
```

**Parsing rules:**
- `## Projects` section: each line is `- Name | priority: N | deadline: YYYY-MM-DD` (deadline optional)
- `## Settings` section: key-value pairs, one per line
- `## Current Focus` section: informational, not used by scheduler (future use)
- Other sections are ignored

> **Design decision:** Fixed commitments (uni schedule, etc.) are NOT parsed or used. The original spec included them, but the queue model doesn't need them — the user manages capacity manually via `daily_capacity`. Keeps parsing simple.

### Duration Format

Used for both `effort` and `daily_capacity`. Supported formats:

| Format | Example | Meaning |
|--------|---------|---------|
| `Xh` | `4h` | Hours |
| `Xm` | `30m` | Minutes |
| `XhYm` | `1h30m` | Hours and minutes |

Invalid duration strings default to `15m` and are silently accepted.

## Architecture

Single Swift Package, one executable target.

```
DayPilot/
├── Package.swift
├── Sources/
│   ├── DayPilotApp.swift        # @main, MenuBarExtra setup
│   ├── Views/
│   │   ├── ScheduleView.swift   # Main popover: Today/Tomorrow/Backlog
│   │   ├── TaskRowView.swift    # Numbered row: title, project pill, effort
│   │   └── AddTaskView.swift    # Bottom text field + button
│   ├── Models/
│   │   ├── TodoItem.swift       # Task model
│   │   ├── MemoryContext.swift   # Projects, priorities, daily_capacity
│   │   └── DayQueue.swift       # Today/Tomorrow/Backlog buckets
│   ├── Services/
│   │   ├── TodoParser.swift     # Parses & writes todos.md
│   │   ├── MemoryParser.swift   # Parses memory.md
│   │   ├── Scheduler.swift      # Sorts + fills queues by capacity
│   │   └── FileWatcher.swift    # FSEvents file monitoring
│   └── ScheduleStore.swift      # @Observable, single source of truth
```

### Key Components

**ScheduleStore** (`@Observable`): Single source of truth. Holds the current `DayQueue`, the parsed `MemoryContext`, and methods to add/complete/reorder tasks. All views read from this.

**FileWatcher**: Uses `DispatchSource.makeFileSystemObjectSource` to monitor `~/scheduler/` for changes. Includes a **self-edit guard**: when the app writes to `todos.md`, it sets a flag to suppress the next file-change event, avoiding a redundant recompute cycle. Uses 0.5s debounce for external edits.

**TodoParser**: Reads `todos.md` line-by-line. Preserves all non-task lines (headings, blanks, comments) in a raw line buffer so writes don't destroy file structure. Writes back by replacing only the changed task line.

**MemoryParser**: Reads `memory.md`, extracts projects (name, priority, deadline) and `daily_capacity`. Ignores unrecognized sections.

**Scheduler**: Pure function. Takes `[TodoItem]` + `MemoryContext`, returns `DayQueue`.

## Data Flow

```
App Launch / File Change / Reschedule tap
  → TodoParser.parse(todos.md) → [TodoItem] (uncompleted only)
  → MemoryParser.parse(memory.md) → MemoryContext
  → Scheduler.schedule(todos, context) → DayQueue
  → ScheduleStore updates → Views re-render

Check off task
  → ScheduleStore sets self-edit flag
  → TodoParser writes [x] to todos.md
  → FileWatcher sees change, checks flag, skips recompute

Add task
  → ScheduleStore sets self-edit flag
  → TodoParser appends to todos.md
  → FileWatcher sees change, checks flag, skips recompute
  → ScheduleStore triggers recompute directly

Drag reorder → ScheduleStore updates queue order (manual override, session-only)

External file edit → FileWatcher detects (debounced) → full recompute, discards manual reorders
```

## Scheduling Logic

1. Filter to uncompleted tasks only
2. Sort by: **deadline proximity** (soonest first, no-deadline last) → **project priority** (1 = highest, no-project = lowest) → **effort** (shortest first)
3. Walk sorted list, accumulate effort into **Today** until `daily_capacity` is reached
4. Continue into **Tomorrow** for another `daily_capacity` worth
5. Everything remaining → **Backlog**
6. Manual drag-reorder overrides computed order for the current session only. Any file-triggered recompute or Reschedule tap resets to computed order.

**"Today" is determined by system clock date.** No special midnight handling — if you're working at 1am, it's still "today" per the system. Tomorrow = calendar tomorrow.

## UI Design

**Menubar icon:** SF Symbol `checklist.checked`

**Popover:** ~320px wide, Apple Reminders aesthetic (system fonts, subtle separators)

### Layout (top to bottom)

1. **"Today"** section header — shows total effort vs capacity (e.g. "3h 30m / 4h")
2. **Numbered task list** — draggable rows, numbering restarts per section (1, 2, 3). Each row:
   - Checkbox (left side, tap to complete)
   - Number (position in queue)
   - Task title
   - Project tag pill (colored, rounded) — only shown if task has a project
   - Effort badge (e.g. "30m")
3. **"Tomorrow"** section header — total effort
4. **Numbered task list** — same row format, numbering restarts (1, 2, 3)
5. **"Backlog"** section header — collapsed by default, tap to expand
6. **Numbered task list** — same row format
7. **Divider**
8. **Add task row** — text field (placeholder: `"Task | project: X | effort: 30m"`) + "Add" button
9. **"Reschedule" button** — secondary style, recomputes from scratch

### Project Pill Colors

Colors are derived by hashing the project name to an index into a fixed palette of 8 muted colors. Same project name always gets the same color. No user configuration needed.

### Interactions

- **Check off:** Tap checkbox → marks `[x]` in todos.md → task fades out → recompute
- **Add task:** Type in field, hit Add/Enter → appends to todos.md → recompute
- **Drag reorder:** Drag rows within or between sections to override priority (session-only)
- **Reschedule:** Discards manual reorders, recomputes from files
- **Backlog collapse:** Tap header to toggle visibility

## Behaviour

- **On launch:** Read both files, compute schedule, display today's queue
- **File watching:** Monitor `~/scheduler/` for changes, debounced at 0.5s, auto-recompute on external edits
- **Persistence:** All state derived from the two markdown files. No app-specific storage.
- **Error handling:** If `~/scheduler/` doesn't exist, show empty state with message: "Create ~/scheduler/todos.md to get started"
- **Malformed input:** Skip unparseable lines silently, preserve them on write-back

## What This Does NOT Include

- No AI integration
- No cloud sync
- No accounts or auth
- No onboarding flow
- No settings screen
- No time-of-day scheduling or time blocks
- No energy pattern parsing
- No fixed commitment scheduling
- No notifications
