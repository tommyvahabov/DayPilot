import Testing
import Foundation
@testable import DayPilot

@Suite("Scheduler")
struct SchedulerTests {
    let context = MemoryContext(
        projects: [
            ProjectInfo(name: "Alpha", priority: 1, deadline: nil),
            ProjectInfo(name: "Beta", priority: 2, deadline: nil),
        ],
        dailyCapacityMinutes: 60
    )

    @Test func fillsTodayUpToCapacity() {
        let todos = [
            TodoItem(title: "A", project: "Alpha", effortMinutes: 30),
            TodoItem(title: "B", project: "Alpha", effortMinutes: 30),
            TodoItem(title: "C", project: "Alpha", effortMinutes: 30),
        ]
        let queue = Scheduler.schedule(todos: todos, context: context)
        #expect(queue.today.count == 2)
        #expect(queue.todayEffort == 60)
        #expect(queue.tomorrow.count == 1)
    }

    @Test func sortsDeadlineFirst() {
        let soon = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let later = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        let todos = [
            TodoItem(title: "Later", project: "Alpha", effortMinutes: 30, deadline: later),
            TodoItem(title: "Soon", project: "Alpha", effortMinutes: 30, deadline: soon),
        ]
        let queue = Scheduler.schedule(todos: todos, context: context)
        #expect(queue.today[0].title == "Soon")
        #expect(queue.today[1].title == "Later")
    }

    @Test func noDeadlineSortsLast() {
        let soon = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let todos = [
            TodoItem(title: "No deadline", project: "Alpha", effortMinutes: 30),
            TodoItem(title: "Has deadline", project: "Alpha", effortMinutes: 30, deadline: soon),
        ]
        let queue = Scheduler.schedule(todos: todos, context: context)
        #expect(queue.today[0].title == "Has deadline")
        #expect(queue.today[1].title == "No deadline")
    }

    @Test func projectPriorityBreaksTies() {
        let todos = [
            TodoItem(title: "Beta task", project: "Beta", effortMinutes: 30),
            TodoItem(title: "Alpha task", project: "Alpha", effortMinutes: 30),
        ]
        let queue = Scheduler.schedule(todos: todos, context: context)
        #expect(queue.today[0].title == "Alpha task")
        #expect(queue.today[1].title == "Beta task")
    }

    @Test func overflowGoesToBacklog() {
        let todos = (1...5).map { i in
            TodoItem(title: "Task \(i)", project: "Alpha", effortMinutes: 30)
        }
        let queue = Scheduler.schedule(todos: todos, context: context)
        #expect(queue.today.count == 2)
        #expect(queue.tomorrow.count == 2)
        #expect(queue.backlog.count == 1)
    }

    @Test func tieBreakIsFileOrder() {
        let todos = [
            TodoItem(title: "Big first", project: "Alpha", effortMinutes: 45, lineIndex: 1),
            TodoItem(title: "Small second", project: "Alpha", effortMinutes: 15, lineIndex: 2),
        ]
        let queue = Scheduler.schedule(todos: todos, context: context)
        #expect(queue.today.map(\.title) == ["Big first", "Small second"])
    }

    @Test func emptyTodosReturnsEmptyQueue() {
        let queue = Scheduler.schedule(todos: [], context: context)
        #expect(queue.today.isEmpty)
        #expect(queue.tomorrow.isEmpty)
        #expect(queue.backlog.isEmpty)
    }

    // MARK: Flight math

    private func date(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    @Test func noCautionWhenPlanFits() {
        // 10:00, 2h remaining, capacity 6h, nothing done → lands 12:00, well clear
        let ctx = MemoryContext(dailyCapacityMinutes: 360)
        #expect(!Scheduler.cautionActive(now: date(hour: 10), remainingMinutes: 120, minutesDoneToday: 0, context: ctx))
    }

    @Test func cautionWhenOverrunningAdminEnd() {
        // 20:00 with 3h remaining → wheels down 23:00, past adminEnd 22:00
        let ctx = MemoryContext(dailyCapacityMinutes: 600)
        #expect(Scheduler.cautionActive(now: date(hour: 20), remainingMinutes: 180, minutesDoneToday: 0, context: ctx))
    }

    @Test func cautionWhenOverCapacity() {
        // 9:00, 5h remaining but only 4h capacity left (6h cap, 2h done)
        let ctx = MemoryContext(dailyCapacityMinutes: 360)
        #expect(Scheduler.cautionActive(now: date(hour: 9), remainingMinutes: 300, minutesDoneToday: 120, context: ctx))
    }

    @Test func wheelsDownAddsRemaining() {
        let now = date(hour: 14)
        let eta = Scheduler.wheelsDown(now: now, remainingMinutes: 90)
        #expect(eta == now.addingTimeInterval(90 * 60))
    }
}
