import SwiftUI

struct SettingsView: View {
    @Bindable var store: ScheduleStore
    @State private var capacityText: String = ""
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Daily Capacity
            VStack(alignment: .leading, spacing: 8) {
                Text("Daily Capacity")
                    .font(.headline)
                Text("How many hours of tasks to schedule per day")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ForEach(presets, id: \.self) { preset in
                        Button(preset) {
                            capacityText = preset
                            saveCapacity()
                        }
                        .buttonStyle(.bordered)
                        .tint(capacityText == preset ? .accentColor : nil)
                    }

                    TextField("Custom (e.g. 5h30m)", text: $capacityText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit { saveCapacity() }

                    Button("Set") { saveCapacity() }
                        .buttonStyle(.borderedProminent)
                }

                Text("Current: \(DurationParser.format(minutes: store.context.dailyCapacityMinutes))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Scheduler Directory
            VStack(alignment: .leading, spacing: 8) {
                Text("Files")
                    .font(.headline)

                HStack {
                    Text("~/scheduler/")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Open in Finder") {
                        let path = NSHomeDirectory() + "/scheduler"
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            capacityText = DurationParser.format(minutes: store.context.dailyCapacityMinutes)
        }
    }

    private var presets: [String] {
        ["2h", "4h", "6h", "8h"]
    }

    private func saveCapacity() {
        let trimmed = capacityText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let minutes = DurationParser.parseMinutes(trimmed)
        guard minutes > 0 else { return }
        store.setDailyCapacity(trimmed)
        capacityText = DurationParser.format(minutes: minutes)
    }
}
