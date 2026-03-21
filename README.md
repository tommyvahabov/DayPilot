# DayPilot

A macOS menubar scheduler that turns two markdown files into a prioritized daily task queue. No cloud, no accounts, no AI — just local files and pure Swift logic.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange) ![License: MIT](https://img.shields.io/badge/License-MIT-green)

## How It Works

DayPilot reads two files from `~/scheduler/`:

- **`todos.md`** — your task list
- **`memory.md`** — your projects, priorities, and daily capacity

It sorts tasks by deadline → project priority → effort, fills your day up to `daily_capacity`, and shows the result in a clean menubar popover with **Today / Tomorrow / Backlog** sections.

Edit the files in any editor — the app watches for changes and updates live.

## Install

### Homebrew (recommended)

```bash
brew tap tommyvahabov/tap
brew install --cask daypilot
```

### Manual

```bash
git clone https://github.com/tommyvahabov/DayPilot.git
cd DayPilot
swift build -c release
bash bundle.sh
open ~/Applications/DayPilot.app
```

### Auto-launch on login (optional)

```bash
osascript -e 'tell application "System Events" to make login item at end with properties {path:"'$HOME'/Applications/DayPilot.app", hidden:true}'
```

## Setup

Create `~/scheduler/` with your files:

### todos.md

```markdown
- [ ] Ship landing page | project: Acme | effort: 2h | deadline: 2026-03-25
- [ ] Review PR | project: Acme | effort: 30m
- [ ] Buy groceries | effort: 20m
- [x] Already done task
```

Each task is a line starting with `- [ ]` or `- [x]`. Fields after the title are pipe-delimited and optional:

| Field | Format | Default |
|-------|--------|---------|
| `project` | `project: Name` | None |
| `effort` | `effort: 30m` / `1h` / `1h30m` | 15m |
| `deadline` | `deadline: YYYY-MM-DD` | None (sorts last) |

### memory.md

```markdown
## Projects
- Acme | priority: 1 | deadline: 2026-04-01
- SideProject | priority: 2

## Settings
daily_capacity: 4h
```

## Scheduling Logic

1. Filter uncompleted tasks
2. Sort by: **deadline proximity** → **project priority** (1 = highest) → **effort** (shortest first)
3. Fill **Today** until `daily_capacity` is reached
4. Fill **Tomorrow** with the next `daily_capacity` worth
5. Everything else → **Backlog**

## MCP Server (optional)

An MCP server is included so AI assistants (Claude, etc.) can manage your tasks directly.

```bash
cd mcp-server
npm install
```

Add to your Claude Code config (`~/.claude/settings.local.json`):

```json
{
  "mcpServers": {
    "daypilot": {
      "command": "node",
      "args": ["/path/to/DayPilot/mcp-server/index.js"]
    }
  }
}
```

Available tools: `list_tasks`, `add_task`, `complete_task`, `remove_task`, `read_memory`, `update_memory`, `set_capacity`, `set_project`

## Features

- Menubar-only app (no dock icon)
- Live file watching with debounce
- Drag to reorder tasks
- Add tasks from the popover
- Check off tasks (writes back to todos.md)
- Reschedule button to recompute from scratch
- Colored project pills
- Collapsible backlog section

## Requirements

- macOS 14+
- Swift 5.10+

## License

MIT
