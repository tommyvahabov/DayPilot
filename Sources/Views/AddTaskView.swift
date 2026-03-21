import SwiftUI

struct AddTaskView: View {
    let store: ScheduleStore
    var compact: Bool = true

    @State private var title = ""
    @State private var project = ""
    @State private var effort = ""
    @State private var deadline = ""

    var body: some View {
        if compact {
            compactView
        } else {
            expandedView
        }
    }

    private var compactView: some View {
        HStack(spacing: 8) {
            TextField("Task title", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { add() }

            TextField("Project", text: $project)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

            TextField("30m", text: $effort)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)

            Button("Add") { add() }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

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
