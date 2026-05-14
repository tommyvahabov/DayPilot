import SwiftUI

struct AddTaskView: View {
    let store: ScheduleStore
    var compact: Bool = true

    @State private var title = ""
    @State private var project = ""
    @State private var effort = ""
    @State private var deadline = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        if compact {
            compactView
        } else {
            expandedView
        }
    }

    @State private var newProjectDraft: String = ""
    @State private var showNewProjectField = false

    private var compactView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 14))

                TextField("What's next?", text: $title)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit { submit() }

                if !title.isEmpty {
                    Button(action: { submit() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.background.secondary))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(fieldFocused ? 0.18 : 0.08), lineWidth: 1)
            )

            if !selectedSummary.isEmpty {
                HStack(spacing: 4) {
                    Text(selectedSummary)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: clearSelections) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 4)
            }

            chipRow(label: "Project", chips: projectChips, trailing: AnyView(newProjectControl))
            chipRow(label: "Effort", chips: effortChips, trailing: nil)
            chipRow(label: "Due", chips: deadlineChips, trailing: nil)
        }
    }

    private var projectChips: [ChipModel] {
        store.context.projects.prefix(6).map { p in
            ChipModel(label: p.name, isSelected: project == p.name) {
                project = (project == p.name) ? "" : p.name
            }
        }
    }

    private var effortChips: [ChipModel] {
        ["15m", "30m", "1h", "2h"].map { v in
            ChipModel(label: v, isSelected: effort == v) {
                effort = (effort == v) ? "" : v
            }
        }
    }

    private var deadlineChips: [ChipModel] {
        let today = Self.isoFormatter.string(from: Date())
        let tomorrow = Self.isoFormatter.string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        return [
            ChipModel(label: "Today", isSelected: deadline == today) {
                deadline = (deadline == today) ? "" : today
            },
            ChipModel(label: "Tomorrow", isSelected: deadline == tomorrow) {
                deadline = (deadline == tomorrow) ? "" : tomorrow
            },
        ]
    }

    private var newProjectControl: some View {
        Group {
            if showNewProjectField {
                HStack(spacing: 4) {
                    TextField("New project", text: $newProjectDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10))
                        .frame(width: 80)
                        .onSubmit { commitNewProject() }
                    Button(action: commitNewProject) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.background.secondary))
            } else {
                Button(action: { showNewProjectField = true }) {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3])))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chipRow(label: String, chips: [ChipModel], trailing: AnyView?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(chips) { chip in
                        ChipView(chip: chip)
                    }
                    if let trailing = trailing { trailing }
                }
            }
        }
    }

    private func commitNewProject() {
        let trimmed = newProjectDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            showNewProjectField = false
            return
        }
        store.saveProjectIfNew(trimmed)
        project = trimmed
        newProjectDraft = ""
        showNewProjectField = false
    }

    private func clearSelections() {
        project = ""
        effort = ""
        deadline = ""
    }

    private var selectedSummary: String {
        var parts: [String] = []
        if !project.isEmpty { parts.append(project) }
        if !effort.isEmpty { parts.append(effort) }
        if !deadline.isEmpty {
            let today = Self.isoFormatter.string(from: Date())
            let tomorrow = Self.isoFormatter.string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
            if deadline == today { parts.append("Today") }
            else if deadline == tomorrow { parts.append("Tomorrow") }
            else { parts.append(deadline) }
        }
        return parts.joined(separator: "  ·  ")
    }

    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var raw = trimmed
        if !project.isEmpty { raw += " | project: \(project)" }
        if !effort.isEmpty { raw += " | effort: \(effort)" }
        if !deadline.isEmpty { raw += " | deadline: \(deadline)" }
        if !project.isEmpty { store.saveProjectIfNew(project) }
        store.addTask(raw: raw)
        title = ""
        clearSelections()
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var expandedView: some View {
        HStack(spacing: 12) {
            TextField("Task title", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { add() }

            TextField("Project", text: $project)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)

            TextField("Effort (e.g. 30m)", text: $effort)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)

            TextField("Deadline (YYYY-MM-DD)", text: $deadline)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)

            Button("Add") { add() }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var raw = trimmed
        let proj = project.trimmingCharacters(in: .whitespaces)
        let eff = effort.trimmingCharacters(in: .whitespaces)
        let dl = deadline.trimmingCharacters(in: .whitespaces)

        if !proj.isEmpty { raw += " | project: \(proj)" }
        if !eff.isEmpty { raw += " | effort: \(eff)" }
        if !dl.isEmpty { raw += " | deadline: \(dl)" }

        store.addTask(raw: raw)
        title = ""
        project = ""
        effort = ""
        deadline = ""
    }

}

struct ChipModel: Identifiable {
    let id = UUID()
    let label: String
    let isSelected: Bool
    let action: () -> Void
}

struct ChipView: View {
    let chip: ChipModel

    var body: some View {
        Button(action: chip.action) {
            Text(chip.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(chip.isSelected ? Color.white : Color.primary.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(chip.isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}
