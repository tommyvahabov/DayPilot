# Contributing to DayPilot

Thanks for being here. DayPilot is a small project by one founder — contributions of any size are welcome, from typo fixes to new features.

## Before you start

- **Bugs**: open an issue first with reproduction steps. If you've got a fix ready, link the PR to the issue.
- **Features**: open an issue describing the use case before writing code. DayPilot stays opinionated and small on purpose — not every feature fits, and a quick discussion saves both of us time.
- **Docs / typos**: just send the PR.

## Development setup

```bash
git clone https://github.com/tommyvahabov/DayPilot.git
cd DayPilot
swift build -c release
./bundle.sh
open ~/Applications/DayPilot.app
```

**Requirements:**
- macOS 14 (Sonoma) or newer
- Apple Silicon Mac
- Xcode Command Line Tools (`xcode-select --install`)
- Swift 5.10+ (ships with current Xcode)

## Project layout

| Path | Purpose |
|------|---------|
| `Sources/` | Main SwiftUI app |
| `Sources/MCPServer/` | Native Swift MCP server (separate executable target) |
| `Sources/Services/` | App services (parsing, file watching, update checker, Claude integration) |
| `Sources/Views/` | SwiftUI views |
| `Sources/Models/` | Plain data types |
| `Resources/` | Icons, entitlements, runtime PNGs (copied into `Contents/Resources/`) |
| `Tests/` | Unit tests |
| `bundle.sh` | Builds the `.app` bundle from the SPM output |
| `release.sh` | Cuts a signed + notarized GitHub release |

## Coding style

- Follow standard Swift conventions and the patterns already in the codebase
- Prefer `@Observable` and SwiftUI-native patterns over AppKit when possible
- Keep views small and composable
- Avoid adding dependencies unless they replace a meaningful amount of hand-rolled code
- No comments for what the code does — only for *why* it does something non-obvious

## Pull requests

- One concern per PR — easier to review, easier to revert
- Branch from `master`, name it whatever's descriptive
- Run `swift build -c release` locally and make sure it links cleanly
- For UI changes: include a before/after screenshot or short video
- Tests are nice to have but not required for every change — use judgement

## Reporting bugs

Use the bug issue template. Include:
- DayPilot version (sidebar footer shows `v1.x.y`)
- macOS version
- Steps to reproduce
- What you expected vs. what happened
- Crash log if applicable (`Console.app → Crash Reports → DayPilot`)

## Code of conduct

Be kind. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

By contributing, you agree your work is released under the [MIT License](LICENSE).
