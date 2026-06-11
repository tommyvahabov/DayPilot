import Foundation

enum Scheduler {
    /// deadline > project priority > file order (so manual reordering survives
    /// recomputes — effort used to be the tiebreak, which stomped user intent).
    private static func lessThan(_ a: TodoItem, _ b: TodoItem, context: MemoryContext) -> Bool {
        let aDeadline = a.deadline ?? Date.distantFuture
        let bDeadline = b.deadline ?? Date.distantFuture
        if aDeadline != bDeadline { return aDeadline < bDeadline }

        let aPriority = context.priority(for: a.project)
        let bPriority = context.priority(for: b.project)
        if aPriority != bPriority { return aPriority < bPriority }

        return a.lineIndex < b.lineIndex
    }

    /// Estimate × the project's calibration multiplier (Claude-maintained, from
    /// done.md actuals). Display always shows the raw estimate; packing and ETA
    /// use this.
    static func effectiveEffort(_ item: TodoItem, context: MemoryContext) -> Int {
        let mult = context.calibrationMultiplier(for: item.project)
        return Int((Double(item.effortMinutes) * mult).rounded())
    }

    static func schedule(todos: [TodoItem], context: MemoryContext, today date: Date = Date()) -> DayQueue {
        let sorted = todos.sorted { lessThan($0, $1, context: context) }

        let cal = Calendar.current
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date))!
        let deferFormatter = DateFormatter()
        deferFormatter.dateFormat = "MMM d"

        var today: [TodoItem] = []
        var tomorrow: [TodoItem] = []
        var backlog: [TodoItem] = []
        var todayTotal = 0
        var tomorrowTotal = 0
        let cap = context.dailyCapacityMinutes

        for var item in sorted {
            let effort = effectiveEffort(item, context: context)
            // Deferred tasks skip today's packing entirely.
            if let d = item.deferUntil, d >= startOfTomorrow {
                if cal.isDate(d, inSameDayAs: startOfTomorrow), tomorrowTotal + effort <= cap {
                    item.rationale = "tomorrow — deferred" + rationaleSuffix(item, effort: effort, context: context)
                    tomorrow.append(item)
                    tomorrowTotal += effort
                } else {
                    item.rationale = "backlog — deferred to \(deferFormatter.string(from: d))"
                    backlog.append(item)
                }
                continue
            }
            if todayTotal + effort <= cap {
                item.rationale = "today — fits \(DurationParser.format(minutes: todayTotal + effort))/\(DurationParser.format(minutes: cap))"
                    + rationaleSuffix(item, effort: effort, context: context)
                today.append(item)
                todayTotal += effort
            } else if tomorrowTotal + effort <= cap {
                item.rationale = "tomorrow — over today's capacity (\(DurationParser.format(minutes: cap)))"
                    + rationaleSuffix(item, effort: effort, context: context)
                tomorrow.append(item)
                tomorrowTotal += effort
            } else {
                item.rationale = "backlog — beyond today and tomorrow's capacity"
                backlog.append(item)
            }
        }

        return DayQueue(today: today, tomorrow: tomorrow, backlog: backlog)
    }

    private static let deadlineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static func rationaleSuffix(_ item: TodoItem, effort: Int, context: MemoryContext) -> String {
        var parts: [String] = []
        if let deadline = item.deadline {
            parts.append("deadline \(deadlineFormatter.string(from: deadline))")
        }
        let priority = context.priority(for: item.project)
        if priority != Int.max, let project = item.project {
            parts.append("P\(priority) \(project)")
        }
        if effort != item.effortMinutes {
            let mult = context.calibrationMultiplier(for: item.project)
            parts.append("\(DurationParser.format(minutes: effort)) effective (\(DurationParser.format(minutes: item.effortMinutes)) × \(String(format: "%.1f", mult)))")
        }
        return parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")
    }

    // MARK: - Go-Around

    /// Repack the remaining open tasks into what's actually left of the day:
    /// time until the admin block ends, capped by unspent capacity. Whatever
    /// doesn't fit is diverted (caller defers it to tomorrow with a carry).
    static func reflow(todos: [TodoItem], context: MemoryContext, now: Date, minutesDoneToday: Int) -> (kept: [TodoItem], diverted: [TodoItem]) {
        let cal = Calendar.current
        let endOfDay = cal.date(bySettingHour: context.energy.adminEnd, minute: 0, second: 0, of: now) ?? now
        let untilEnd = max(0, Int(endOfDay.timeIntervalSince(now) / 60))
        let available = min(untilEnd, max(0, context.dailyCapacityMinutes - minutesDoneToday))
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!

        var kept: [TodoItem] = []
        var diverted: [TodoItem] = []
        var used = 0
        for item in todos.sorted(by: { lessThan($0, $1, context: context) }) {
            if let d = item.deferUntil, d >= startOfTomorrow { continue }  // already not today's problem
            let effort = effectiveEffort(item, context: context)
            if used + effort <= available {
                kept.append(item)
                used += effort
            } else {
                diverted.append(item)
            }
        }
        return (kept, diverted)
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
