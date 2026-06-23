import Foundation

/// The lifecycle of a handed-off task, mirrored on both Macs. Status flows one
/// way only: `delivered → accepted/declined`, and `accepted → done`. The sender
/// watches it climb; the receiver drives it.
enum TaskStatus: String, Codable, Equatable {
    case delivered   // left this Mac, sitting in the coworker's inbox
    case accepted    // coworker took it — now a real line in their todos.md
    case declined    // coworker passed
    case done        // the todos.md line flipped [ ]→[x]

    /// Declined and done are end states — nothing follows them.
    var isTerminal: Bool {
        self == .declined || self == .done
    }

    /// Whether `next` is a legal forward move from this status.
    func canTransition(to next: TaskStatus) -> Bool {
        switch (self, next) {
        case (.delivered, .accepted), (.delivered, .declined): return true
        case (.accepted, .done): return true
        default: return false
        }
    }

    /// The status after attempting to move to `next`: `next` when the move is
    /// legal, otherwise unchanged. Lets the inbox/outbox merge inbound updates
    /// without a stale, duplicate, or reordered packet corrupting a row.
    func applying(_ next: TaskStatus) -> TaskStatus {
        canTransition(to: next) ? next : self
    }
}

/// A task offered to a coworker. `title` is the only required field; everything
/// else mirrors the optional tokens on a todos.md line. `id` is the hidden
/// `collab:<uuid>` tracking tag that lets status updates find their task on both
/// ends — and lets the done-watcher recognise the accepted line later.
struct SharedTask: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var project: String?
    var effortMinutes: Int?
    var priority: Int?
    /// Free-form context; lands as the indented `CONTEXT:` note line on accept.
    var note: String?
    /// Sender's display name; serialized as the `from:` token on accept.
    var from: String?

    init(
        id: UUID = UUID(),
        title: String,
        project: String? = nil,
        effortMinutes: Int? = nil,
        priority: Int? = nil,
        note: String? = nil,
        from: String? = nil
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.effortMinutes = effortMinutes
        self.priority = priority
        self.note = note
        self.from = from
    }
}

/// A status change flowing back to the original sender, keyed by the task's
/// collab id so the outbox can find the row to update.
struct StatusUpdate: Codable, Equatable {
    let collabID: UUID
    var status: TaskStatus
}

/// A task that arrived from a coworker, parked in the in-app inbox until it's
/// accepted or declined. Identity is the task's collab id.
struct InboxItem: Identifiable, Equatable {
    let task: SharedTask
    /// Display name of the peer that sent it.
    var fromPeer: String
    var status: TaskStatus
    /// Cleared once the human has looked at it; drives the new-arrival badge.
    var unread: Bool

    var id: UUID { task.id }

    init(task: SharedTask, fromPeer: String, status: TaskStatus = .delivered, unread: Bool = true) {
        self.task = task
        self.fromPeer = fromPeer
        self.status = status
        self.unread = unread
    }
}

/// A task this Mac sent out, with the status flowing back from the recipient.
struct OutboxItem: Identifiable, Equatable {
    let task: SharedTask
    /// Display name of the peer it went to.
    var toPeer: String
    var status: TaskStatus
    /// True when this was a *delegation* of one of my own tasks (removed from my
    /// list on handoff) — if the peer declines, restore it to my list.
    var restoreOnDecline: Bool

    var id: UUID { task.id }

    init(task: SharedTask, toPeer: String, status: TaskStatus = .delivered, restoreOnDecline: Bool = false) {
        self.task = task
        self.toPeer = toPeer
        self.status = status
        self.restoreOnDecline = restoreOnDecline
    }
}

/// Everything sent over the wire is one of these. Codable is synthesized; the
/// `encoded()`/`decode(_:)` helpers pin the JSON config in one place so both
/// Macs agree on the format.
enum CollabMessage: Codable, Equatable {
    case task(SharedTask)
    case statusUpdate(StatusUpdate)

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> CollabMessage {
        try JSONDecoder().decode(CollabMessage.self, from: data)
    }
}
