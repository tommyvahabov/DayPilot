import SwiftUI

enum EnergyMode {
    case deepWork, lighter, admin, rest

    var label: String {
        switch self {
        case .deepWork: return "Deep Work"
        case .lighter: return "Lighter"
        case .admin: return "Admin"
        case .rest: return "Wind Down"
        }
    }

    var icon: String {
        switch self {
        case .deepWork: return "brain.head.profile"
        case .lighter: return "leaf.fill"
        case .admin: return "tray.fill"
        case .rest: return "moon.fill"
        }
    }

    var color: Color {
        switch self {
        case .deepWork: return .indigo
        case .lighter: return .teal
        case .admin: return .orange
        case .rest: return .purple
        }
    }
}

struct NowCardView: View {
    let store: ScheduleStore

    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var hour: Int { Calendar.current.component(.hour, from: now) }

    private var energy: EnergyMode {
        switch hour {
        case 5..<12: return .deepWork
        case 12..<17: return .lighter
        case 17..<22: return .admin
        default: return .rest
        }
    }

    private var greeting: String {
        switch hour {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<22: return "Evening"
        default: return "Late"
        }
    }

    private var topTask: TodoItem? {
        store.queue.today.first
    }

    private var minutesLeft: Int {
        store.queue.today.reduce(0) { $0 + $1.effortMinutes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            footer
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(energy.color.opacity(0.18), lineWidth: 1)
        )
        .onReceive(timer) { now = $0 }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(greeting.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(timeString)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Spacer()
            energyPill
        }
    }

    @ViewBuilder
    private var content: some View {
        if let task = topTask {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(energy.color)
                        .frame(width: 6, height: 6)
                    Text("UP NEXT")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)
                }
                Text(task.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                metaRow(for: task)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(energy.color)
                Text("Runway clear")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Text("— nothing queued")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metaRow(for task: TodoItem) -> some View {
        HStack(spacing: 8) {
            if let project = task.project {
                tag(project, system: "tag.fill")
            }
            tag(DurationParser.format(minutes: task.effortMinutes), system: "clock")
            if !task.notes.isEmpty {
                tag("\(task.notes.count) note\(task.notes.count == 1 ? "" : "s")", system: "note.text")
            }
        }
    }

    private func tag(_ text: String, system: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: system)
                .font(.system(size: 9))
            Text(text)
                .font(.caption2)
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            stat(value: "\(store.completedTodayCount)/\(store.totalTodayCount)", label: "done")
            divider
            stat(value: DurationParser.format(minutes: minutesLeft), label: "left")
            Spacer()
        }
    }

    private func stat(value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.tertiary)
            .frame(width: 1, height: 10)
    }

    private var energyPill: some View {
        HStack(spacing: 4) {
            Image(systemName: energy.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(energy.label)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(energy.color.opacity(0.15))
        )
        .foregroundStyle(energy.color)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: now)
    }
}
