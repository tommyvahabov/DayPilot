import SwiftUI

struct TaskRowView: View {
    let index: Int
    let item: TodoItem
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onComplete) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Text("\(index).")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)

            Text(item.title)
                .lineLimit(1)

            Spacer()

            if let project = item.project {
                Text(project)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(pillColor(for: project).opacity(0.2))
                    .foregroundStyle(pillColor(for: project))
                    .clipShape(Capsule())
            }

            Text(DurationParser.format(minutes: item.effortMinutes))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private func pillColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .mint, .brown]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}
