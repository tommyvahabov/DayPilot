import SwiftUI

/// Shared task list content used by the popover.
struct ScheduleContentView: View {
    @Bindable var store: ScheduleStore
    var compact: Bool = true

    var body: some View {
        if let error = store.errorMessage {
            VStack(spacing: 10) {
                Image(systemName: "doc.questionmark")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button {
                    store.recompute()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                todaySection
                completedSection
                tomorrowSection
                backlogSection
            }
            .listStyle(.plain)
        }
    }

    private var todaySection: some View {
        TaskSectionView(
            title: "Today",
            subtitle: "\(store.completedTodayCount)/\(store.totalTodayCount) done",
            items: $store.queue.today,
            section: .today,
            store: store,
            compact: compact,
            showProgress: true,
            progressCurrent: store.completedTodayCount,
            progressCapacity: store.totalTodayCount
        )
    }

    @ViewBuilder
    private var completedSection: some View {
        if !store.queue.completedToday.isEmpty {
            TaskSectionView(
                title: "Done",
                subtitle: "\(store.queue.completedToday.count) tasks",
                items: $store.queue.completedToday,
                section: .today,
                store: store,
                collapsible: true,
                compact: compact
            )
        }
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
