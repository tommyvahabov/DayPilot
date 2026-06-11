# DayPilot v2 — "Flight Deck" Design

Date: 2026-06-11
Status: Approved direction (Tommy: "i like all lets do it"). Spec open for async review.
Branch: `v2-flight-deck`

## Goal

Evolve DayPilot from a nice menubar todo into a category-of-one: a local-first,
markdown-backed day planner where the deterministic Swift scheduler owns the pixels
and Claude (via the existing MCP server) owns the thinking. Research synthesis behind
this scope: menubar HUD + ETA + go-around + bookend rituals + legible/calibrated
scheduling are the highest retention-per-complexity features in the market, and the
symbiosis features are unshipped by anyone.

Constraints honored: no backend, no in-app AI calls, markdown files stay the single
source of truth, popover stays fast and keyboard-light.

## File-format contract (the foundation everything sits on)

The deepest architectural fact discovered in design: **today/tomorrow/backlog are
not persisted** — `Scheduler.schedule` recomputes the split from capacity packing on
every parse. Several approved features therefore need real file semantics:

### todos.md task line tokens (pipe-separated, all optional after title)

```
- [ ] Title | project: X | effort: 30m | deadline: 2026-06-20 | defer: 2026-06-12 | carried: 2 | by: claude
```

- `defer: YYYY-MM-DD` — NEW. Task is excluded from today's packing until that date.
  `defer == tomorrow` ⇒ tomorrow bucket; later ⇒ backlog. This gives "push to
  tomorrow" a real, persistent meaning.
- `carried: N` — NEW. Rollover counter, incremented each time a task is diverted
  (go-around) or pushed to tomorrow (post-flight). N ≥ 3 surfaces a "still worth
  hauling?" badge.
- `by: claude` — NEW. Provenance. MCP `add_task` writes it automatically; origin
  prose goes in notes. UI shows a sparkle badge.
- `- [?]` — NEW third checkbox state: *proposed* task. Excluded from scheduling.
  Rendered in a Proposals section with accept (→ `- [ ]`) / reject (→ removed,
  logged). MCP `add_task` gains `proposed: true`.

Parsers must round-trip unknown tokens untouched (they already do — tokens live in
the raw line; we only rewrite whole lines we own).

### done.md day entries

```
## 2026-06-11
> preflight 08:42
- [x] Ship landing page | project: QuizPilot | effort: 30m | at: 14:32
> closed 21:13 | shipped: 5 | diverted: 2 | scrapped: 1
> scrapped: Old task title
> rejected: Proposed task title
```

- `at: HH:mm` — NEW completion timestamp on every entry (app + MCP). This is the
  raw material for Claude's calibration analysis.
- Blockquote `>` lines — NEW ritual/audit markers. Existing parsers ignore them
  (they only match `- [x]` and `## `), so the format is backward compatible.

### memory.md additions

```
## Settings
daily_capacity: 6h
deep_work: 9-12
light: 12-17
admin: 17-22

## Calibration
- QuizPilot: 1.8
- DayPilot: 1.2
```

- Energy block hours — NEW optional overrides (defaults match current hardcoded
  NowCard values). The energy pill and scheduling rationale read these instead of
  hardcoded hours, fixing the "pill ignores memory.md" inconsistency.
- `## Calibration` — NEW. Per-project effort multipliers, *written by Claude* (via
  existing `update_memory`), *read by the Swift scheduler*: effective effort =
  effort × multiplier for packing and ETA. Display always shows the raw estimate.

### briefing.md (new file, optional)

```
# Briefing — 2026-06-11
<markdown body written by Claude>
```

Rendered at the top of the Today view/popover only when the date is today.

## Phase 0 — Fix the lies (bugs from the UI review)

1. **Stable project colors**: replace per-launch-random `String.hashValue` with a
   deterministic djb2 hash in a shared `ProjectColor` helper; used by TaskRowView +
   FlightLogView.
2. **Persistent manual reorder**: scheduler's final tiebreaker becomes *file order*
   (`lineIndex`) instead of effort; drag-drop calls a new
   `store.moveTask(_:before:)` that moves the task's line block (line + notes) in
   `rawTodoLines`, writes back, recomputes. Manual order survives restarts and
   recomputes; deadline/priority still dominate.
3. **Progress bar**: completion semantics — green fill, full-green celebration at
   100%; the red/orange "overload" palette is wrong for done/total and is removed.
4. **Window geometry**: `defaultSize` 980×600 to match the content's minimum.
5. **Settings About card**: version read from bundle (single source), not hardcoded.
6. **Status dot**: bound to real state — green "Watching files" when the watcher is
   live and parse succeeded, red with the error message otherwise.
7. **Greeting flip**: plays once per app launch, not on every tab visit.
8. **Done-section double-dim**: rows already render secondary+strikethrough; the
   extra `.opacity` wash is removed.
