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

    @Test func emptyTodosReturnsEmptyQueue() {
        let queue = Scheduler.schedule(todos: [], context: context)
        #expect(queue.today.isEmpty)
        #expect(queue.tomorrow.isEmpty)
        #expect(queue.backlog.isEmpty)
    }
}
