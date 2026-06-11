import SwiftUI

struct TaskRowView: View {
    let index: Int
    let item: TodoItem
    let compact: Bool
    let onComplete: () -> Void
    var onUncomplete: (() -> Void)?
    var onNotesChanged: (([String]) -> Void)?
    /// (title, project, effort, deadline) — empty strings clear a field.
    var onEdit: ((String, String, String, String) -> Void)?
    var onDelete: (() -> Void)?

    @State private var isExpanded = false
    @State private var noteText = ""
    @State private var planeVisible = false
    @State private var flying = false
    @State private var titleHidden = false
    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var editProject = ""
    @State private var editEffort = ""
    @State private var editDeadline = ""

    private static let deadlineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func triggerComplete() {
        guard !flying else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            planeVisible = true
        }
        withAnimation(.easeIn(duration: 0.7)) {
            flying = true
        }
        withAnimation(.easeIn(duration: 0.4).delay(0.25)) {
            titleHidden = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onComplete()
        }
    }

    private var liftoff: Bool { flying }

    private var editForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title", text: $editTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit { saveEdit() }

            HStack(spacing: 6) {
                TextField("project", text: $editProject)
                    .frame(width: 90)
                TextField("30m", text: $editEffort)
                    .frame(width: 54)
                TextField("YYYY-MM-DD", text: $editDeadline)
                    .frame(width: 94)
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))

            HStack(spacing: 6) {
                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete task (auto-git keeps a backup)")
                }
                Spacer()
                Button("Cancel") {
                    withAnimation { isEditing = false }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                Button("Save") { saveEdit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(editTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    private func beginEdit() {
        editTitle = item.title
        editProject = item.project ?? ""
        editEffort = DurationParser.format(minutes: item.effortMinutes)
        editDeadline = item.deadline.map { Self.deadlineFormatter.string(from: $0) } ?? ""
        withAnimation(.easeInOut(duration: 0.15)) { isEditing = true }
    }

    private func saveEdit() {
        guard !editTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onEdit?(editTitle, editProject, editEffort, editDeadline)
        withAnimation {
            isEditing = false
            isExpanded = false
        }
    }

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
                    .help(item.rationale ?? "")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if item.addedBy == "claude" {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9))
                        .foregroundStyle(.indigo)
                        .opacity(liftoff ? 0 : 1)
                        .help("Added by Claude" + (item.notes.first.map { " — \($0)" } ?? ""))
                }

                if item.carried >= 3 {
                    Label("\(item.carried)", systemImage: "arrow.uturn.right.circle")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.orange.opacity(0.18))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                        .fixedSize()
                        .opacity(liftoff ? 0 : 1)
                        .help("Carried \(item.carried) days — still worth hauling?")
                }

                if let project = item.project {
                    Text(project)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(ProjectColor.color(for: project).opacity(0.18))
                        .foregroundStyle(ProjectColor.color(for: project))
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
                    if isEditing {
                        editForm
                    } else {
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

                            if onEdit != nil {
                                Button {
                                    beginEdit()
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .help("Edit task")
                            }

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
                }
                .padding(.leading, 56)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

}
