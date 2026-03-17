import Testing
@testable import DayPilot

@Suite("DurationParser")
struct DurationParserTests {
    @Test func parsesMinutesOnly() {
        #expect(DurationParser.parseMinutes("30m") == 30)
    }

    @Test func parsesHoursOnly() {
        #expect(DurationParser.parseMinutes("4h") == 240)
    }

    @Test func parsesHoursAndMinutes() {
        #expect(DurationParser.parseMinutes("1h30m") == 90)
    }

    @Test func invalidStringDefaults() {
        #expect(DurationParser.parseMinutes("garbage") == 15)
    }

    @Test func emptyStringDefaults() {
        #expect(DurationParser.parseMinutes("") == 15)
    }

    @Test func formatsMinutesAsString() {
        #expect(DurationParser.format(minutes: 90) == "1h 30m")
        #expect(DurationParser.format(minutes: 30) == "30m")
        #expect(DurationParser.format(minutes: 120) == "2h")
    }
}
