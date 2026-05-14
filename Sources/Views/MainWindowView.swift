import SwiftUI

enum SidebarTab: String, CaseIterable {
    case runway = "Runway"
    case flightLog = "Flight Log"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .runway: return "airplane.departure"
        case .flightLog: return "book.closed.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var accent: Color {
        switch self {
        case .runway: return .accentColor
        case .flightLog: return .indigo
        case .settings: return .secondary
        }
    }
}

struct MainWindowView: View {
    @Bindable var store: ScheduleStore
    @State private var selectedTab: SidebarTab = .runway

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
        } detail: {
            detail
                .navigationTitle("")
        }
        .frame(minWidth: 980, minHeight: 600)
        .onAppear { store.start() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 10)

            Divider().opacity(0.4)

            VStack(spacing: 2) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    SidebarRow(tab: tab, isSelected: selectedTab == tab) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(10)

            Spacer()

            footer
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .background(.background.secondary)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 30, height: 30)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-25))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("DayPilot")
                    .font(.system(size: 14, weight: .semibold))
                Text("by Pilot AI")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Connected")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text("~/scheduler/")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedTab {
        case .runway:
            RunwayDashboardView(store: store)
        case .flightLog:
            FlightLogView(store: store)
        case .settings:
            SettingsView(store: store)
        }
    }
}

private struct SidebarRow: View {
    let tab: SidebarTab
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(tab.accent) : AnyShapeStyle(.secondary))
                    .frame(width: 18)

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.08) : (hovering ? Color.primary.opacity(0.04) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
