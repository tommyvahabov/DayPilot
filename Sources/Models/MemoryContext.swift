import Foundation

struct ProjectInfo: Equatable {
    let name: String
    let priority: Int
    let deadline: Date?
}

/// Hour boundaries for the day's energy blocks. Defaults match the historical
/// hardcoded values; overridable via memory.md `## Settings` (deep_work: 9-12 …).
struct EnergyBlocks: Equatable {
    var deepWorkStart = 5
    var deepWorkEnd = 12
    var lightEnd = 17
    var adminEnd = 22
}

struct MemoryContext: Equatable {
    var projects: [ProjectInfo]
    var dailyCapacityMinutes: Int
    var energy: EnergyBlocks
    /// Per-project effort multipliers, keyed by lowercased project name.
    /// Written by Claude (from done.md actuals), read by the scheduler.
    var calibration: [String: Double]

    init(projects: [ProjectInfo] = [], dailyCapacityMinutes: Int = 240, energy: EnergyBlocks = EnergyBlocks(), calibration: [String: Double] = [:]) {
        self.projects = projects
        self.dailyCapacityMinutes = dailyCapacityMinutes
        self.energy = energy
        self.calibration = calibration
    }

    func calibrationMultiplier(for projectName: String?) -> Double {
        guard let name = projectName?.lowercased() else { return 1.0 }
        return calibration[name] ?? 1.0
    }

    func priority(for projectName: String?) -> Int {
        guard let name = projectName,
              let project = projects.first(where: { $0.name == name }) else {
            return Int.max
        }
        return project.priority
    }
}
