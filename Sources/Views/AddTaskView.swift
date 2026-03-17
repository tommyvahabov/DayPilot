import SwiftUI

struct AddTaskView: View {
    let store: ScheduleStore
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("Task | project: X | effort: 30m", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { add() }

            Button("Add") { add() }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        store.addTask(raw: text)
        text = ""
    }
}
