import Foundation

/// On first launch (and whenever the app moves), merges a `daypilot` MCP server entry
/// into the user's Claude Code (`~/.claude.json`) and Claude Desktop config files,
/// pointing at the bundled `DayPilotMCP` binary. Idempotent — re-runs only when the
/// path changes or the entry is missing.
enum ClaudeIntegration {

    static var mcpBinaryPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/DayPilotMCP")
            .path
    }

    static let serverName = "daypilot"
    static let claudeCodeConfigPath = NSHomeDirectory() + "/.claude.json"
    static let claudeDesktopConfigPath = NSHomeDirectory() + "/Library/Application Support/Claude/claude_desktop_config.json"

    /// Call on first launch (and any subsequent launch — it's idempotent).
    static func ensureRegistered() {
        let path = mcpBinaryPath
        guard FileManager.default.fileExists(atPath: path) else { return }

        if isClaudeCodeInstalled() {
            mergeServerEntry(into: claudeCodeConfigPath, command: path)
        }
        if isClaudeDesktopInstalled() {
            mergeServerEntry(into: claudeDesktopConfigPath, command: path)
        }
    }

    private static func isClaudeCodeInstalled() -> Bool {
        // Heuristic: either the user-level config exists, or the CLI is on PATH.
        if FileManager.default.fileExists(atPath: claudeCodeConfigPath) { return true }
        return which("claude") != nil
    }

    private static func isClaudeDesktopInstalled() -> Bool {
        let dir = NSHomeDirectory() + "/Library/Application Support/Claude"
        if FileManager.default.fileExists(atPath: dir) { return true }
        let appPath = "/Applications/Claude.app"
        return FileManager.default.fileExists(atPath: appPath)
    }

    private static func which(_ cmd: String) -> String? {
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for dir in pathEnv.split(separator: ":") {
            let candidate = "\(dir)/\(cmd)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Merge { "mcpServers": { "daypilot": { "command": <path> } } } into the JSON at `path`.
    /// Preserves all other keys/servers. Creates the file (and parent dir) if missing.
    private static func mergeServerEntry(into path: String, command: String) {
        let parent = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)

        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = obj
        }

        var mcpServers = (root["mcpServers"] as? [String: Any]) ?? [:]
        let existing = mcpServers[serverName] as? [String: Any]
        let existingCommand = existing?["command"] as? String

        // Skip write if entry already correct.
        if existingCommand == command {
            return
        }

        mcpServers[serverName] = ["command": command] as [String: Any]
        root["mcpServers"] = mcpServers

        guard let outData = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }

        try? outData.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
