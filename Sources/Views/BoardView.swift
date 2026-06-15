import SwiftUI

/// The three-lane cockpit: Today · Tomorrow · Backlog, each a clearly separated
/// column of task cards with independent scrolling and in-column drag reorder.
struct BoardView: View {
    @Bindable var store: ScheduleStore

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BoardColumnView(
                store: store,
                title: "Today",
                icon: "sun.max.fill",
                accent: .green,
                items: $store.queue.today,
                section: .today,
                subtitle: todaySubtitle,
                emptyText: "Runway is clear",
                completed: $store.queue.completedToday
            )

            BoardColumnView(
                store: store,
                title: "Tomorrow",
                icon: "sunrise.fill",
                accent: .blue,
                items: $store.queue.tomorrow,
                section: .tomorrow,
                subtitle: store.queue.tomorrow.isEmpty ? nil : DurationParser.format(minutes: store.queue.tomorrowEffort),
                emptyText: "Tomorrow is open"
            )

            BoardColumnView(
                store: store,
                title: "Backlog",
                icon: "tray.full.fill",
                accent: .orange,
                items: $store.queue.backlog,
                section: .backlog,
                subtitle: store.queue.backlog.isEmpty ? nil : "\(store.queue.backlog.count) waiting",
                emptyText: "Backlog is empty"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var todaySubtitle: String? {
        guard store.totalTodayCount > 0 else { return nil }
        return "\(store.completedTodayCount)/\(store.totalTodayCount) done · \(DurationParser.format(minutes: store.queue.todayEffort)) left"
    }
}

struct BoardColumnView: View {
    let store: ScheduleStore
    let title: String
    let icon: String
    let accent: Color
    @Binding var items: [TodoItem]
    let section: ScheduleStore.Section
    var subtitle: String? = nil
    var emptyText: String = "Nothing here"
    var completed: Binding<[TodoItem]>? = nil

    @State private var showCompleted = false
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background.secondary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(dropTargeted ? accent.opacity(0.6) : Color.primary.opacity(0.06), lineWidth: dropTargeted ? 2 : 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(accent.opacity(0.18)).frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text("\(items.count)")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if items.isEmpty {
                    emptyState
                } else {
                    ForEach(items) { item in
                        card(for: item)
                    }
                }

                if let completed, !completed.wrappedValue.isEmpty {
                    completedDisclosure(completed)
                }
            }
            .padding(10)
        }
    }

    private func card(for item: TodoItem) -> some View {
        TaskCardView(store: store, item: item)
            .draggable(item.id.uuidString) {
                Text(item.title)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first, let uuid = UUID(uuidString: id),
                      let toIndex = items.firstIndex(where: { $0.id == item.id }),
                      items.contains(where: { $0.id == uuid }) else { return false }
                withAnimation { store.moveTask(id: uuid, toIndex: toIndex, in: section) }
                return true
            } isTargeted: { dropTargeted = $0 }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)
            Text(emptyText)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    @ViewBuilder
    private func completedDisclosure(_ completed: Binding<[TodoItem]>) -> some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showCompleted.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("Done today")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text("\(completed.wrappedValue.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    Spacer()
                    Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 6)
            }
            .buttonStyle(.plain)

            if showCompleted {
                ForEach(completed.wrappedValue) { done in
                    TaskCardView(store: store, item: done, compact: true)
                }
            }
        }
    }
}
