import SwiftUI

@main
struct DayPilotApp: App {
    var body: some Scene {
        MenuBarExtra("DayPilot", systemImage: "checklist.checked") {
            ScheduleView()
        }
        .menuBarExtraStyle(.window)
    }
}
