import SwiftUI

struct TaskSectionView: View {
    let title: String
    let subtitle: String?
    @Binding var items: [TodoItem]
    let section: ScheduleStore.Section
    let store: ScheduleStore
    var collapsible: Bool = false

    @State private var isExpanded: Bool

    init(title: String, subtitle: String?, items: Binding<[TodoItem]>, section: ScheduleStore.Section, store: ScheduleStore, collapsible: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self._items = items
        self.section = section
        self.store = store
        self.collapsible = collapsible
        self._isExpanded = State(initialValue: !collapsible)
    }

    var body: some View {
        if !items.isEmpty || !collapsible {
            VStack(alignment: .leading, spacing: 4) {
                header
                if isExpanded {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        TaskRowView(index: index + 1, item: item) {
                            store.completeTask(item)
                        }
                    }
                    .onMove { source, destination in
                        store.moveTask(from: source, to: destination, in: section)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            if collapsible {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        Text(title)
                            .font(.headline)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(title)
                    .font(.headline)
            }

            Spacer()

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }
}
