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

@Suite("TodoParser v2 tokens")
struct TodoParserTokenTests {
    @Test func parsesNewTokens() {
        let items = TodoParser.parse(lines: ["- [ ] T | project: X | defer: 2026-06-12 | carried: 2 | by: claude"])
        #expect(items.count == 1)
        #expect(items[0].carried == 2)
        #expect(items[0].addedBy == "claude")
        #expect(items[0].deferUntil != nil)
    }

    @Test func setTokenReplacesAndRemoves() {
        let line = "- [ ] T | effort: 30m | carried: 1"
        let bumped = TodoParser.setToken(line: line, key: "carried", value: "2")
        #expect(bumped.contains("carried: 2"))
        #expect(!bumped.contains("carried: 1"))
        #expect(bumped.contains("effort: 30m"))
        #expect(bumped.hasPrefix("- [ ] T"))
        let removed = TodoParser.setToken(line: bumped, key: "carried", value: nil)
        #expect(!removed.contains("carried:"))
    }

    @Test func proposedTasksParseSeparately() {
        let lines = ["- [?] Maybe | project: X", "- [ ] Real"]
        #expect(TodoParser.parse(lines: lines).map(\.title) == ["Real"])
        let proposals = TodoParser.proposals(lines: lines)
        #expect(proposals.map(\.title) == ["Maybe"])
        #expect(proposals[0].isProposed)
    }

    @Test func proposedNotesDoNotLeakToPreviousTask() {
        let lines = ["- [ ] Real", "- [?] Maybe", "  a proposal note"]
        let real = TodoParser.parse(lines: lines)
        #expect(real[0].notes.isEmpty)
        #expect(TodoParser.proposals(lines: lines)[0].notes == ["a proposal note"])
    }
}
