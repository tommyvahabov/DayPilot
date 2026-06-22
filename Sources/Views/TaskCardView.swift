import SwiftUI

/// A single task rendered as a clean, self-contained card. Tap the body to
/// expand notes + attachments; the pencil (or right-click) opens the full
/// editor modal. Owns its own completion animation and editor sheet so the
/// board/popover just hand it a store and an item.
struct TaskCardView: View {
    let store: ScheduleStore
    let item: TodoItem
    var compact: Bool = false

    /// Injected at the scene root so any card can hand its task to a coworker
    /// without threading the peer manager through the whole board.
    @Environment(PeerManager.self) private var peers

    @State private var isExpanded = false
    @State private var showEditor = false

    // Completion "lift-off" animation.
    @State private var planeVisible = false
    @State private var flying = false
    @State private var titleHidden = false

    private static let deadlineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private var hasDetail: Bool { !item.notes.isEmpty || !item.attachments.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow

            if isExpanded {
                detail
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(compact ? 9 : 12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .opacity(item.isCompleted ? 0.6 : 1)
        .contextMenu { contextMenu }
        .sheet(isPresented: $showEditor) {
            TaskEditorSheet(store: store, item: item)
        }
    }

    private var borderColor: Color {
        if let project = item.project {
            return ProjectColor.color(for: project).opacity(0.22)
        }
        return Color.primary.opacity(0.06)
    }

    // MARK: - Main row

    private var mainRow: some View {
        HStack(alignment: .top, spacing: 10) {
            checkbox

            ZStack(alignment: .leading) {
                Image(systemName: "airplane")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .rotationEffect(.degrees(-14))
                    .opacity(planeVisible ? 1 : 0)
                    .offset(x: flying ? 600 : -36, y: flying ? -12 : 0)
                    .allowsHitTesting(false)

                Button(action: toggleExpand) {
                    titleAndMeta
                        .opacity(titleHidden ? 0 : 1)
                        .offset(x: flying ? 660 : 0)
                }
                .buttonStyle(.plain)
                .disabled(flying)
            }

            trailing
        }
    }

    private var checkbox: some View {
        Button {
            if item.isCompleted { store.uncompleteTask(item) } else { triggerComplete() }
        } label: {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: compact ? 15 : 17))
                .foregroundStyle(item.isCompleted ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.plain)
        .help(item.isCompleted ? "Mark as not done" : "Complete")
    }

    private var titleAndMeta: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.title)
                    .font(.system(size: compact ? 12.5 : 13.5, weight: .medium))
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .lineLimit(compact && !isExpanded ? 2 : nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if item.addedBy == "claude" {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9))
                        .foregroundStyle(.indigo)
                        .help("Added by Claude")
                }
            }

            metaRow
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(item.rationale ?? "")
    }

    @ViewBuilder
    private var metaRow: some View {
        let chips = metaChips
        if !chips.isEmpty {
            HStack(spacing: 6) {
                ForEach(chips) { $0.view }
            }
        }
    }

    private var metaChips: [MetaChip] {
        var chips: [MetaChip] = []
        if let p = item.priority {
            chips.append(MetaChip(id: "priority", view: AnyView(
                HStack(spacing: 2.5) {
                    Image(systemName: "flag.fill").font(.system(size: 8))
                    Text(PriorityStyle.badge(p)).font(.system(size: 9.5, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(PriorityStyle.color(p).opacity(0.16))
                .foregroundStyle(PriorityStyle.color(p))
                .clipShape(Capsule())
            )))
        }
        if let project = item.project {
            chips.append(MetaChip(id: "project", view: AnyView(
                Text(project)
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ProjectColor.color(for: project).opacity(0.16))
                    .foregroundStyle(ProjectColor.color(for: project))
                    .clipShape(Capsule())
            )))
        }
        chips.append(MetaChip(id: "effort", view: AnyView(
            metaLabel(DurationParser.format(minutes: item.effortMinutes), system: "clock")
        )))
        if let deadline = item.deadline {
            chips.append(MetaChip(id: "deadline", view: AnyView(
                metaLabel(deadlineText(deadline), system: "calendar")
                    .foregroundStyle(deadlineColor(deadline))
            )))
        }
        if !item.attachments.isEmpty {
            chips.append(MetaChip(id: "attach", view: AnyView(
                metaLabel("\(item.attachments.count)", system: "paperclip")
            )))
        }
        if !item.notes.isEmpty {
            chips.append(MetaChip(id: "notes", view: AnyView(
                metaLabel("\(item.notes.count)", system: "note.text")
            )))
        }
        if item.carried >= 3 {
            chips.append(MetaChip(id: "carried", view: AnyView(
                metaLabel("\(item.carried)d", system: "arrow.uturn.right")
                    .foregroundStyle(.orange)
            )))
        }
        return chips
    }

    private func metaLabel(_ text: String, system: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: system).font(.system(size: 8.5))
            Text(text).font(.system(size: 10, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(.secondary)
    }

    private var trailing: some View {
        Button(action: { showEditor = true }) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .opacity(flying ? 0 : 1)
        .help("Edit task")
    }

    // MARK: - Expanded detail

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !item.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.notes, id: \.self) { note in
                        Text(note)
                            .font(.system(size: compact ? 11.5 : 12.5))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }

            if !item.attachments.isEmpty {
                AttachmentGalleryView(attachments: item.attachments, thumbSide: compact ? 56 : 72)
            }

            if !hasDetail {
                Text("No notes yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Button(action: { showEditor = true }) {
                Label("Edit details", systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.leading, 28)
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        if item.isCompleted {
            Button { store.uncompleteTask(item) } label: { Label("Mark not done", systemImage: "arrow.uturn.backward") }
        } else {
            Button { triggerComplete() } label: { Label("Complete", systemImage: "checkmark.circle") }
        }
        Button { showEditor = true } label: { Label("Edit…", systemImage: "square.and.pencil") }
        handoffMenu
        if !item.attachments.isEmpty {
            Button { for a in item.attachments { AttachmentService.open(a) } } label: {
                Label("Open attachments", systemImage: "paperclip")
            }
        }
        Divider()
        Button(role: .destructive) { store.removeTask(item) } label: { Label("Delete", systemImage: "trash") }
    }

    /// "Hand off to…" — send this existing task to a connected coworker (CoPilot).
    /// Shown only when there's someone to hand it to and the task is still open.
    @ViewBuilder
    private var handoffMenu: some View {
        let connected = peers.peers.filter { $0.connection == .connected }
        if !item.isCompleted && !connected.isEmpty {
            Menu {
                ForEach(connected) { peer in
                    Button(peer.displayName) {
                        peers.send(CollabBridge.sharedTask(from: item), to: peer.displayName)
                    }
                }
            } label: {
                Label("Hand off to…", systemImage: "paperplane")
            }
        }
    }

    // MARK: - Behaviour

    private func toggleExpand() {
        withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
    }

    private func triggerComplete() {
        guard !flying else { return }
        withAnimation(.easeOut(duration: 0.12)) { planeVisible = true }
        withAnimation(.easeIn(duration: 0.7)) { flying = true }
        withAnimation(.easeIn(duration: 0.4).delay(0.25)) { titleHidden = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { store.completeTask(item) }
    }

    private func deadlineText(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "today" }
        if cal.isDateInTomorrow(date) { return "tmrw" }
        if cal.isDateInYesterday(date) { return "yest" }
        return Self.deadlineFormatter.string(from: date)
    }

    private func deadlineColor(_ date: Date) -> Color {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        if date < startOfToday { return .red }
        if cal.isDateInToday(date) || cal.isDateInTomorrow(date) { return .orange }
        return .secondary
    }
}

private struct MetaChip: Identifiable {
    let id: String
    let view: AnyView
}
