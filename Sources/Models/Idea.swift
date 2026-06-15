import Foundation

/// A free-form idea / journal entry. Lives in `~/scheduler/ideas.md`. Metadata
/// rides in an HTML comment so the file still reads as clean markdown anywhere
/// else, while giving each entry a stable id, creation time, and pin state.
struct Idea: Identifiable, Equatable {
    let id: String
    var title: String
    var body: String
    var createdAt: Date
    var pinned: Bool

    init(id: String, title: String, body: String, createdAt: Date, pinned: Bool = false) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.pinned = pinned
    }

    /// First non-empty line of the body, used as a subtitle when the title is
    /// itself derived from the body.
    var preview: String {
        body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
