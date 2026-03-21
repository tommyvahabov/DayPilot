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

    init(
        id: UUID = UUID(),
        title: String,
        project: String? = nil,
        effortMinutes: Int = 15,
        deadline: Date? = nil,
        isCompleted: Bool = false,
        lineIndex: Int = -1,
        notes: [String] = []
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.effortMinutes = effortMinutes
        self.deadline = deadline
        self.isCompleted = isCompleted
        self.lineIndex = lineIndex
        self.notes = notes
    }
}
