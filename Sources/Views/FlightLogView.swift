import SwiftUI

struct FlightLogView: View {
    @Bindable var store: ScheduleStore

    private var totalCompleted: Int {
        store.doneLog.reduce(0) { $0 + $1.entries.count }
    }

    private var thisWeekCompleted: Int {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }

        return store.doneLog.reduce(0) { acc, day in
            guard let date = formatter.date(from: day.date), date >= weekStart else { return acc }
            return acc + day.entries.count
        }
    }

    private var bestDay: (date: String, count: Int)? {
        guard let max = store.doneLog.max(by: { $0.entries.count < $1.entries.count }), max.entries.count > 0 else { return nil }
        return (max.date, max.entries.count)
    }

    var body: some View {
        if store.doneLog.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statsRow
                    timeline
                }
                .padding(24)
            }
            .background(
                LinearGradient(
                    colors: [Color.indigo.opacity(0.04), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "airplane.departure")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.indigo)
            }
            Text("No flights logged yet")
                .font(.system(size: 16, weight: .semibold))
            Text("Complete a task to see it here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Flight Log")
                .font(.system(size: 26, weight: .bold))
            Text("Every task you've shipped.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCardView(
                icon: "checkmark.seal.fill",
                value: "\(totalCompleted)",
                label: "Total shipped",
                accent: .indigo
            )
            StatCardView(
                icon: "calendar",
                value: "\(thisWeekCompleted)",
                label: "This week",
                accent: .blue
            )
            StatCardView(
                icon: "trophy.fill",
                value: bestDay.map { "\($0.count)" } ?? "—",
                label: "Best day",
                accent: .orange,
                sublabel: bestDay?.date
            )
            StatCardView(
                icon: "calendar.badge.checkmark",
                value: "\(store.doneLog.count)",
                label: "Active days",
                accent: .green
            )
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(store.doneLog) { day in
                dayCard(day)
            }
        }
    }

    private func dayCard(_ day: DoneDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(prettyDate(day.date))
                    .font(.system(size: 14, weight: .semibold))
                Text("\(day.entries.count) shipped")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.indigo.opacity(0.15)))
                    .foregroundStyle(.indigo)
                Spacer()
                Text(day.date)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().opacity(0.3)

            VStack(spacing: 0) {
                ForEach(Array(day.entries.enumerated()), id: \.element.id) { i, entry in
                    entryRow(entry)
                    if i < day.entries.count - 1 {
                        Divider().opacity(0.15).padding(.leading, 38)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func entryRow(_ entry: DoneEntry) -> some View {
        HStack(spacing: 10) {
            Button {
                store.uncompleteByTitle(entry.title)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
            }
            .buttonStyle(.borderless)
            .help("Reopen this task")

            Text(entry.title)
                .font(.system(size: 13))

            Spacer()

            if let project = entry.project {
                Text(project)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(pillColor(for: project).opacity(0.18))
                    .foregroundStyle(pillColor(for: project))
                    .clipShape(Capsule())
            }

            if !entry.effort.isEmpty {
                Text(entry.effort)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func prettyDate(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func pillColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .mint, .brown]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}
