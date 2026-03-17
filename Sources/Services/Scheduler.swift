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

            return a.effortMinutes < b.effortMinutes
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
}
