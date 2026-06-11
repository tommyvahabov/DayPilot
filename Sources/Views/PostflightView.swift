import SwiftUI

/// Evening ritual: a conscious choice per leftover (tomorrow / backlog / scrap)
/// instead of a silently rotting overdue pile, then the day is stamped closed.
struct PostflightView: View {
    let store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    @State private var decisions: [UUID: ScheduleStore.EndOfDayChoice] = [:]

    private var leftovers: [TodoItem] { store.queue.today }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Post-flight")
                    .font(.system(size: 18, weight: .bold))
                Text(leftovers.isEmpty
                     ? "All shipped. Close it out."
                     : "\(leftovers.count) left on the runway — decide what happens to each.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if !leftovers.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(leftovers) { item in
                            leftoverRow(item)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }

            HStack {
                Text("\(store.queue.completedToday.count) shipped today")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .controlSize(.small)
                Button("Close the day") {
                    store.closeDay(decisions: decisions)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private func leftoverRow(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if item.carried >= 3 {
                    Label("\(item.carried)", systemImage: "arrow.uturn.right.circle")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                        .help("Carried \(item.carried) days — still worth hauling?")
                }
                Spacer()
                if let project = item.project {
                    Text(project)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(ProjectColor.color(for: project).opacity(0.18))
                        .foregroundStyle(ProjectColor.color(for: project))
                        .clipShape(Capsule())
                }
            }

            Picker("", selection: binding(for: item)) {
                Text("Tomorrow").tag(ScheduleStore.EndOfDayChoice.tomorrow)
                Text("Backlog").tag(ScheduleStore.EndOfDayChoice.backlog)
                Text("Scrap").tag(ScheduleStore.EndOfDayChoice.scrap)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background.secondary)
        )
    }

    private func binding(for item: TodoItem) -> Binding<ScheduleStore.EndOfDayChoice> {
        Binding(
            get: { decisions[item.id] ?? .tomorrow },
            set: { decisions[item.id] = $0 }
        )
    }
}
