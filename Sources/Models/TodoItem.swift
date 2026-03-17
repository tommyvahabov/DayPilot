import Foundation

struct TodoItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var project: String?
    var effortMinutes: Int
    var deadline: Date?
    var isCompleted: Bool
    var lineIndex: Int  // position in the original file for write-back

    init(
        id: UUID = UUID(),
        title: String,
        project: String? = nil,
        effortMinutes: Int = 15,
        deadline: Date? = nil,
        isCompleted: Bool = false,
        lineIndex: Int = -1
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.effortMinutes = effortMinutes
        self.deadline = deadline
        self.isCompleted = isCompleted
        self.lineIndex = lineIndex
    }
}
