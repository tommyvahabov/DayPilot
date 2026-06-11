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

@Suite("MemoryParser v2")
struct MemoryParserV2Tests {
    @Test func parsesCalibrationSection() {
        let content = """
        ## Calibration
        - QuizPilot: 1.8
        - DayPilot: 1.2
        """
        let ctx = MemoryParser.parse(content: content)
        #expect(ctx.calibrationMultiplier(for: "QuizPilot") == 1.8)
        #expect(ctx.calibrationMultiplier(for: "quizpilot") == 1.8)
        #expect(ctx.calibrationMultiplier(for: "Unknown") == 1.0)
        #expect(ctx.calibrationMultiplier(for: nil) == 1.0)
    }

    @Test func parsesEnergyBlockOverrides() {
        let content = """
        ## Settings
        daily_capacity: 6h
        deep_work: 9-12
        light: 12-18
        admin: 18-23
        """
        let ctx = MemoryParser.parse(content: content)
        #expect(ctx.energy.deepWorkStart == 9)
        #expect(ctx.energy.deepWorkEnd == 12)
        #expect(ctx.energy.lightEnd == 18)
        #expect(ctx.energy.adminEnd == 23)
    }

    @Test func defaultsSurviveAbsentSections() {
        let ctx = MemoryParser.parse(content: "# Memory\n")
        #expect(ctx.energy == EnergyBlocks())
        #expect(ctx.calibration.isEmpty)
    }
}
