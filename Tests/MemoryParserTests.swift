import Testing
import Foundation
@testable import DayPilot

@Suite("MemoryParser")
struct MemoryParserTests {
    @Test func parsesProjects() {
        let content = """
        ## Projects
        - QuizPilot | priority: 1 | deadline: 2026-04-01
        - DayPilot | priority: 2

        ## Settings
        daily_capacity: 4h
        """
        let ctx = MemoryParser.parse(content: content)
        #expect(ctx.projects.count == 2)
        #expect(ctx.projects[0].name == "QuizPilot")
        #expect(ctx.projects[0].priority == 1)
        #expect(ctx.projects[1].name == "DayPilot")
        #expect(ctx.projects[1].priority == 2)
        #expect(ctx.projects[1].deadline == nil)
    }

    @Test func parsesDailyCapacity() {
        let content = """
        ## Settings
        daily_capacity: 6h
        """
        let ctx = MemoryParser.parse(content: content)
        #expect(ctx.dailyCapacityMinutes == 360)
    }

    @Test func defaultsWhenEmpty() {
        let ctx = MemoryParser.parse(content: "")
        #expect(ctx.projects.isEmpty)
        #expect(ctx.dailyCapacityMinutes == 240)
    }

    @Test func ignoresUnknownSections() {
        let content = """
        ## Random Stuff
        blah blah

        ## Settings
        daily_capacity: 2h
        """
        let ctx = MemoryParser.parse(content: content)
        #expect(ctx.dailyCapacityMinutes == 120)
    }
}
