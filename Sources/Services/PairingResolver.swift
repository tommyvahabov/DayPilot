/// What to do with an incoming pairing invitation. Keeps the
/// MultipeerConnectivity collision logic pure and testable, out of PeerManager.
enum PairingDecision: Equatable {
    case autoAccept      // already-trusted peer → silent accept
    case acceptIncoming  // simultaneous invite, we yield → take theirs
    case rejectIncoming  // simultaneous invite, ours wins → decline theirs
    case prompt          // unknown peer → ask the user
}

enum PairingResolver {
    /// Resolve an incoming invitation. The key case is *simultaneous* invites
    /// (both Macs tapped "Pair"): if both sides also accept, MultipeerConnectivity
    /// gets two concurrent connection attempts between the same pair and never
    /// reaches `.connected`. We break the tie deterministically by display name —
    /// the lower name keeps its own outgoing invite and rejects the incoming one,
    /// the higher name drops its invite and accepts — so exactly one channel forms.
    static func decide(from peer: String, localName: String, trusted: Bool, hasOutgoingInvite: Bool) -> PairingDecision {
        // Tiebreak first: if we also invited them (both sides auto-invite on
        // reconnect), only one connection may form — even for trusted peers,
        // where blindly accepting would collide.
        if hasOutgoingInvite {
            return localName < peer ? .rejectIncoming : .acceptIncoming
        }
        if trusted { return .autoAccept }
        return .prompt
    }
}
