import SwiftUI

struct TaskSectionView: View {
    let title: String
    let subtitle: String?
    @Binding var items: [TodoItem]
    let section: ScheduleStore.Section
    let store: ScheduleStore
    var collapsible: Bool = false
    var compact: Bool = true
    var showProgress: Bool = false
    var progressCurrent: Int = 0
    var progressCapacity: Int = 0

    @State private var isExpanded: Bool
    @State private var draggingItem: TodoItem?

    init(title: String, subtitle: String?, items: Binding<[TodoItem]>, section: ScheduleStore.Section, store: ScheduleStore, collapsible: Bool = false, compact: Bool = true, showProgress: Bool = false, progressCurrent: Int = 0, progressCapacity: Int = 0) {
        self.title = title
        self.subtitle = subtitle
        self._items = items
        self.section = section
        self.store = store
        self.collapsible = collapsible
        self.compact = compact
        self.showProgress = showProgress
        self.progressCurrent = progressCurrent
        self.progressCapacity = progressCapacity
        self._isExpanded = State(initialValue: !collapsible)
    }

    var body: some View {
        if !items.isEmpty || !collapsible {
            VStack(alignment: .leading, spacing: 4) {
                header

                if showProgress {
                    ProgressBarView(current: progressCurrent, capacity: progressCapacity)
                        .padding(.top, 2)
                }

                if isExpanded {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        TaskRowView(index: index + 1, item: item, compact: compact, onComplete: {
                            store.completeTask(item)
                        }, onUncomplete: {
                            store.uncompleteTask(item)
                        }, onNotesChanged: { notes in
                            store.updateNotes(for: item, notes: notes)
                        })
                        .draggable(item.id.uuidString) {
                            Text(item.title)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .dropDestination(for: String.self) { droppedIDs, _ in
                            guard let droppedID = droppedIDs.first,
                                  let fromIndex = items.firstIndex(where: { $0.id.uuidString == droppedID }) else {
                                return false
                            }
                            let toIndex = index
                            if fromIndex != toIndex {
                                withAnimation {
                                    items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                                }
                            }
                            return true
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(headerAccent)
                .frame(width: 5, height: 5)

            if collapsible {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Text(title.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(.primary)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.borderless)
            } else {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.primary)
            }

            Spacer()

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private var headerAccent: Color {
        switch title.lowercased() {
        case "today": return .green
        case "done": return .secondary
        case "tomorrow": return .blue
        case "backlog": return .orange
        default: return .accentColor
        }
    }
}
