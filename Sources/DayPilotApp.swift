import SwiftUI
import AppKit

final class WindowOpener {
    static let shared = WindowOpener()
    var open: (() -> Void)?
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowOpener.shared.open?()
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            WindowOpener.shared.open?()
        }
    }
}

struct WindowOpenerBinder: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear {
            WindowOpener.shared.open = { openWindow(id: "main-window") }
        }
    }
}

enum AppResources {
    static func image(named name: String, ext: String = "png") -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return NSImage(contentsOf: url)
    }
}

@main
struct DayPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ScheduleStore()
    @State private var updateChecker = UpdateChecker()

    static let menubarImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenubarIcon@2x", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 17, height: 17)
        img.isTemplate = false
        return img
    }()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        MenuBarExtra {
            ScheduleView(store: store)
                .modifier(WindowOpenerBinder())
        } label: {
            Group {
                if let nsImage = Self.menubarImage {
                    Image(nsImage: nsImage)
                        .renderingMode(.original)
                } else {
                    Image(systemName: "checklist.checked")
                }
            }
            .modifier(WindowOpenerBinder())
        }
        .menuBarExtraStyle(.window)

        Window("DayPilot", id: "main-window") {
            MainWindowView(store: store, updateChecker: updateChecker)
                .task {
                    await updateChecker.check()
                }
        }
        .defaultSize(width: 800, height: 500)
        .windowResizability(.contentMinSize)
    }
}
