# Security Policy

## Supported versions

DayPilot is single-developer software shipped via GitHub Releases. Only the **latest released version** receives security fixes. Older versions can be upgraded via the in-app one-click updater (sidebar pill when a new release is available).

## Reporting a vulnerability

**Please do not file public GitHub issues for security vulnerabilities.**

Instead, email **rahmonberdivahabov@gmail.com** with:

- A description of the issue
- Steps to reproduce or proof of concept
- Affected version(s)
- Your assessment of severity / impact
- Whether you'd like to be credited in the release notes

**What to expect:**

- Acknowledgement within **48 hours**
- An initial assessment within **7 days**
- A fix and coordinated disclosure timeline communicated as soon as the scope is understood. Critical issues are typically patched and released within **2 weeks**.

## Scope

In scope:
- The DayPilot macOS app (signed and notarized binaries from GitHub Releases)
- The bundled `DayPilotMCP` server
- The auto-update mechanism (signature verification, file replacement)
- Any code that touches `~/scheduler/` files or Claude config files

Out of scope:
- Issues in third-party MCP clients (Claude Desktop, Claude Code) themselves
- macOS Gatekeeper / notarization behaviour
- Self-built source builds that bypass the signed release pipeline

## Security model

DayPilot:

- Reads and writes files under `~/scheduler/` (todos.md, memory.md, done.md)
- On first launch, merges a `daypilot` MCP entry into `~/.claude.json` and `~/Library/Application Support/Claude/claude_desktop_config.json` — preserving all other servers and settings
- Polls `api.github.com` for release metadata (no telemetry, no analytics)
- Downloads release zips from `github.com/tommyvahabov/DayPilot/releases/...` when you click the in-app update pill, replaces the running `.app` bundle, and relaunches
- Does not send any data off your machine other than the GitHub API polls described above

All releases since v1.5.0 are code-signed with a Developer ID, hardened-runtime, and notarized by Apple.

## Credit

Reporters who follow responsible disclosure are credited in the release notes for the fix (unless they prefer to stay anonymous).
