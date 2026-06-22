import Testing
import Foundation
@testable import DayPilot

@Suite("CollabBridge serialize")
struct CollabBridgeSerializeTests {
    @Test func builtLineLooksHandWritten() {
        let id = UUID()
        let task = SharedTask(
            id: id,
            title: "Fix battle protocol timeout",
            project: "AvtoPilot",
            effortMinutes: 60,
            from: "Tommy"
        )
        let line = CollabBridge.todoLine(for: task)
        #expect(line == "- [ ] Fix battle protocol timeout | project: AvtoPilot | effort: 1h | from: Tommy | collab: \(id.uuidString)")
    }

    @Test func minimalTaskIsJustTitleAndCollabTag() {
        let id = UUID()
        let line = CollabBridge.todoLine(for: SharedTask(id: id, title: "Quick thing"))
        #expect(line == "- [ ] Quick thing | collab: \(id.uuidString)")
    }

    @Test func includesPriorityWhenSet() {
        let task = SharedTask(id: UUID(), title: "T", priority: 2)
        #expect(CollabBridge.todoLine(for: task).contains("priority: 2"))
    }

    @Test func sanitizesTitlePipesSoTheLineStaysParseable() {
        let id = UUID()
        let line = CollabBridge.todoLine(for: SharedTask(id: id, title: "a | b"))
        // Exactly one real token separator beyond the title: the collab tag.
        #expect(line == "- [ ] a / b | collab: \(id.uuidString)")
    }

    @Test func noteBecomesContextNoteLine() {
        let task = SharedTask(title: "T", note: "customers stuck on round 3, see Sentry #412")
        #expect(CollabBridge.notes(for: task) == ["CONTEXT: customers stuck on round 3, see Sentry #412"])
    }

    @Test func absentOrBlankNoteYieldsNoNotes() {
        #expect(CollabBridge.notes(for: SharedTask(title: "T")).isEmpty)
        #expect(CollabBridge.notes(for: SharedTask(title: "T", note: "   ")).isEmpty)
    }

    @Test func serializedLineRoundTripsBackThroughTheCollabID() {
        let task = SharedTask(id: UUID(), title: "Round trip", project: "X", effortMinutes: 30, from: "Tommy")
        let line = CollabBridge.todoLine(for: task)
        #expect(CollabBridge.collabID(from: line) == task.id)
        // And the app's own parser reads it as an ordinary task.
        let parsed = TodoParser.parse(lines: [line])
        #expect(parsed.count == 1)
        #expect(parsed[0].title == "Round trip")
        #expect(parsed[0].project == "X")
        #expect(parsed[0].effortMinutes == 30)
    }
}

@Suite("CollabBridge collab id extraction")
struct CollabBridgeIDTests {
    @Test func findsTheCollabToken() {
        let id = UUID()
        let line = "- [x] Done | project: X | collab: \(id.uuidString)"
        #expect(CollabBridge.collabID(from: line) == id)
    }

    @Test func nonCollabLineReturnsNil() {
        #expect(CollabBridge.collabID(from: "- [ ] Plain task | project: X") == nil)
    }

    @Test func aTitleMentioningCollabDoesNotFalseMatch() {
        #expect(CollabBridge.collabID(from: "- [ ] write the collab feature") == nil)
    }

    @Test func garbageCollabValueReturnsNil() {
        #expect(CollabBridge.collabID(from: "- [ ] T | collab: not-a-uuid") == nil)
    }
}

@Suite("CollabBridge done detection")
struct CollabBridgeDoneTests {
    @Test func detectsACollabTaggedCheckboxFlip() {
        let id = UUID()
        let old = ["- [ ] T | collab: \(id.uuidString)"]
        let new = ["- [x] T | collab: \(id.uuidString)"]
        #expect(CollabBridge.newlyCompletedCollabIDs(old: old, new: new) == [id])
    }

    @Test func ignoresFlipsOnNonCollabTasks() {
        let old = ["- [ ] Ordinary task"]
        let new = ["- [x] Ordinary task"]
        #expect(CollabBridge.newlyCompletedCollabIDs(old: old, new: new).isEmpty)
    }

    @Test func noFlipWhenStillOpen() {
        let id = UUID()
        let lines = ["- [ ] T | collab: \(id.uuidString)"]
        #expect(CollabBridge.newlyCompletedCollabIDs(old: lines, new: lines).isEmpty)
    }

    @Test func alreadyDoneTaskDoesNotRefire() {
        let id = UUID()
        let lines = ["- [x] T | collab: \(id.uuidString)"]
        #expect(CollabBridge.newlyCompletedCollabIDs(old: lines, new: lines).isEmpty)
    }

    @Test func uncompletingThenRecompletingFiresAgain() {
        let id = UUID()
        let done = ["- [x] T | collab: \(id.uuidString)"]
        let open = ["- [ ] T | collab: \(id.uuidString)"]
        #expect(CollabBridge.newlyCompletedCollabIDs(old: done, new: open).isEmpty)   // un-checked: no fire
        #expect(CollabBridge.newlyCompletedCollabIDs(old: open, new: done) == [id])   // re-checked: fires
    }

    @Test func handlesMultipleTasksAndOnlyReportsTheFlipped() {
        let a = UUID(), b = UUID()
        let old = ["- [ ] A | collab: \(a.uuidString)", "- [ ] B | collab: \(b.uuidString)"]
        let new = ["- [x] A | collab: \(a.uuidString)", "- [ ] B | collab: \(b.uuidString)"]
        #expect(CollabBridge.newlyCompletedCollabIDs(old: old, new: new) == [a])
    }
}
