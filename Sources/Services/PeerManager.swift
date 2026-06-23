import Foundation
import MultipeerConnectivity
import os

/// A peer this Mac can see on the local network.
struct DiscoveredPeer: Identifiable, Equatable {
    let displayName: String
    var connection: PeerConnection
    var isTrusted: Bool
    var id: String { displayName }
}

enum PeerConnection: Equatable {
    case discovered   // visible, not connected
    case connecting   // invite in flight
    case connected    // session open, ready for handoff
}

/// An incoming pairing request from an untrusted peer, waiting on the user.
struct PendingInvite: Identifiable, Equatable {
    let displayName: String
    var id: String { displayName }
}

/// Owns the MultipeerConnectivity stack: advertiser + browser + an encrypted
/// session, plus the inbox/outbox of handed-off tasks. Mac-to-Mac, Bluetooth +
/// peer-to-peer WiFi, no server. All published state is mutated on the main
/// actor; the MC delegate callbacks (background queue) hop here before touching
/// anything.
///
/// The testable logic (wire format, todos.md serialize, status state machine,
/// done detection) lives in `CollabModels`/`CollabBridge`/`ScheduleStore`; this
/// class is the transport glue, exercised by hand with two Macs.
@MainActor
@Observable
final class PeerManager: NSObject {
    /// Bonjour service type → advertised as `_dpcollab._tcp`. Must also be
    /// listed under NSBonjourServices in Info.plist (macOS 14 requirement).
    static let serviceType = "dpcollab"

    let localName: String
    private(set) var peers: [DiscoveredPeer] = []
    private(set) var inbox: [InboxItem] = []
    private(set) var outbox: [OutboxItem] = []
    private(set) var pendingInvites: [PendingInvite] = []
    private(set) var isOnline = false

    /// Unseen tasks sitting in the inbox — drives the sidebar badge.
    var unreadCount: Int { inbox.filter { $0.unread && $0.status == .delivered }.count }

    @ObservationIgnored private let localPeerID: MCPeerID
    @ObservationIgnored private let session: MCSession
    @ObservationIgnored private let advertiser: MCNearbyServiceAdvertiser
    @ObservationIgnored private let browser: MCNearbyServiceBrowser
    @ObservationIgnored private let logger = Logger(subsystem: "com.pilotai.daypilot", category: "copilot")

    /// Trusted peers by display name; once paired, both ends silently reconnect.
    @ObservationIgnored private var trusted: Set<String>
    /// MCPeerID handles for peers currently visible, so we can invite/send.
    @ObservationIgnored private var peerIDs: [String: MCPeerID] = [:]
    /// Held invitation responders for untrusted peers, until the user decides.
    @ObservationIgnored private var invitationResponders: [String: (Bool, MCSession?) -> Void] = [:]
    /// Peers we've sent an invitation to and are awaiting a verdict from. Used to
    /// detect simultaneous invites and resolve the collision deterministically.
    @ObservationIgnored private var outgoingInvites: Set<String> = []
    /// The todos.md owner — appends accepted tasks, reports checkbox flips back.
    @ObservationIgnored private weak var store: ScheduleStore?
    @ObservationIgnored private var attached = false

    override init() {
        let name = String((Host.current().localizedName ?? "Mac").prefix(60))
        let peer = MCPeerID(displayName: name)
        self.localName = name
        self.localPeerID = peer
        self.session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        self.advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: Self.serviceType)
        self.browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        self.trusted = Self.loadTrusted()
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    /// Wire to the task store and go online. Idempotent.
    func attach(to store: ScheduleStore) {
        guard !attached else { return }
        attached = true
        self.store = store
        // Zero-click "done": when an accepted collab line flips [ ]→[x] in
        // todos.md, ack the sender. Weak self so the store doesn't pin us.
        store.onCollabTaskDone = { [weak self] id in self?.taskCompletedLocally(id) }
        start()
    }

    func start() {
        guard !isOnline else { return }
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        isOnline = true
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        isOnline = false
    }

    // MARK: - Pairing

