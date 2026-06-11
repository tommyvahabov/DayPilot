import SwiftUI

struct RunwayDashboardView: View {
    @Bindable var store: ScheduleStore

    private var minutesLeft: Int { store.queue.today.reduce(0) { $0 + $1.effortMinutes } }
    private var minutesDone: Int { store.queue.completedToday.reduce(0) { $0 + $1.effortMinutes } }
    private var activeProjects: Int {
        Set((store.queue.today + store.queue.tomorrow + store.queue.backlog).compactMap { $0.project }).count
    }
    private var streak: Int { RitualStreak.compute(days: store.doneLog) }

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
                label: "Flight days",
                accent: .orange,
                sublabel: streak == 0 ? "Close a day to start" : "Plan it, fly it, close it"
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
                    section: .tomorrow,
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
                    section: .backlog,
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

            if let s = store.lastGoAround {
                Text("\(s.kept) kept · \(s.diverted) diverted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button(action: { store.goAround() }) {
                Label("Go-Around", systemImage: "arrow.uturn.up")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Repack what's left of today from now; divert the rest to tomorrow (⌃⌥G)")
        }
    }

}
