import Foundation

/// The seam between a `SharedTask` arriving over the wire and DayPilot's plain
/// todos.md. Pure string work — no file I/O, no transport — so the round-trip
/// (serialize on accept, recognise the line, spot the [ ]→[x] flip) is fully
/// unit-testable. The actual file append + watching is owned by `ScheduleStore`,
/// which is the single writer/watcher of todos.md.
enum CollabBridge {
    static let collabKey = "collab"

    /// Render an accepted task as a line indistinguishable from a hand-written
    /// one, save the trailing `collab:` provenance tag that lets us track it:
    ///
    ///   - [ ] Fix battle protocol timeout | project: AvtoPilot | effort: 1h | from: Tommy | collab: <uuid>
    static func todoLine(for task: SharedTask) -> String {
        var parts = baseTokens(for: task)
        if let from = task.from, !from.isEmpty {
            parts.append("from: \(from)")
        }
        parts.append("\(collabKey): \(task.id.uuidString)")
        return parts.joined(separator: " | ")
    }

    /// A normal task line with no collab/`from` tags — used when a handed-off
    /// task is declined and restored to the sender's own list (it's theirs again,
    /// no longer a tracked handoff).
    static func plainLine(for task: SharedTask) -> String {
        baseTokens(for: task).joined(separator: " | ")
    }

    /// The shared `- [ ] title | project | effort | priority` prefix.
    private static func baseTokens(for task: SharedTask) -> [String] {
        var parts = ["- [ ] " + TodoParser.sanitizeTitle(task.title)]
        if let project = task.project, !project.isEmpty {
            parts.append("project: \(project)")
        }
        if let minutes = task.effortMinutes {
            parts.append("effort: \(DurationParser.format(minutes: minutes))")
        }
        if let priority = task.priority {
            parts.append("priority: \(priority)")
        }
        return parts
    }

    /// Turn one of your own tasks into a `SharedTask` to hand off to a coworker.
    /// A fresh collab id is minted (this is a new shared instance); `from` is
    /// left for the sender to stamp at send time. CONTEXT note prefixes are
    /// stripped so they don't double up when the recipient re-renders them.
    static func sharedTask(from item: TodoItem) -> SharedTask {
        let note = item.notes
            .map(stripContextPrefix)
            .filter { !$0.isEmpty }
            .joined(separator: "; ")
        return SharedTask(
            title: item.title,
            project: item.project,
            effortMinutes: item.effortMinutes,
            priority: item.priority,
            note: note.isEmpty ? nil : note
        )
    }

    private static func stripContextPrefix(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("context:") {
            return String(trimmed.dropFirst("context:".count)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    /// The indented note block for an accepted task — the `note` becomes a
    /// `CONTEXT:` line, matching how context notes already read in todos.md.
    static func notes(for task: SharedTask) -> [String] {
        guard let note = task.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else { return [] }
        return ["CONTEXT: \(note)"]
    }

    /// Extract the `collab:` tracking id from a task line, or nil if it isn't a
    /// collab task. Only matches the dedicated token (split on `|`), so a title
    /// that merely mentions "collab" can't false-match.
    static func collabID(from line: String) -> UUID? {
        let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts.dropFirst() where part.lowercased().hasPrefix("\(collabKey):") {
            let value = part.dropFirst(collabKey.count + 1).trimmingCharacters(in: .whitespaces)
            return UUID(uuidString: value)
        }
        return nil
    }

    /// Collab ids whose line flipped from open to complete between two snapshots
    /// of todos.md. Fires only on a genuine [ ]→[x] transition: a task that was
    /// already done, or appears done out of nowhere, is ignored — so the "done"
    /// ack is sent exactly once per completion.
    static func newlyCompletedCollabIDs(old: [String], new: [String]) -> [UUID] {
        let before = completionByCollabID(old)
        let after = completionByCollabID(new)
        return after.compactMap { id, isDone -> UUID? in
            guard isDone, before[id] == false else { return nil }
            return id
        }
    }

    /// Map every collab-tagged line to whether its checkbox is ticked.
    private static func completionByCollabID(_ lines: [String]) -> [UUID: Bool] {
        var result: [UUID: Bool] = [:]
        for line in lines {
            guard let id = collabID(from: line) else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            result[id] = trimmed.hasPrefix("- [x] ")
        }
        return result
    }
}
