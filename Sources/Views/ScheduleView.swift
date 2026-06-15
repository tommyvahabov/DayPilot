import SwiftUI

struct ScheduleView: View {
    @Bindable var store: ScheduleStore
    @Environment(\.openWindow) private var openWindow

    @State private var showPostflight = false

    private var isEvening: Bool {
        Calendar.current.component(.hour, from: Date()) >= 17
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PreflightCardView(store: store)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            BriefingCardView(store: store, collapsible: true)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            ProposalsView(store: store)
                .padding(.horizontal, 12)
                .padding(.top, 12)

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
                Button(action: { store.goAround() }) {
                    Label(goAroundLabel, systemImage: "arrow.uturn.up")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Repack what's left of today from now; divert the rest to tomorrow (⌃⌥G)")

                if store.dayClosedToday {
                    Label("Flight closed", systemImage: "airplane.arrival")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if isEvening {
                    Button(action: { showPostflight = true }) {
                        Label("Close the day", systemImage: "airplane.arrival")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Post-flight: decide what happens to each leftover, then close out")
                } else {
                    Button(action: { showPostflight = true }) {
                        Label("Close the day", systemImage: "airplane.arrival")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Post-flight: decide what happens to each leftover, then close out")
                }

                Button(action: { store.route = .ideas; openWindow(id: "main-window") }) {
                    Image(systemName: "lightbulb")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Open Ideas")

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
        .sheet(isPresented: $showPostflight) {
            PostflightView(store: store)
        }
        .onAppear { store.start() }
        .task(id: store.lastGoAround) {
            guard store.lastGoAround != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            store.lastGoAround = nil
        }
    }

    private var goAroundLabel: String {
        if let s = store.lastGoAround {
            return "Go-around: \(s.kept) kept · \(s.diverted) diverted"
        }
        return "Go-Around"
    }
}
