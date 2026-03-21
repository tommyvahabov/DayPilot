struct DayQueue: Equatable {
    var today: [TodoItem]
    var tomorrow: [TodoItem]
    var backlog: [TodoItem]
    var completedToday: [TodoItem]

    init(today: [TodoItem] = [], tomorrow: [TodoItem] = [], backlog: [TodoItem] = [], completedToday: [TodoItem] = []) {
        self.today = today
        self.tomorrow = tomorrow
        self.backlog = backlog
        self.completedToday = completedToday
    }

    var todayEffort: Int { today.reduce(0) { $0 + $1.effortMinutes } }
    var tomorrowEffort: Int { tomorrow.reduce(0) { $0 + $1.effortMinutes } }
}
