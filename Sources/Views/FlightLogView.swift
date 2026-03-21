import SwiftUI

struct FlightLogView: View {
    @Bindable var store: ScheduleStore

    var body: some View {
        if store.doneLog.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "airplane.departure")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No completed tasks yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(store.doneLog) { day in
                    Section {
                        ForEach(day.entries) { entry in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)

                                Text(entry.title)

                                Spacer()

                                if let project = entry.project {
                                    Text(project)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(pillColor(for: project).opacity(0.2))
                                        .foregroundStyle(pillColor(for: project))
                                        .clipShape(Capsule())
                                }

                                if !entry.effort.isEmpty {
                                    Text(entry.effort)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    } header: {
                        Text(day.date)
                            .font(.headline)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func pillColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo, .mint, .brown]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}
