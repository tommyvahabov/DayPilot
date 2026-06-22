import Testing
import Foundation
@testable import DayPilot

@Suite("TaskStatus state machine")
struct TaskStatusTests {
    @Test func deliveredCanBeAcceptedOrDeclined() {
        #expect(TaskStatus.delivered.canTransition(to: .accepted))
        #expect(TaskStatus.delivered.canTransition(to: .declined))
    }

    @Test func deliveredCannotJumpStraightToDone() {
        // Done only happens once the task is on the coworker's list, i.e. after accept.
        #expect(!TaskStatus.delivered.canTransition(to: .done))
    }

    @Test func acceptedCanOnlyBecomeDone() {
        #expect(TaskStatus.accepted.canTransition(to: .done))
        #expect(!TaskStatus.accepted.canTransition(to: .declined))
        #expect(!TaskStatus.accepted.canTransition(to: .delivered))
    }

    @Test func declinedAndDoneAreTerminal() {
        #expect(TaskStatus.declined.isTerminal)
        #expect(TaskStatus.done.isTerminal)
        #expect(!TaskStatus.delivered.isTerminal)
        #expect(!TaskStatus.accepted.isTerminal)
        for next in [TaskStatus.accepted, .declined, .done, .delivered] {
            #expect(!TaskStatus.declined.canTransition(to: next))
            #expect(!TaskStatus.done.canTransition(to: next))
        }
    }

    @Test func noSelfTransitions() {
        for s in [TaskStatus.delivered, .accepted, .declined, .done] {
            #expect(!s.canTransition(to: s))
        }
    }

    @Test func encodesAsRawString() throws {
        let data = try JSONEncoder().encode(TaskStatus.accepted)
        #expect(String(data: data, encoding: .utf8) == "\"accepted\"")
    }

    @Test func applyingLegalUpdateAdvances() {
        #expect(TaskStatus.delivered.applying(.accepted) == .accepted)
        #expect(TaskStatus.accepted.applying(.done) == .done)
    }

    @Test func applyingIllegalUpdateKeepsCurrentStatus() {
        // A duplicate "done" ack, or a packet that arrives out of order, must not
        // walk the row backwards or sideways.
        #expect(TaskStatus.done.applying(.accepted) == .done)
        #expect(TaskStatus.done.applying(.done) == .done)
        #expect(TaskStatus.accepted.applying(.delivered) == .accepted)
        #expect(TaskStatus.declined.applying(.done) == .declined)
    }
}

@Suite("SharedTask")
struct SharedTaskTests {
    @Test func titleIsTheOnlyRequiredField() {
        let task = SharedTask(title: "Ship it")
        #expect(task.title == "Ship it")
        #expect(task.project == nil)
        #expect(task.effortMinutes == nil)
        #expect(task.priority == nil)
        #expect(task.note == nil)
        #expect(task.from == nil)
    }

    @Test func carriesACollabTrackingID() {
        let a = SharedTask(title: "A")
        let b = SharedTask(title: "B")
        #expect(a.id != b.id)  // each task gets its own collab tag
    }

    @Test func roundTripsThroughCodable() throws {
        let task = SharedTask(
            id: UUID(),
            title: "Fix battle protocol timeout",
            project: "AvtoPilot",
            effortMinutes: 60,
            priority: 1,
            note: "customers stuck on round 3, see Sentry #412",
            from: "Tommy"
        )
        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(SharedTask.self, from: data)
        #expect(decoded == task)
    }
}

@Suite("CollabMessage envelope")
struct CollabMessageTests {
    @Test func taskMessageRoundTrips() throws {
        let task = SharedTask(title: "Do the thing", project: "DayPilot", from: "Tommy")
        let message = CollabMessage.task(task)
        let decoded = try CollabMessage.decode(message.encoded())
        #expect(decoded == message)
    }

    @Test func statusUpdateMessageRoundTrips() throws {
        let update = StatusUpdate(collabID: UUID(), status: .done)
        let message = CollabMessage.statusUpdate(update)
        let decoded = try CollabMessage.decode(message.encoded())
        #expect(decoded == message)
    }

    @Test func taskAndStatusEnvelopesAreDistinguishable() throws {
        let task = CollabMessage.task(SharedTask(title: "X"))
        let status = CollabMessage.statusUpdate(StatusUpdate(collabID: UUID(), status: .accepted))
        // Decoding a task payload never yields a statusUpdate case and vice versa.
        #expect(try CollabMessage.decode(task.encoded()) == task)
        #expect(try CollabMessage.decode(status.encoded()) == status)
        #expect(task != status)
    }
}
