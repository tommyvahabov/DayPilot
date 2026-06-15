import Foundation

struct TodoItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var project: String?
    var effortMinutes: Int
    var deadline: Date?
    var isCompleted: Bool
    var lineIndex: Int
    var notes: [String]
    /// Per-task priority: 1 (high) … 3 (low), nil when unset. Overrides the
    /// project's priority in the scheduler when present.
    var priority: Int?
    /// Files attached to this task. Persisted as the line's `attach:` token.
    var attachments: [Attachment]
    /// Snoozed until this date; excluded from today's packing before then.
    var deferUntil: Date?
    /// Times this task rolled over to another day (go-around or post-flight).
    var carried: Int
    /// Provenance: "claude" when an agent wrote the line via MCP.
    var addedBy: String?
    /// `- [?]` lines: agent proposals awaiting human accept/reject.
    var isProposed: Bool
    /// Why the scheduler placed it where it did. Derived, never persisted.
    var rationale: String?

    init(
        id: UUID = UUID(),
        title: String,
        project: String? = nil,
        effortMinutes: Int = 15,
        deadline: Date? = nil,
        isCompleted: Bool = false,
        lineIndex: Int = -1,
        notes: [String] = [],
        priority: Int? = nil,
        attachments: [Attachment] = [],
        deferUntil: Date? = nil,
        carried: Int = 0,
        addedBy: String? = nil,
        isProposed: Bool = false,
        rationale: String? = nil
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.effortMinutes = effortMinutes
        self.deadline = deadline
        self.isCompleted = isCompleted
        self.lineIndex = lineIndex
        self.notes = notes
        self.priority = priority
        self.attachments = attachments
        self.deferUntil = deferUntil
        self.carried = carried
        self.addedBy = addedBy
        self.isProposed = isProposed
        self.rationale = rationale
    }
}
