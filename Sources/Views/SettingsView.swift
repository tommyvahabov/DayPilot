import SwiftUI

struct SettingsView: View {
    @Bindable var store: ScheduleStore
    @State private var capacityText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                capacityCard
                filesCard
                aboutCard
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.gray.opacity(0.05), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
        .onAppear {
            capacityText = DurationParser.format(minutes: store.context.dailyCapacityMinutes)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 26, weight: .bold))
            Text("Tune DayPilot to your day.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var capacityCard: some View {
        card(icon: "gauge.with.dots.needle.67percent", accent: .blue, title: "Daily Capacity", subtitle: "How many hours of focused tasks fit in a day") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        Button(preset) {
                            capacityText = preset
                            saveCapacity()
                        }
                        .buttonStyle(.bordered)
                        .tint(capacityText == preset ? .accentColor : nil)
                        .controlSize(.regular)
                    }
                }

                HStack(spacing: 8) {
                    TextField("Custom (e.g. 5h30m)", text: $capacityText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit { saveCapacity() }

                    Button("Set") { saveCapacity() }
                        .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text("Currently: ")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(DurationParser.format(minutes: store.context.dailyCapacityMinutes))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var filesCard: some View {
        card(icon: "folder.fill", accent: .orange, title: "Files", subtitle: "DayPilot reads & writes plain markdown") {
            VStack(alignment: .leading, spacing: 10) {
                fileRow(name: "todos.md", description: "Your task list")
                fileRow(name: "memory.md", description: "Projects, priorities, capacity")
                fileRow(name: "done.md", description: "Completion log")

                Button {
                    let path = NSHomeDirectory() + "/scheduler"
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                } label: {
                    Label("Open ~/scheduler/", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
    }

    private var aboutCard: some View {
        card(icon: "paperplane.fill", accent: .accentColor, title: "About", subtitle: "DayPilot v1.1.0 — by Pilot AI") {
            HStack(spacing: 6) {
                Text("Built native in SwiftUI.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Local-only.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("No tracking, no cloud.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fileRow(name: String, description: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text(name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
            Text("—")
                .foregroundStyle(.tertiary)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func card<Content: View>(icon: String, accent: Color, title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
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
