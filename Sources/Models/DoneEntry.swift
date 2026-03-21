import Foundation

struct DoneEntry: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let project: String?
    let effort: String
}

struct DoneDay: Identifiable, Equatable {
    let id: String  // date string "2026-03-21"
    let date: String
    let entries: [DoneEntry]
}
