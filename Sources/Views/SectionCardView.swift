import SwiftUI

struct SectionCardView: View {
    let title: String
    let icon: String
    let accent: Color
    @Binding var items: [TodoItem]
    let store: ScheduleStore
    var subtitle: String? = nil
    var emptyText: String = "Nothing here yet"
    var maxHeight: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().opacity(0.3)

            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            TaskRowView(
                                index: index + 1,
                                item: item,
                                compact: false,
                                onComplete: { store.completeTask(item) },
                                onUncomplete: { store.uncompleteTask(item) },
                                onNotesChanged: { notes in store.updateNotes(for: item, notes: notes) }
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
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

                            if index < items.count - 1 {
                                Divider()
                                    .opacity(0.15)
                                    .padding(.leading, 48)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxHeight: maxHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 22, height: 22)
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 18))
                .foregroundStyle(.tertiary)
            Text(emptyText)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}
