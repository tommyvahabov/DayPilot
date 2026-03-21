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
- No AI integration
- No cloud sync
- No accounts
- No onboarding
- No settings screen (keep it simple)