import SwiftUI

/// Claude's morning briefing (briefing.md), rendered only when dated today.
/// Collapsible so it never crowds the popover.
struct BriefingCardView: View {
    let store: ScheduleStore
    var collapsible: Bool = false
    @State private var isExpanded = true

    var body: some View {
        if let briefing = store.briefing {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.indigo)
                    if collapsible {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text("MORNING BRIEFING")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1.2)
                                    .foregroundStyle(.primary)
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Text("MORNING BRIEFING")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: "sparkle")
                        .font(.system(size: 9))
                        .foregroundStyle(.indigo)
                        .help("Written by Claude")
                }

                if isExpanded {
                    Text(LocalizedStringKey(briefing))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.indigo.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.indigo.opacity(0.15), lineWidth: 1)
            )
        }
    }
}
