import Testing
@testable import DayPilot

@Suite("PairingResolver — collision resolution")
struct PairingResolverTests {
    @Test func trustedPeerAutoAccepts() {
        #expect(PairingResolver.decide(from: "B", localName: "A", trusted: true, hasOutgoingInvite: false) == .autoAccept)
    }

    @Test func unknownPeerPromptsTheUser() {
        #expect(PairingResolver.decide(from: "B", localName: "A", trusted: false, hasOutgoingInvite: false) == .prompt)
    }

    @Test func simultaneousInviteLowerNameKeepsOwn() {
        // We invited them and they invited us at the same time. We sort lower
        // ("A" < "B"), so our invite wins — reject theirs to avoid a 2nd channel.
        #expect(PairingResolver.decide(from: "B", localName: "A", trusted: false, hasOutgoingInvite: true) == .rejectIncoming)
    }

    @Test func simultaneousInviteHigherNameYields() {
        // We sort higher ("B" > "A"), so we drop our invite and accept theirs.
        #expect(PairingResolver.decide(from: "A", localName: "B", trusted: false, hasOutgoingInvite: true) == .acceptIncoming)
    }

    @Test func trustedReconnectAutoAcceptsWhenOnlyTheyInvited() {
        // Classic silent reconnect: they invited, we didn't → just accept.
        #expect(PairingResolver.decide(from: "B", localName: "A", trusted: true, hasOutgoingInvite: false) == .autoAccept)
    }

    @Test func trustedSimultaneousInviteStillResolvesByTiebreak() {
        // On reconnect BOTH trusted peers auto-invite, so trust must not short-
        // circuit to autoAccept — that double-accepts and collides. The tiebreak
        // wins: lower name keeps its invite, higher accepts theirs.
        #expect(PairingResolver.decide(from: "B", localName: "A", trusted: true, hasOutgoingInvite: true) == .rejectIncoming)
        #expect(PairingResolver.decide(from: "A", localName: "B", trusted: true, hasOutgoingInvite: true) == .acceptIncoming)
    }
}
