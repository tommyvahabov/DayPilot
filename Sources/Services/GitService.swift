import Foundation

/// Debounced auto-commit of ~/scheduler so every change — app action, Claude/MCP
/// write, or manual edit — becomes an auditable diff Claude can read back.
/// Silent no-op when git is unavailable or the setting is off.
final class GitService {
    private let dir: String
    private let queue = DispatchQueue(label: "daypilot.git", qos: .utility)
    private var pending: DispatchWorkItem?

    init(directory: String) {
        self.dir = directory
    }

    func commitSoon(_ message: String) {
        guard UserDefaults.standard.object(forKey: "autoGitEnabled") as? Bool ?? true else { return }
        pending?.cancel()
        let dir = self.dir
        let work = DispatchWorkItem { GitService.commitNow(dir: dir, message: message) }
        pending = work
        queue.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private static func commitNow(dir: String, message: String) {
        guard FileManager.default.fileExists(atPath: dir) else { return }
        if !FileManager.default.fileExists(atPath: dir + "/.git") {
            run(["init", "-q"], in: dir)
        }
        run(["add", "-A"], in: dir)
        // Identity is pinned so commits work without global git config.
        run(["-c", "user.name=DayPilot", "-c", "user.email=daypilot@local",
             "commit", "-q", "-m", message], in: dir)  // no-op when nothing staged
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
