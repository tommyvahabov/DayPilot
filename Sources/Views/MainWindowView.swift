import SwiftUI

struct MainWindowView: View {
    @Bindable var store: ScheduleStore

    var body: some View {
        VStack(spacing: 0) {
            ScheduleContentView(store: store, compact: false)

            Divider()

            HStack(spacing: 12) {
                AddTaskView(store: store, compact: false)

                Button(action: { store.recompute() }) {
                    Label("Reschedule", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
        }
        .frame(minWidth: 700, minHeight: 400)
        .onAppear { store.start() }
    }
}
