import Testing
import Foundation
@testable import DayPilot

@Suite("TodoParser")
struct TodoParserTests {
    @Test func parsesFullTask() {
        let lines = ["- [ ] Build UI | project: DayPilot | effort: 1h | deadline: 2026-03-20"]
        let result = TodoParser.parse(lines: lines)
        #expect(result.count == 1)
        #expect(result[0].title == "Build UI")
        #expect(result[0].project == "DayPilot")
        #expect(result[0].effortMinutes == 60)
        #expect(result[0].isCompleted == false)
    }

    @Test func parsesMinimalTask() {
        let lines = ["- [ ] Quick thing"]
        let result = TodoParser.parse(lines: lines)
        #expect(result.count == 1)
        #expect(result[0].title == "Quick thing")
        #expect(result[0].project == nil)
        #expect(result[0].effortMinutes == 15)
        #expect(result[0].deadline == nil)
    }

    @Test func skipsCompletedTasks() {
        let lines = [
            "- [x] Done task",
            "- [ ] Open task",
        ]
        let result = TodoParser.parse(lines: lines)
        #expect(result.count == 1)
        #expect(result[0].title == "Open task")
    }

    @Test func skipsNonTaskLines() {
        let lines = [
            "# My Todos",
            "",
            "- [ ] Real task",
            "Some random text",
        ]
        let result = TodoParser.parse(lines: lines)
        #expect(result.count == 1)
        #expect(result[0].title == "Real task")
    }

    @Test func marksTaskComplete() {
        var lines = [
            "- [ ] Task one",
            "- [ ] Task two",
        ]
        TodoParser.markComplete(lines: &lines, at: 0)
        #expect(lines[0] == "- [x] Task one")
        #expect(lines[1] == "- [ ] Task two")
    }

    @Test func appendsNewTask() {
        var lines = ["- [ ] Existing"]
        TodoParser.append(lines: &lines, raw: "New task | project: Test | effort: 45m")
        #expect(lines.count == 2)
        #expect(lines[1] == "- [ ] New task | project: Test | effort: 45m")
    }
}
