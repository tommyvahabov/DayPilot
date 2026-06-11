import SwiftUI

/// The menubar IS the HUD: current task + time remaining, with a master-caution
/// symbol swap when the plan no longer fits the day.
///
/// Deliberately a plain HStack of Image+Text: MenuBarExtra labels render inside
/// an NSStatusItem, which silently fails to display dynamic containers like
/// TimelineView (zero-width item, no onAppear — which also killed the window
/// opener and hotkey when they were chained to it). Minute refresh comes from
/// the store's observable `now` tick instead.
struct MenubarHUDLabel: View {
    let store: ScheduleStore
    @AppStorage("hudMode") private var mode: String = "compact"
    @State private var hotKey: HotKeyService?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()

    var body: some View {
        HStack(spacing: 3) {
            if store.cautionActive {
                Image(systemName: "exclamationmark.triangle.fill")
            } else if let nsImage = DayPilotApp.menubarImage {
                Image(nsImage: nsImage)
                    .renderingMode(.original)
            } else {
                Image(systemName: "checklist.checked")
            }
            if mode != "icon", let text = hudText {
                Text(text)
            }
        }
        .onAppear {
            store.start()
            if hotKey == nil {
                let store = self.store
                hotKey = HotKeyService { store.goAround() }
            }
        }
    }

    private var hudText: String? {
        guard store.errorMessage == nil else { return nil }
        let remaining = store.remainingTodayMinutes
        guard remaining > 0 else { return nil }
        let time = store.cautionActive
            ? "↓\(Self.timeFormatter.string(from: store.wheelsDownDate))"
            : DurationParser.format(minutes: remaining)
        if mode == "full", let top = store.queue.today.first {
            let title = top.title.count > 28 ? String(top.title.prefix(27)) + "…" : top.title
            return "\(title) · \(time)"
        }
        return time
    }
}
