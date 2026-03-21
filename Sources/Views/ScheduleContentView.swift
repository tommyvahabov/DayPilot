import SwiftUI

/// Shared task list content used by both popover and window.
struct ScheduleContentView: View {
    @Bindable var store: ScheduleStore
    var compact: Bool = true

    var body: some View {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if compact {
            compactLayout
        } else {
            expandedLayout
        }
    }

    private var compactLayout: some View {
        List {
            todaySection
            tomorrowSection
            backlogSection
        }
        .listStyle(.plain)
    }

    private var expandedLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            List {
                todaySection
            }
            .listStyle(.plain)

            Divider()

            List {
                tomorrowSection
            }
            .listStyle(.plain)

            Divider()

            List {
                backlogSection
            }
            .listStyle(.plain)
        }
    }

    private var todaySection: some View {
        TaskSectionView(
            title: "Today",
            subtitle: "\(DurationParser.format(minutes: store.queue.todayEffort)) / \(DurationParser.format(minutes: store.context.dailyCapacityMinutes))",
            items: $store.queue.today,
            section: .today,
            store: store,
            compact: compact
        )
    }

    private var tomorrowSection: some View {
        TaskSectionView(
            title: "Tomorrow",
            subtitle: DurationParser.format(minutes: store.queue.tomorrowEffort),
            items: $store.queue.tomorrow,
            section: .tomorrow,
            store: store,
            compact: compact
        )
    }

    @ViewBuilder
    private var backlogSection: some View {
        if !store.queue.backlog.isEmpty || !compact {
            TaskSectionView(
                title: "Backlog",
                subtitle: "\(store.queue.backlog.count) tasks",
                items: $store.queue.backlog,
                section: .backlog,
                store: store,
                collapsible: compact,
                compact: compact
            )
        }
    }
}
