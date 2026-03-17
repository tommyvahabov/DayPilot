struct DayQueue: Equatable {
    var today: [TodoItem]
    var tomorrow: [TodoItem]
    var backlog: [TodoItem]

    init(today: [TodoItem] = [], tomorrow: [TodoItem] = [], backlog: [TodoItem] = []) {
        self.today = today
        self.tomorrow = tomorrow
        self.backlog = backlog
    }

    var todayEffort: Int { today.reduce(0) { $0 + $1.effortMinutes } }
    var tomorrowEffort: Int { tomorrow.reduce(0) { $0 + $1.effortMinutes } }
}