9. **Error state**: distinct icon + Retry button (was: Flight Log's icon, no action).
10. **Completion animation**: total latency tightened from 1.45s to ~0.8s; plane
    still flies, data updates sooner.
11. Dead `expandedLayout` in ScheduleContentView removed.

## Phase 1 — HUD, ETA, master caution

- **Menubar HUD**: `@AppStorage("hudMode")` ∈ {icon, compact, full}; label renders
  icon + `Text` refreshed by `TimelineView(.everyMinute)`.
  - compact: `47m` (remaining today) or wheels-down time when caution is active
  - full: `Ship API · 47m` (current top task, title truncated ~28 chars)
- **Wheels-down ETA**: `now + Σ effective remaining effort`, shown in NowCard footer
  ("wheels down 21:40"); red when caution.
- **Master caution**: active when ETA passes the end of the admin block (default
  22:00) or remaining effort exceeds remaining capacity. Menubar icon swaps to a
  warning triangle (color styling in the menubar is unreliable; symbol swap is the
  signal). No notifications — the bar itself is the alert.
- Settings gains a "Menubar HUD" card with the mode picker.

## Phase 2 — Go-Around (reflow from now)

- `Scheduler.reflow(todos:context:now:)`: available minutes = min(minutes until end
  of admin block, capacity − minutes already done today). Repack incomplete tasks
  by the same sort; overflow is *diverted*: `defer: tomorrow` + `carried+1` written
  to the file.
- UI: "Reschedule" becomes **Go-Around** (aviation: aborted landing, circle back).
  Feedback toast: "Go-around: 5 kept · 2 diverted". Button spins during reflow.
- **Global hotkey** ⌃⌥G via Carbon `RegisterEventHotKey` (no permissions needed,
  ~60-line service). Triggers go-around from anywhere. (Programmatically opening a
  MenuBarExtra popover is not supported by SwiftUI; popover hotkey is out of scope.)

## Phase 3 — Rituals (the retention engine)

- **Pre-flight** (morning): card at the top of popover/Today before noon when not
  yet done today and tasks exist. Shows payload vs runway: "Payload 7h / runway 6h —
  overweight" with the lightest-value suggestions, [Begin day] writes
  `> preflight HH:mm`. Dismissible, never blocks, never nags.
- **Post-flight** (evening): "Close the day" action (highlighted after 17:00).
  Walks each remaining today-task with a per-row choice — Tomorrow (defer+carry) /
  Backlog (move to file bottom) / Scrap (delete + `> scrapped:` log). Confirm writes
  `> closed HH:mm | shipped/diverted/scrapped` and shows "Flight closed." + streak.
- **Ritual streak**: consecutive days with a `closed` marker, allowing one missing
  day per ISO week (a "ground day"), counted from today-or-yesterday backward.
  Replaces the completion-based streak on the Runway dashboard ("12 flight days").
- **Carry counter**: `carried: N` parsed/displayed; badge at N ≥ 3 ("missed 3
  flights — still worth hauling?") in rows and the post-flight flow.

## Phase 4 — Symbiosis (Claude ↔ app shared-state features)

- **Proposals**: `- [?]` parsing; "Proposals" section (sparkles, indigo) in popover
  + Today with accept/reject; MCP `add_task` gains `proposed` param; rejects logged
  to done.md.
- **Provenance**: `by: claude` token; MCP `add_task` appends it; sparkle badge with
  tooltip in rows.
- **Legible scheduling**: `Scheduler` attaches a human rationale to every placement
  ("today — deadline Fri · P1 · fits deep work 9–12"); shown via `.help` tooltip on
  rows and in the NowCard. Derived, not persisted.
- **Calibration**: `## Calibration` multipliers parsed into `MemoryContext`,
  applied to packing/ETA as effective effort; calibrated rows show a small "×1.8"
  hint in the tooltip. The analysis itself is Claude's job (done.md now has `at:`
  timestamps); convention documented in CLAUDE.md.
- **Auto-git**: `GitService` — `git init` ~/scheduler if needed; debounced
  `add -A && commit` after every app write and after external-change reloads
  ("external edit (claude/mcp or manual)"). Toggle in Settings, default on. Silent
  no-op if git is unavailable.
- **Briefing**: briefing.md rendered (lightweight markdown → AttributedString) at
  the top of Today when dated today; MCP gains `write_briefing` tool.
- **Negotiated overload**: the caution state (Phase 1) + proposals + go-around ARE
  the mechanism; the convention that Claude proposes named trade-off bundles in
  conversation (never silently rewrites the plan) is documented in CLAUDE.md.

## MCP server changes (Sources/MCPServer/main.swift)

- `add_task`: new optional `proposed: bool`, `defer: YYYY-MM-DD`; always appends
  `by: claude`.
- `complete_task` → done.md entries gain `at: HH:mm`.
- New `write_briefing { content }` → writes briefing.md with today's header.
- `list_tasks` already returns raw lines, so new tokens flow to Claude for free.

## Error handling & compatibility

- All new tokens optional; files written by v1 parse identically in v2 and vice
  versa (v1 ignores unknown tokens — they ride along inside the raw line).
- Parsers never throw; malformed tokens fall back to defaults (existing behavior).
- Git/hotkey/briefing failures are silent and never block scheduling.

## Testing

Existing XCTest suites extended:
- TodoParser: `[?]` state, defer/carried/by round-trip, token preservation.
- Scheduler: file-order tiebreak stability, defer exclusion, calibration math,
  `reflow` packing + divert behavior with fixed `now`.
- MemoryParser: calibration section, energy block overrides.
- New DoneLogTests: `at:` timestamps, blockquote markers, ritual streak math
  (incl. ground-day freeze and week boundaries).

UI behavior verified by build + manual run; no UI test target exists.

## Out of scope (explicitly)

Motion-style silent auto-rescheduling, notifications, cloud anything, popover
global hotkey (SwiftUI limitation), natural-language quick-add parsing (future),
gamification beyond the ritual streak.
