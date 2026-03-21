import SwiftUI
import AppKit

@main
struct DayPilotApp: App {
    @State private var store = ScheduleStore()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("DayPilot", systemImage: "checklist.checked") {
            ScheduleView(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("DayPilot", id: "main-window") {
            MainWindowView(store: store)
        }
        .defaultSize(width: 800, height: 500)
        .windowResizability(.contentMinSize)
    }
}
