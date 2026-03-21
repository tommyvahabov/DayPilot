import SwiftUI

struct TaskRowView: View {
    let index: Int
    let item: TodoItem
    let compact: Bool
    let onComplete: () -> Void
    var onUncomplete: (() -> Void)?
    var onNotesChanged: (([String]) -> Void)?

    @State private var isExpanded = false
    @State private var noteText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    if item.isCompleted {
                        onUncomplete?()
                    } else {
                        onComplete()
                    }
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isCompleted ? .green : .secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)

                Text("\(index).")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 24, alignment: .trailing)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                        if isExpanded {
                            noteText = item.notes.joined(separator: "\n")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(item.title)
                            .lineLimit(compact ? 1 : nil)
                            .fixedSize(horizontal: false, vertical: !compact)
                            .foregroundStyle(.primary)

                        if !item.notes.isEmpty {
                            Image(systemName: "note.text")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.borderless)

                Spacer()

                if let project = item.project {
                    Text(project)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(pillColor(for: project).opacity(0.2))
                        .foregroundStyle(pillColor(for: project))
                        .clipShape(Capsule())
                        .fixedSize()
                }

                Text(DurationParser.format(minutes: item.effortMinutes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if !item.notes.isEmpty {
                        ForEach(item.notes, id: \.self) { note in
                            Text(note)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 6) {
                        TextField("Add a note...", text: $noteText, axis: .vertical)
                            .font(.callout)
                            .textFieldStyle(.plain)
                            .lineLimit(1...5)

                        Button("Save") {
                            let notes = noteText
                                .split(separator: "\n", omittingEmptySubsequences: false)
                                .map { String($0) }
                                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                            onNotesChanged?(notes)
                            withAnimation { isExpanded = false }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
                .padding(.leading, 56)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private func pillColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .mint, .brown]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}
