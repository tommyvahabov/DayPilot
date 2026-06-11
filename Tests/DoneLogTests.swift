import Testing
import Foundation
@testable import DayPilot

@Suite("DoneLogParser")
struct DoneLogParserTests {
    @Test func parsesEntriesWithTimestamps() {
        let content = """
        ## 2026-06-11
        > preflight 08:42
        - [x] Ship page | project: QuizPilot | effort: 30m | at: 14:32
        > closed 21:13 | shipped: 1 | diverted: 0 | scrapped: 0
        """
        let days = DoneLogParser.parse(content: content)
        #expect(days.count == 1)
        #expect(days[0].entries.count == 1)
        #expect(days[0].entries[0].at == "14:32")
        #expect(days[0].entries[0].project == "QuizPilot")
        #expect(days[0].preflight == "08:42")
        #expect(days[0].closed?.hasPrefix("21:13") == true)
    }

    @Test func legacyEntriesWithoutMarkersStillParse() {
        let content = """
        ## 2026-06-10
        - [x] Old task | effort: 15m
        """
        let days = DoneLogParser.parse(content: content)
        #expect(days[0].entries[0].at == nil)
        #expect(days[0].preflight == nil)
        #expect(days[0].closed == nil)
    }
}

@Suite("RitualStreak")
struct RitualStreakTests {
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func closedDay(_ date: String) -> DoneDay {
        DoneDay(id: date, date: date, entries: [], closed: "21:00")
    }

    private func openDay(_ date: String) -> DoneDay {
        DoneDay(id: date, date: date, entries: [])
    }

    private func day(_ s: String) -> Date { formatter.date(from: s)! }

    @Test func consecutiveClosedDaysCount() {
        let days = [closedDay("2026-06-11"), closedDay("2026-06-10"), closedDay("2026-06-09")]
        #expect(RitualStreak.compute(days: days, today: day("2026-06-11")) == 3)
    }

    @Test func todayNotYetClosedCountsFromYesterday() {
        let days = [closedDay("2026-06-10"), closedDay("2026-06-09")]
        #expect(RitualStreak.compute(days: days, today: day("2026-06-11")) == 2)
    }

    @Test func singleGapIsForgivenAsGroundDay() {
        // Wed 2026-06-10 missing; Tue and Thu closed → streak continues through
        let days = [closedDay("2026-06-11"), closedDay("2026-06-09"), closedDay("2026-06-08")]
        #expect(RitualStreak.compute(days: days, today: day("2026-06-11")) == 3)
    }

    @Test func twoGapsInSameWeekStopTheStreak() {
        // 2026-06-08 (Mon) … 11 (Thu): closed Thu + Tue, missing Wed and Mon → second gap same ISO week stops it
        let days = [closedDay("2026-06-11"), closedDay("2026-06-09"), closedDay("2026-06-05")]
        #expect(RitualStreak.compute(days: days, today: day("2026-06-11")) == 2)
    }

    @Test func twoConsecutiveMissedDaysStopTheStreak() {
        let days = [closedDay("2026-06-11"), closedDay("2026-06-07")]
        #expect(RitualStreak.compute(days: days, today: day("2026-06-11")) == 1)
    }

    @Test func dayWithEntriesButNoCloseDoesNotCount() {
        let days = [
            closedDay("2026-06-11"),
            DoneDay(id: "2026-06-10", date: "2026-06-10", entries: [DoneEntry(title: "t", project: nil, effort: "15m")], closed: nil),
            closedDay("2026-06-09"),
        ]
        // 06-10 has completions but wasn't closed — it's a gap, forgiven once
        #expect(RitualStreak.compute(days: days, today: day("2026-06-11")) == 2)
    }

    @Test func noClosedDaysIsZero() {
        #expect(RitualStreak.compute(days: [openDay("2026-06-11")], today: day("2026-06-11")) == 0)
    }
}
