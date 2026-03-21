import SwiftUI

struct ScheduleView: View {
    @Bindable var store: ScheduleStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScheduleContentView(store: store, compact: true)

            Divider()

            AddTaskView(store: store)
                .padding(12)

            HStack(spacing: 8) {
                Button(action: { store.recompute() }) {
                    Text("Reschedule")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: { openWindow(id: "main-window") }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
                .help("Open full window")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 320, height: 480)
        .onAppear { store.start() }
    }
}
