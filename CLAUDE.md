# Scheduler Menubar App

## App name
DayPilot — macOS menubar scheduler by Pilot AI

## What this is
A native macOS menubar app that acts as my personal scheduling assistant.
Reads two local markdown files and displays my schedule. I interact with it
to add todos and reschedule.

## Files it reads/writes
- `~/scheduler/memory.md` — my life context (projects, priorities, energy patterns, deadlines)
- `~/scheduler/todos.md` — running task list, updated by me and the app

## Tech stack
- SwiftUI + AppKit (macOS only, no iOS)
- MenuBarExtra for the menubar icon
- No backend, no API, no network calls
- Local file reads only

## UI
- Menubar icon: a small calendar or checkmark SF Symbol
- Click opens a popover (not a window), ~320px wide
- Shows today's scheduled tasks in order
- Each task has: title, time block, project tag, done checkbox
- Bottom of popover: text field to add a new todo, "Add" button
- "Reschedule" button that re-reads both markdown files and reorders tasks
- Clean, minimal — think Apple Reminders aesthetic

## Scheduling logic
No AI API. Pure Swift logic:
- Parse todos.md for uncompleted tasks
- Parse memory.md for context (energy patterns, deadlines, project priorities)
- Sort by: deadline proximity > project priority > estimated effort
- Assign to time blocks based on energy pattern in memory.md
- Morning = deep work, afternoon = lighter tasks, evening = admin

## memory.md format
The app reads these fields:
- Projects (name, priority 1-3, deadline if any)
- Energy pattern (e.g. "best focus 9am-12pm, low energy 2-4pm")
- Fixed commitments (uni, Ramadan schedule, etc.)
- Current focus (what matters most this week)

## todos.md format
Each task:
- [ ] Task name | project: QuizPilot | effort: 30m | deadline: 2026-03-20

Completed:
- [x] Task name

## Behaviour
- On launch: read both files, compute schedule, display today
- Add todo: append to todos.md, recompute
- Check off: mark [x] in todos.md
- Reschedule button: recompute from scratch
- Auto-refresh: watch files for changes, update popover live

## What NOT to build
- No in-app AI API calls (intelligence comes from Claude via the MCP server;
  the app itself stays deterministic and offline)
- No cloud sync
- No accounts
- No onboarding
- No notifications (the menubar HUD is the only signal)

## Claude ↔ DayPilot conventions (v2 "Flight Deck")

The app's scheduler is deterministic Swift; Claude supplies judgment through the
markdown files via the daypilot MCP tools. The contract:

- **Proposals, not surprises.** Anything speculative goes in as `proposed: true`
  (a `- [?]` line). Tommy accepts/rejects in the app. Only add `- [ ]` tasks
  directly when he explicitly asked for that exact task.
- **Provenance.** MCP-added tasks are tagged `by: claude` automatically; put the
  why in the task's notes.
- **Defer, don't delete.** `defer: YYYY-MM-DD` snoozes a task. `carried: N`
  counts rollovers — when you see N ≥ 3 in list_tasks, ask whether it's still
  worth hauling.
- **Calibration loop.** done.md entries carry `at: HH:mm` timestamps. Periodically
  compare estimates vs actual completion patterns per project and write a
  `## Calibration` section to memory.md (`- ProjectName: 1.8`). The scheduler
  multiplies efforts by it for packing and the wheels-down ETA.
- **Morning briefing.** When asked (or in a morning routine), use `write_briefing`
  — 3-6 lines: today's shape, the one thing that matters, any overweight warning.
  Rendered at the top of the app until midnight.
- **Negotiated overload.** When the day doesn't fit (payload > capacity), never
  silently rewrite todos.md. Present 2-3 named trade-off bundles in conversation
  ("drop X / shrink Y / push Z") and apply only what Tommy picks.
- **Memory ratification.** Propose memory.md edits (energy pattern, priorities)
  in conversation before writing them — the user model is jointly owned.
- **Energy blocks** are configurable in memory.md `## Settings`:
  `deep_work: 9-12`, `light: 12-17`, `admin: 17-22`.
- `~/scheduler` is auto-committed to a local git repo by the app; history is
  readable context ("what changed last week and did it help?").
