import Foundation

enum Scheduler {
    static func schedule(todos: [TodoItem], context: MemoryContext) -> DayQueue {
        let sorted = todos.sorted { a, b in
            let aDeadline = a.deadline ?? Date.distantFuture
            let bDeadline = b.deadline ?? Date.distantFuture
            if aDeadline != bDeadline { return aDeadline < bDeadline }

            let aPriority = context.priority(for: a.project)
            let bPriority = context.priority(for: b.project)
            if aPriority != bPriority { return aPriority < bPriority }

            // File order is the final tiebreak so manual reordering survives
            // recomputes (effort used to win here, which stomped user intent).
            return a.lineIndex < b.lineIndex
        }

        var today: [TodoItem] = []
        var tomorrow: [TodoItem] = []
        var backlog: [TodoItem] = []
        var todayTotal = 0
        var tomorrowTotal = 0
        let cap = context.dailyCapacityMinutes

        for item in sorted {
            if todayTotal + item.effortMinutes <= cap {
                today.append(item)
                todayTotal += item.effortMinutes
            } else if tomorrowTotal + item.effortMinutes <= cap {
                tomorrow.append(item)
                tomorrowTotal += item.effortMinutes
            } else {
                backlog.append(item)
            }
        }

        return DayQueue(today: today, tomorrow: tomorrow, backlog: backlog)
    }

    // MARK: - Flight math

    static func wheelsDown(now: Date, remainingMinutes: Int) -> Date {
        now.addingTimeInterval(TimeInterval(remainingMinutes * 60))
    }

    /// Master caution: the remaining plan overruns the end of the admin block,
    /// or exceeds what's left of today's capacity.
    static func cautionActive(now: Date, remainingMinutes: Int, minutesDoneToday: Int, context: MemoryContext) -> Bool {
        let cal = Calendar.current
        let endOfDay = cal.date(bySettingHour: context.energy.adminEnd, minute: 0, second: 0, of: now) ?? now
        let overrunsDay = wheelsDown(now: now, remainingMinutes: remainingMinutes) > endOfDay
        let overCapacity = remainingMinutes > max(0, context.dailyCapacityMinutes - minutesDoneToday)
        return overrunsDay || overCapacity
    }
}
