import SwiftUI

/// CoPilot: hand a task to a coworker across the office. No cloud, no account —
/// packets stay on the local network. Peers · composer · inbox · outbox.
struct CollabView: View {
    let store: ScheduleStore
    @Bindable var peers: PeerManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !peers.pendingInvites.isEmpty { pendingInvitesCard }
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        NearbyPeersCard(peers: peers)
                        ComposerCard(store: store, peers: peers)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 16) {
                        InboxCard(peers: peers)
                        OutboxCard(peers: peers)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .onAppear { peers.markInboxSeen() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("COPILOT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.tertiary)
                Text("Hand off a task")
                    .font(.system(size: 25, weight: .bold))
                Text("Peer-to-peer across the office — no cloud, no account.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(peers.isOnline ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text(peers.isOnline ? "On the air as \(peers.localName)" : "Offline")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.background.secondary))
        .help(peers.isOnline ? "Advertising over Bluetooth + local WiFi" : "Not advertising")
    }

    // MARK: - Pending invites

    private var pendingInvitesCard: some View {
        CollabCard(title: "PAIRING REQUESTS", systemImage: "person.crop.circle.badge.questionmark",
                   accent: .orange, count: peers.pendingInvites.count) {
            ForEach(peers.pendingInvites) { invite in
                HStack(spacing: 8) {
                    Text(invite.displayName)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Pair") { peers.acceptInvite(invite) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Ignore") { peers.declineInvite(invite) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Nearby peers

private struct NearbyPeersCard: View {
    @Bindable var peers: PeerManager

    var body: some View {
        CollabCard(title: "NEARBY", systemImage: "antenna.radiowaves.left.and.right",
                   accent: .teal, count: peers.peers.count) {
            if peers.peers.isEmpty {
                Text("Looking for coworkers running DayPilot…")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(peers.peers) { peer in
                    peerRow(peer)
                }
            }
        }
    }

    private func peerRow(_ peer: DiscoveredPeer) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor(peer.connection))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(peer.displayName)
                    .font(.system(size: 12, weight: .medium))
                Text(stateLabel(peer.connection))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            if peer.isTrusted {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.teal)
                    .help("Paired — reconnects automatically")
            }
            Spacer()
            trailingControl(peer)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func trailingControl(_ peer: DiscoveredPeer) -> some View {
        switch peer.connection {
        case .connected:
            if peer.isTrusted {
                Button("Unpair") { peers.unpair(peer.displayName) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
            }
        case .connecting:
            ProgressView().controlSize(.small)
        case .discovered:
            Button("Pair") { peers.pair(with: peer.displayName) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func dotColor(_ c: PeerConnection) -> Color {
        switch c {
        case .connected: return .green
        case .connecting: return .orange
        case .discovered: return .secondary
        }
    }

    private func stateLabel(_ c: PeerConnection) -> String {
        switch c {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .discovered: return "Nearby"
        }
    }
}

// MARK: - Composer

private struct ComposerCard: View {
    let store: ScheduleStore
    @Bindable var peers: PeerManager

    @State private var title = ""
    @State private var project = ""
    @State private var effort = ""
    @State private var priority: Int? = nil
    @State private var note = ""
    @State private var recipient: String = ""

    private var connectedPeers: [String] {
        peers.peers.filter { $0.connection == .connected }.map(\.displayName)
    }

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !resolvedRecipient.isEmpty
    }

    /// Selected recipient, defaulting to the only/first connected peer.
    private var resolvedRecipient: String {
        if connectedPeers.contains(recipient) { return recipient }
        return connectedPeers.first ?? ""
    }

    var body: some View {
        CollabCard(title: "COMPOSE", systemImage: "paperplane", accent: .blue, count: nil) {
            if connectedPeers.isEmpty {
                Text("Pair with a coworker to send them a task.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                composer
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Task title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.background.secondary))
                .onSubmit(send)

            chipRow(label: "Project", chips: projectChips)
            chipRow(label: "Priority", chips: priorityChips)
            chipRow(label: "Effort", chips: effortChips)

            TextField("Context (optional) — becomes a CONTEXT note", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .lineLimit(1...3)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.background.secondary))

            HStack(spacing: 8) {
                if connectedPeers.count > 1 {
                    Picker("To", selection: Binding(get: { resolvedRecipient }, set: { recipient = $0 })) {
                        ForEach(connectedPeers, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                } else {
                    Text("To \(resolvedRecipient)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { send() } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!canSend)
            }
        }
    }

    private var projectChips: [ChipModel] {
        store.context.projects.prefix(6).map { p in
            ChipModel(label: p.name, isSelected: project == p.name) {
                project = (project == p.name) ? "" : p.name
            }
        }
    }

    private var priorityChips: [ChipModel] {
        PriorityStyle.levels.map { p in
            ChipModel(label: "P\(p)", isSelected: priority == p) {
                priority = (priority == p) ? nil : p
            }
        }
    }

    private var effortChips: [ChipModel] {
        ["15m", "30m", "1h", "2h"].map { v in
            ChipModel(label: v, isSelected: effort == v) {
                effort = (effort == v) ? "" : v
            }
        }
    }

    private func chipRow(label: String, chips: [ChipModel]) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 48, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(chips) { ChipView(chip: $0) }
                }
            }
        }
    }

    private func send() {
        let to = resolvedRecipient
        let cleanTitle = TodoParser.sanitizeTitle(title)
        guard !cleanTitle.isEmpty, !to.isEmpty else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = SharedTask(
            title: cleanTitle,
            project: project.isEmpty ? nil : project,
            effortMinutes: effort.isEmpty ? nil : DurationParser.parseMinutes(effort),
            priority: priority,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
        peers.send(task, to: to)
        title = ""; project = ""; effort = ""; priority = nil; note = ""
    }
}

// MARK: - Inbox

private struct InboxCard: View {
    @Bindable var peers: PeerManager

    var body: some View {
        CollabCard(title: "INBOX", systemImage: "tray.and.arrow.down",
                   accent: .indigo, count: peers.inbox.isEmpty ? nil : peers.inbox.count) {
            if peers.inbox.isEmpty {
                Text("Nothing handed to you yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(peers.inbox) { item in
                    inboxRow(item)
                    if item.id != peers.inbox.last?.id { Divider().opacity(0.3) }
                }
            }
        }
    }

    private func inboxRow(_ item: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if item.unread {
                    Circle().fill(Color.indigo).frame(width: 6, height: 6)
                }
                Text(item.task.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                Spacer()
                StatusPill(status: item.status)
            }
            TaskMetaRow(task: item.task, from: item.fromPeer)
            inboxActions(item)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func inboxActions(_ item: InboxItem) -> some View {
        HStack(spacing: 8) {
            Spacer()
            switch item.status {
            case .delivered:
                Button("Decline") { peers.decline(item) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Accept") { peers.accept(item) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            case .accepted:
                Text("On your list")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Button("Mark done") { peers.markDone(item) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            case .declined, .done:
                EmptyView()
            }
        }
    }
}

// MARK: - Outbox

private struct OutboxCard: View {
    @Bindable var peers: PeerManager

    var body: some View {
        CollabCard(title: "OUTBOX", systemImage: "tray.and.arrow.up",
                   accent: .blue, count: peers.outbox.isEmpty ? nil : peers.outbox.count) {
            if peers.outbox.isEmpty {
                Text("Tasks you send show their status here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(peers.outbox) { item in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.task.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text("to \(item.toPeer)")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        StatusPill(status: item.status)
                    }
                    .padding(.vertical, 3)
                    if item.id != peers.outbox.last?.id { Divider().opacity(0.3) }
                }
            }
        }
    }
}

// MARK: - Shared bits

/// Status of a handed-off task, with the colour matching its lifecycle.
private struct StatusPill: View {
    let status: TaskStatus

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }

    private var label: String {
        switch status {
        case .delivered: return "DELIVERED"
        case .accepted: return "ACCEPTED"
        case .declined: return "DECLINED"
        case .done: return "DONE"
        }
    }

    private var color: Color {
        switch status {
        case .delivered: return .secondary
        case .accepted: return .blue
        case .declined: return .red
        case .done: return .green
        }
    }
}

/// The project / effort / priority / sender line under a task.
private struct TaskMetaRow: View {
    let task: SharedTask
    var from: String?

    var body: some View {
        HStack(spacing: 6) {
            if let from {
                Label(from, systemImage: "person.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let project = task.project {
                Text(project)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(ProjectColor.color(for: project).opacity(0.18))
                    .foregroundStyle(ProjectColor.color(for: project))
                    .clipShape(Capsule())
            }
            if let p = task.priority {
                Text(PriorityStyle.badge(p))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PriorityStyle.color(p))
            }
            if let m = task.effortMinutes {
                Text(DurationParser.format(minutes: m))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The framed, titled card used across CoPilot — mirrors ProposalsView's look.
private struct CollabCard<Content: View>: View {
    let title: String
    let systemImage: String
    let accent: Color
    var count: Int?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(accent.opacity(0.16), lineWidth: 1))
    }
}
