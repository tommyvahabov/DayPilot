import SwiftUI

/// Claude's proposed tasks (`- [?]` lines): visible, attributed, and waiting
/// for a human verdict. AI proposes, you decide.
struct ProposalsView: View {
    let store: ScheduleStore

    var body: some View {
        if !store.proposals.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.indigo)
                    Text("PROPOSALS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(store.proposals.count) from Claude")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                ForEach(store.proposals) { item in
                    proposalRow(item)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.indigo.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.indigo.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private func proposalRow(_ item: TodoItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                if let firstNote = item.notes.first {
                    Text(firstNote)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let project = item.project {
                Text(project)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(ProjectColor.color(for: project).opacity(0.18))
                    .foregroundStyle(ProjectColor.color(for: project))
                    .clipShape(Capsule())
            }

            Button {
                store.acceptProposal(item)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .help("Accept — becomes a real task")

            Button {
                store.rejectProposal(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reject — removed and logged")
        }
        .padding(.vertical, 2)
    }
}
