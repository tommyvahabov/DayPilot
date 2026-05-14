import SwiftUI

struct ScheduleView: View {
    @Bindable var store: ScheduleStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NowCardView(store: store)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScheduleContentView(store: store, compact: true)

            Divider()

            AddTaskView(store: store)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            HStack(spacing: 6) {
                Button(action: { store.recompute() }) {
                    Label("Reschedule", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button(action: { openWindow(id: "main-window") }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Open full window")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .foregroundStyle(.secondary)
        }
        .frame(width: 360, height: 560)
        .onAppear { store.start() }
    }
}
