import SwiftUI
import AppKit

@main
struct DayPilotApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("DayPilot", systemImage: "checklist.checked") {
            ScheduleView()
        }
        .menuBarExtraStyle(.window)
    }
}
