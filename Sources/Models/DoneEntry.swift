import Foundation

struct DoneEntry: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let project: String?
    let effort: String
    /// Completion clock time ("14:32") when recorded — raw material for
    /// Claude's effort-calibration analysis.
    var at: String?
}

struct DoneDay: Identifiable, Equatable {
    let id: String  // date string "2026-03-21"
    let date: String
    var entries: [DoneEntry]
    /// `> preflight HH:mm` ritual marker, if the day was opened.
    var preflight: String?
    /// `> closed HH:mm …` ritual marker, if the day was closed.
    var closed: String?

    init(id: String, date: String, entries: [DoneEntry], preflight: String? = nil, closed: String? = nil) {
        self.id = id
        self.date = date
        self.entries = entries
        self.preflight = preflight
        self.closed = closed
    }
}
