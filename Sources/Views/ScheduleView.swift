import SwiftUI

struct ScheduleView: View {
    @State var store = ScheduleStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = store.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                List {
                    TaskSectionView(
                        title: "Today",
                        subtitle: "\(DurationParser.format(minutes: store.queue.todayEffort)) / \(DurationParser.format(minutes: store.context.dailyCapacityMinutes))",
                        items: $store.queue.today,
                        section: .today,
                        store: store
                    )

                    TaskSectionView(
                        title: "Tomorrow",
                        subtitle: DurationParser.format(minutes: store.queue.tomorrowEffort),
                        items: $store.queue.tomorrow,
                        section: .tomorrow,
                        store: store
                    )

                    if !store.queue.backlog.isEmpty {
                        TaskSectionView(
                            title: "Backlog",
                            subtitle: "\(store.queue.backlog.count) tasks",
                            items: $store.queue.backlog,
                            section: .backlog,
                            store: store,
                            collapsible: true
                        )
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            AddTaskView(store: store)
                .padding(12)

            Button(action: { store.recompute() }) {
                Text("Reschedule")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 320, height: 480)
        .onAppear { store.start() }
    }
}
