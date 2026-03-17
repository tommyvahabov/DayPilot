import Foundation

struct ProjectInfo: Equatable {
    let name: String
    let priority: Int
    let deadline: Date?
}

struct MemoryContext: Equatable {
    var projects: [ProjectInfo]
    var dailyCapacityMinutes: Int

    init(projects: [ProjectInfo] = [], dailyCapacityMinutes: Int = 240) {
        self.projects = projects
        self.dailyCapacityMinutes = dailyCapacityMinutes
    }

    func priority(for projectName: String?) -> Int {
        guard let name = projectName,
              let project = projects.first(where: { $0.name == name }) else {
            return Int.max
        }
        return project.priority
    }
}
