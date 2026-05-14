import SwiftUI
import AppKit

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
    @Bindable var updateChecker: UpdateChecker
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
            brandIcon
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("DayPilot")
                    .font(.system(size: 14, weight: .semibold))
                Text("by Pilot AI")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var brandIcon: some View {
        if let url = Bundle.module.url(forResource: "SidebarIcon", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            updateBadge
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Connected")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text("~/scheduler/  •  v\(updateChecker.currentVersion)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var updateBadge: some View {
        switch updateChecker.status {
        case .idle:
            if updateChecker.isUpdateAvailable, let latest = updateChecker.latestVersion {
                Button {
                    Task { await updateChecker.installUpdate() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                        Text("Update to \(latest)")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .help("Click to download and install the latest version")
            }
        case .downloading(let progress):
            HStack(spacing: 6) {
                ProgressView(value: progress).controlSize(.small).frame(width: 60)
                Text("Downloading…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .failed(let msg):
            Text("Update failed: \(msg)")
                .font(.system(size: 9))
                .foregroundStyle(.red)
                .lineLimit(2)
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
