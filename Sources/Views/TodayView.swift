import SwiftUI

struct TodayView: View {
    @Bindable var store: ScheduleStore

    private var today: Date { Date() }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private var minutesLeft: Int {
        store.queue.today.reduce(0) { $0 + $1.effortMinutes }
    }

    private var minutesDone: Int {
        store.queue.completedToday.reduce(0) { $0 + $1.effortMinutes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                SectionCardView(
                    title: "Today",
                    icon: "sun.max.fill",
                    accent: .green,
                    items: $store.queue.today,
                    store: store,
                    subtitle: subtitle,
                    emptyText: "Runway is clear — nothing left for today",
                    maxHeight: nil
                )

                if !store.queue.completedToday.isEmpty {
                    SectionCardView(
                        title: "Done today",
                        icon: "checkmark.seal.fill",
                        accent: .secondary,
                        items: $store.queue.completedToday,
                        store: store,
                        subtitle: "\(store.queue.completedToday.count) shipped  •  \(formatMinutes(minutesDone)) logged",
                        emptyText: "Nothing shipped yet",
                        maxHeight: nil
                    )
                    .opacity(0.85)
                }
            }
            .padding(24)
            .frame(maxWidth: 800, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TODAY")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.tertiary)
            Text(Self.dayFormatter.string(from: today))
                .font(.system(size: 28, weight: .bold))
            Text(progressLine)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        "\(store.completedTodayCount)/\(store.totalTodayCount) done  •  \(formatMinutes(minutesLeft)) left"
    }

    private var progressLine: String {
        let done = store.completedTodayCount
        let total = store.totalTodayCount
        if total == 0 { return "No tasks scheduled. Add one to get rolling." }
        if done == total { return "All clear. Day's done." }
        return "\(done) of \(total) shipped  •  \(formatMinutes(minutesLeft)) of work left"
    }

    private func formatMinutes(_ m: Int) -> String {
        if m == 0 { return "0m" }
        let h = m / 60
        let mm = m % 60
        if h == 0 { return "\(mm)m" }
        if mm == 0 { return "\(h)h" }
        return "\(h)h \(mm)m"
    }
}