    /// Invite a discovered peer to pair (first-time handshake).
    func pair(with displayName: String) {
        // If they already invited us, accept theirs instead of opening a second
        // channel (that's what causes the never-connects collision).
        if let responder = invitationResponders.removeValue(forKey: displayName) {
            pendingInvites.removeAll { $0.id == displayName }
            setConnection(displayName, .connecting)
            responder(true, session)
            logger.info("pair \(displayName, privacy: .public): accepted their pending invite")
            return
        }
        guard let peerID = peerIDs[displayName] else { return }
        outgoingInvites.insert(displayName)
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 60)
        setConnection(displayName, .connecting)
        logger.info("pair \(displayName, privacy: .public): invitation sent")
    }

    /// Accept an incoming pairing request.
    func acceptInvite(_ invite: PendingInvite) {
        outgoingInvites.remove(invite.displayName)
        setConnection(invite.displayName, .connecting)
        invitationResponders.removeValue(forKey: invite.displayName)?(true, session)
        pendingInvites.removeAll { $0.id == invite.id }
    }

    /// Decline an incoming pairing request.
    func declineInvite(_ invite: PendingInvite) {
        invitationResponders.removeValue(forKey: invite.displayName)?(false, nil)
        pendingInvites.removeAll { $0.id == invite.id }
    }

    /// Forget a peer so it no longer auto-reconnects.
    func unpair(_ displayName: String) {
        trusted.remove(displayName)
        saveTrusted()
        if let idx = peers.firstIndex(where: { $0.id == displayName }) {
            peers[idx].isTrusted = false
        }
    }

    // MARK: - Sending

    /// Hand a task to a connected coworker. Stamps the sender name, drops it in
    /// the outbox as `delivered`. Returns whether it actually went out.
    @discardableResult
    func send(_ task: SharedTask, to displayName: String, restoreOnDecline: Bool = false) -> Bool {
        guard let peerID = session.connectedPeers.first(where: { $0.displayName == displayName }) else {
            logger.error("send: \(displayName, privacy: .public) not connected")
            return false
        }
        var task = task
        task.from = localName
        guard sendMessage(.task(task), to: [peerID]) else { return false }
        outbox.removeAll { $0.id == task.id }
        outbox.insert(OutboxItem(task: task, toPeer: displayName, status: .delivered,
                                 restoreOnDecline: restoreOnDecline), at: 0)
        return true
    }

    /// Delegate one of my own tasks: send it, then remove it from my list. If the
    /// coworker declines, it's restored (see the statusUpdate handling).
    func handOff(_ item: TodoItem, to displayName: String) {
        if send(CollabBridge.sharedTask(from: item), to: displayName, restoreOnDecline: true) {
            store?.removeTask(item)
        }
    }

    // MARK: - Inbox actions

    /// Accept a received task: it becomes a real line in todos.md and the sender
    /// is told.
    func accept(_ item: InboxItem) {
        guard let idx = inbox.firstIndex(where: { $0.id == item.id }) else { return }
        inbox[idx].status = inbox[idx].status.applying(.accepted)
        inbox[idx].unread = false
        store?.appendSharedTask(item.task)
        sendStatus(.accepted, collabID: item.id, to: item.fromPeer)
    }

    /// Decline a received task and tell the sender.
    func decline(_ item: InboxItem) {
        guard let idx = inbox.firstIndex(where: { $0.id == item.id }) else { return }
        inbox[idx].status = inbox[idx].status.applying(.declined)
        inbox[idx].unread = false
        sendStatus(.declined, collabID: item.id, to: item.fromPeer)
    }

    /// Manual "Done" (build B): drive the same checkbox flip the watcher catches,
    /// so the ack travels the single path in `taskCompletedLocally`.
    func markDone(_ item: InboxItem) {
        store?.completeCollabTask(id: item.id)
    }

    /// Clear the new-arrival badge once the user has looked at the inbox.
    func markInboxSeen() {
        for idx in inbox.indices where inbox[idx].unread {
            inbox[idx].unread = false
        }
    }

    // MARK: - Done relay

    /// An accepted task's line flipped [ ]→[x] locally — tell whoever sent it.
    /// Called by the store's FSEvents-driven flip detection.
    private func taskCompletedLocally(_ id: UUID) {
        guard let idx = inbox.firstIndex(where: { $0.id == id }) else { return }
        inbox[idx].status = inbox[idx].status.applying(.done)
        sendStatus(.done, collabID: id, to: inbox[idx].fromPeer)
    }

    private func sendStatus(_ status: TaskStatus, collabID: UUID, to displayName: String) {
        guard let peerID = session.connectedPeers.first(where: { $0.displayName == displayName }) else { return }
        _ = sendMessage(.statusUpdate(StatusUpdate(collabID: collabID, status: status)), to: [peerID])
    }

    @discardableResult
    private func sendMessage(_ message: CollabMessage, to peerIDs: [MCPeerID]) -> Bool {
        guard !peerIDs.isEmpty else { return false }
        do {
            try session.send(message.encoded(), toPeers: peerIDs, with: .reliable)
            return true
        } catch {
            logger.error("send failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Inbound handling (main actor)

    private func handleData(_ data: Data, from displayName: String) {
        guard let message = try? CollabMessage.decode(data) else {
            logger.error("undecodable message from \(displayName, privacy: .public)")
            return
        }
        switch message {
        case .task(let task):
            // Replace any prior copy (resend) rather than duplicate the row.
            inbox.removeAll { $0.id == task.id }
            inbox.insert(InboxItem(task: task, fromPeer: displayName), at: 0)
        case .statusUpdate(let update):
            guard let idx = outbox.firstIndex(where: { $0.id == update.collabID }) else { return }
            let was = outbox[idx].status
            outbox[idx].status = was.applying(update.status)
            // A delegated task that got declined comes back to my list.
            if outbox[idx].status == .declined, was != .declined, outbox[idx].restoreOnDecline {
                store?.restoreTask(outbox[idx].task)
            }
        }
    }

    private func handleConnection(_ displayName: String, _ peerID: MCPeerID, _ state: MCSessionState) {
        logger.info("session \(displayName, privacy: .public) state=\(state.rawValue)")
        switch state {
        case .connected:
            peerIDs[displayName] = peerID
            outgoingInvites.remove(displayName)
            setConnection(displayName, .connected)
            // First connection only happens after a human paired on both ends,
            // so it's safe to remember the peer for silent reconnect.
            if !trusted.contains(displayName) {
                trusted.insert(displayName)
                saveTrusted()
            }
            markTrusted(displayName)
        case .connecting:
            setConnection(displayName, .connecting)
        case .notConnected:
            outgoingInvites.remove(displayName)
            // A declined duplicate invite (from the collision tiebreak) fires
            // .notConnected even while the real channel is up — don't clobber it.
            if session.connectedPeers.contains(where: { $0.displayName == displayName }) { return }
            if peers.contains(where: { $0.id == displayName }) {
                setConnection(displayName, .discovered)
            }
        @unknown default:
            break
        }
    }

    private func handleFoundPeer(_ displayName: String, _ peerID: MCPeerID) {
        guard displayName != localName else { return }
        peerIDs[displayName] = peerID
        upsertPeer(displayName, connection: .discovered)
        // Silent reconnect: a single deterministic initiator (lower name) invites
        // so both ends don't race to connect.
        if trusted.contains(displayName), localName < displayName {
            pair(with: displayName)
        }
    }

    private func handleLostPeer(_ displayName: String) {
        peerIDs.removeValue(forKey: displayName)
        outgoingInvites.remove(displayName)
        if session.connectedPeers.contains(where: { $0.displayName == displayName }) { return }
        peers.removeAll { $0.id == displayName }
    }

    private func handleInvitation(_ displayName: String,
                                  _ responder: @escaping (Bool, MCSession?) -> Void) {
        let decision = PairingResolver.decide(
            from: displayName, localName: localName,
            trusted: trusted.contains(displayName),
            hasOutgoingInvite: outgoingInvites.contains(displayName)
        )
        logger.info("invitation from \(displayName, privacy: .public) -> \(String(describing: decision), privacy: .public)")
        switch decision {
        case .autoAccept, .acceptIncoming:
            outgoingInvites.remove(displayName)
            setConnection(displayName, .connecting)
            responder(true, session)
        case .rejectIncoming:
            responder(false, nil)                    // ours wins; theirs declined
        case .prompt:
            invitationResponders[displayName] = responder
            upsertPeer(displayName, connection: .discovered)
            if !pendingInvites.contains(where: { $0.id == displayName }) {
                pendingInvites.append(PendingInvite(displayName: displayName))
            }
        }
    }

    // MARK: - Peer list helpers

    private func upsertPeer(_ displayName: String, connection: PeerConnection) {
        if let idx = peers.firstIndex(where: { $0.id == displayName }) {
            peers[idx].connection = connection
        } else {
            peers.append(DiscoveredPeer(displayName: displayName,
                                        connection: connection,
                                        isTrusted: trusted.contains(displayName)))
        }
    }

    private func setConnection(_ displayName: String, _ connection: PeerConnection) {
        upsertPeer(displayName, connection: connection)
    }

    private func markTrusted(_ displayName: String) {
        if let idx = peers.firstIndex(where: { $0.id == displayName }) {
            peers[idx].isTrusted = true
        }
    }

    // MARK: - Trust persistence

    private static func trustURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DayPilot", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("trusted-peers.json")
    }

    private static func loadTrusted() -> Set<String> {
        guard let data = try? Data(contentsOf: trustURL()),
              let names = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(names)
    }

    private func saveTrusted() {
        let data = try? JSONEncoder().encode(Array(trusted).sorted())
        try? data?.write(to: Self.trustURL(), options: .atomic)
    }
}

// MARK: - MultipeerConnectivity delegates
//
// Delivered on a private background queue; each hops to the main actor before
// touching published state. MC value types aren't Sendable, so they cross the
// boundary in an unchecked box (we only read them on the main actor afterward).

private struct SendableBox<T>: @unchecked Sendable { let value: T }

extension PeerManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let box = SendableBox(value: peerID)
        let name = peerID.displayName
        Task { @MainActor in self.handleConnection(name, box.value, state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let name = peerID.displayName
        Task { @MainActor in self.handleData(data, from: name) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension PeerManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let name = peerID.displayName
        let box = SendableBox(value: invitationHandler)
        Task { @MainActor in self.handleInvitation(name, box.value) }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in self.isOnline = false }
    }
}

extension PeerManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let box = SendableBox(value: peerID)
        let name = peerID.displayName
        Task { @MainActor in self.handleFoundPeer(name, box.value) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let name = peerID.displayName
        Task { @MainActor in self.handleLostPeer(name) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in self.isOnline = false }
    }
}
