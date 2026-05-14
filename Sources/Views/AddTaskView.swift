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

    private var compactView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 14))

                TextField("What's next?  e.g. Ship landing page #quizpilot 45m", text: $title)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit { addCompact() }

                if !title.isEmpty {
                    Button(action: { addCompact() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.background.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(fieldFocused ? 0.18 : 0.08), lineWidth: 1)
            )

            Text("Use #project, 30m / 1h, !YYYY-MM-DD")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
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

    private func addCompact() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let parsed = Self.smartParse(trimmed)
        var raw = parsed.title
        if let p = parsed.project { raw += " | project: \(p)" }
        if let e = parsed.effort { raw += " | effort: \(e)" }
        if let d = parsed.deadline { raw += " | deadline: \(d)" }

        store.addTask(raw: raw)
        title = ""
    }

    static func smartParse(_ input: String) -> (title: String, project: String?, effort: String?, deadline: String?) {
        var titleTokens: [String] = []
        var project: String?
        var effort: String?
        var deadline: String?

        for token in input.split(separator: " ").map(String.init) {
            if (token.hasPrefix("#") || token.hasPrefix("@")) && token.count > 1 {
                project = String(token.dropFirst())
            } else if token.hasPrefix("!") && token.count > 1 && isDate(String(token.dropFirst())) {
                deadline = String(token.dropFirst())
            } else if effort == nil && isDuration(token) {
                effort = token
            } else {
                titleTokens.append(token)
            }
        }

        return (titleTokens.joined(separator: " "), project, effort, deadline)
    }

    private static func isDuration(_ s: String) -> Bool {
        let lower = s.lowercased()
        guard !lower.isEmpty else { return false }
        var i = lower.startIndex
        var sawHour = false
        var sawMinute = false
        while i < lower.endIndex {
            guard lower[i].isNumber else { return false }
            var digitEnd = i
            while digitEnd < lower.endIndex, lower[digitEnd].isNumber {
                digitEnd = lower.index(after: digitEnd)
            }
            guard digitEnd < lower.endIndex else { return false }
            let unit = lower[digitEnd]
            if unit == "h" && !sawHour && !sawMinute { sawHour = true }
            else if unit == "m" && !sawMinute { sawMinute = true }
            else { return false }
            i = lower.index(after: digitEnd)
        }
        return sawHour || sawMinute
    }

    private static func isDate(_ s: String) -> Bool {
        let parts = s.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return false }
        return parts.allSatisfy { $0.allSatisfy { $0.isNumber } }
    }
}
