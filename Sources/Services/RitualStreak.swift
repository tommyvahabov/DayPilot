import Foundation

enum RitualStreak {
    /// Consecutive days with a `closed` ritual marker, walking back from today
    /// (or yesterday, if today isn't closed yet). One missing day per week is
    /// forgiven — a "ground day" — so a single sick day doesn't nuke the streak.
    /// Two gaps in the same week, or two consecutive missed days, end it.
    static func compute(days: [DoneDay], today: Date = Date(), calendar: Calendar = .current) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let closedDates = Set(
            days.filter { $0.closed != nil }
                .compactMap { formatter.date(from: $0.date) }
                .map { calendar.startOfDay(for: $0) }
        )
        guard !closedDates.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: today)
        if !closedDates.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }

        var streak = 0
        var freezeUsedInWeek: Int?
        while true {
            if closedDates.contains(cursor) {
                streak += 1
            } else {
                let week = calendar.component(.weekOfYear, from: cursor)
                if freezeUsedInWeek == week { break }
                let dayBefore = calendar.date(byAdding: .day, value: -1, to: cursor)!
                guard closedDates.contains(dayBefore) else { break }  // ≥2-day gap ends it
                freezeUsedInWeek = week
            }
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }
}
