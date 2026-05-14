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
    @State private var planeVisible = false
    @State private var flying = false
    @State private var titleHidden = false

    private func triggerComplete() {
        guard !flying else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            planeVisible = true
        }
        withAnimation(.easeIn(duration: 1.4)) {
            flying = true
        }
        withAnimation(.easeIn(duration: 0.8).delay(0.5)) {
            titleHidden = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            onComplete()
        }
    }

    private var liftoff: Bool { flying }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    if item.isCompleted {
                        onUncomplete?()
                    } else {
                        triggerComplete()
                    }
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(item.isCompleted ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)

                Text("\(index)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .frame(width: 14, alignment: .trailing)

                ZStack(alignment: .leading) {
                    Image(systemName: "airplane")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .rotationEffect(.degrees(-14))
                        .opacity(planeVisible ? 1 : 0)
                        .offset(x: flying ? 700 : -40, y: flying ? -14 : 0)
                        .allowsHitTesting(false)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                            if isExpanded {
                                noteText = item.notes.joined(separator: "\n")
                            }
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 13))
                                .lineLimit(compact ? 1 : nil)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: !compact)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                .strikethrough(item.isCompleted, color: .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if !item.notes.isEmpty {
                                Image(systemName: "note.text")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(flying)
                    .opacity(titleHidden ? 0 : 1)
                    .offset(x: flying ? 760 : 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let project = item.project {
                    Text(project)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(pillColor(for: project).opacity(0.18))
                        .foregroundStyle(pillColor(for: project))
                        .clipShape(Capsule())
                        .fixedSize()
                        .opacity(liftoff ? 0 : 1)
                }

                Text(DurationParser.format(minutes: item.effortMinutes))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .fixedSize()
                    .opacity(liftoff ? 0 : 1)
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
        .padding(.vertical, 4)
    }

    private func pillColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .mint, .brown]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}
