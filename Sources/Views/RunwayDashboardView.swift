import SwiftUI

struct RunwayDashboardView: View {
    @Bindable var store: ScheduleStore

    private var minutesLeft: Int { store.queue.today.reduce(0) { $0 + $1.effortMinutes } }
    private var minutesDone: Int { store.queue.completedToday.reduce(0) { $0 + $1.effortMinutes } }
    private var activeProjects: Int {
        Set((store.queue.today + store.queue.tomorrow + store.queue.backlog).compactMap { $0.project }).count
    }
    private var streak: Int { computeStreak(from: store.doneLog) }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 18) {
                        hero
                        statsRow
                        boards
                    }
                    .padding(20)
                }

                Divider()

                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.background.secondary)
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.04),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .center
        )
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            NowCardView(store: store)
                .frame(maxWidth: .infinity)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCardView(
                icon: "checkmark.circle.fill",
                value: "\(store.completedTodayCount)",
                label: "Done today",
                accent: .green,
                sublabel: minutesDone > 0 ? DurationParser.format(minutes: minutesDone) + " logged" : "Let's get started"
            )
            StatCardView(
                icon: "clock.fill",
                value: DurationParser.format(minutes: minutesLeft),
                label: "Time left",
                accent: .blue,
                sublabel: "\(store.queue.today.count) tasks queued"
            )
            StatCardView(
                icon: "flame.fill",
                value: "\(streak)",
                label: "Day streak",
                accent: .orange,
                sublabel: streak == 0 ? "Ship something today" : "Keep it alive"
            )
            StatCardView(
                icon: "tag.fill",
                value: "\(activeProjects)",
                label: "Active projects",
                accent: .purple,
                sublabel: "\(store.context.projects.count) tracked"
            )
        }
    }

    private var boards: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 14) {
                SectionCardView(
                    title: "Today",
                    icon: "sun.max.fill",
                    accent: .green,
                    items: $store.queue.today,
                    store: store,
                    subtitle: "\(store.completedTodayCount)/\(store.totalTodayCount) done",
                    emptyText: "Runway is clear",
                    maxHeight: 480
                )

                if !store.queue.completedToday.isEmpty {
                    SectionCardView(
                        title: "Done today",
                        icon: "checkmark.seal.fill",
                        accent: .secondary,
                        items: $store.queue.completedToday,
                        store: store,
                        subtitle: "\(store.queue.completedToday.count) shipped",
                        emptyText: "Nothing shipped yet",
                        maxHeight: 220
                    )
                    .opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 14) {
                SectionCardView(
                    title: "Tomorrow",
                    icon: "sunrise.fill",
                    accent: .blue,
                    items: $store.queue.tomorrow,
                    store: store,
                    subtitle: DurationParser.format(minutes: store.queue.tomorrowEffort),
                    emptyText: "Tomorrow is open",
                    maxHeight: 280
                )

                SectionCardView(
                    title: "Backlog",
                    icon: "tray.full.fill",
                    accent: .orange,
                    items: $store.queue.backlog,
                    store: store,
                    subtitle: "\(store.queue.backlog.count) waiting",
                    emptyText: "Backlog is empty",
                    maxHeight: 360
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            AddTaskView(store: store, compact: false)

            Button(action: { store.recompute() }) {
                Label("Reschedule", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func computeStreak(from log: [DoneDay]) -> Int {
        guard !log.isEmpty else { return 0 }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let datesWithEntries: Set<Date> = Set(log.compactMap { day in
            day.entries.isEmpty ? nil : formatter.date(from: day.date)
        })

        guard !datesWithEntries.isEmpty else { return 0 }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var cursor = today
        var streak = 0

        if !datesWithEntries.contains(where: { calendar.isDate($0, inSameDayAs: today) }) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            cursor = yesterday
        }

        while datesWithEntries.contains(where: { calendar.isDate($0, inSameDayAs: cursor) }) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        return streak
    }
}
