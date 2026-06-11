import SwiftUI

/// Morning ritual: confront the payload-vs-runway math once, consciously,
/// before the day starts. Dismissible, never nags.
struct PreflightCardView: View {
    let store: ScheduleStore
    @AppStorage("preflightDismissedOn") private var dismissedOn: String = ""

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var todayKey: String { Self.dayFormatter.string(from: Date()) }

    private var shouldShow: Bool {
        !store.preflightDoneToday
            && dismissedOn != todayKey
            && Calendar.current.component(.hour, from: Date()) < 12
            && !store.queue.today.isEmpty
    }

    private var payload: Int { store.remainingTodayMinutes }
    private var runway: Int { store.context.dailyCapacityMinutes }
    private var overweight: Bool { payload > runway }

    var body: some View {
        if shouldShow {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                        Text("PRE-FLIGHT")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        dismissedOn = todayKey
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(DurationParser.format(minutes: payload)) payload / \(DurationParser.format(minutes: runway)) runway")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                        if overweight {
                            Label("Overweight — trim now or go-around later", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        } else {
                            Text("\(store.queue.today.count) tasks queued. Plan fits.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Begin day") {
                        store.markPreflight()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.background.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.orange.opacity(overweight ? 0.35 : 0.18), lineWidth: 1)
            )
        }
    }
}
