import SwiftUI

enum SidebarTab: String, CaseIterable {
    case runway = "Runway"
    case flightLog = "Flight Log"

    var icon: String {
        switch self {
        case .runway: return "airplane.departure"
        case .flightLog: return "book.closed"
        }
    }
}

struct MainWindowView: View {
    @Bindable var store: ScheduleStore
    @State private var selectedTab: SidebarTab = .runway

    var body: some View {
        NavigationSplitView {
            List(SidebarTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180)
        } detail: {
            VStack(spacing: 0) {
                switch selectedTab {
                case .runway:
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

                case .flightLog:
                    FlightLogView(store: store)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 450)
        .onAppear { store.start() }
    }
}
