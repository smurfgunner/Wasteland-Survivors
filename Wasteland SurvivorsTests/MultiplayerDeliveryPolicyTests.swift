import CoreGraphics
import Testing
@testable import Wasteland_Survivors

@Suite("Multiplayer Delivery Policy")
struct MultiplayerDeliveryPolicyTests {
    @Test("High-frequency state messages are replaceable")
    func highFrequencyMessagesAreReplaceable() {
        #expect(MultiplayerWireMessage.playerUpdate(.init(id: "p", position: .zero, color: .blue)).deliveryPolicy == .replaceable)
        #expect(MultiplayerWireMessage.playerInput(.init(
            playerID: "p",
            sequence: 1,
            movement: .zero,
            aimAngle: 0,
            wantsToAttack: false
        )).deliveryPolicy == .reliable)
        #expect(MultiplayerWireMessage.boardSnapshot(.empty(hostID: "h", sequence: 1)).deliveryPolicy == .replaceable)
    }

    @Test("Session lifecycle messages are reliable")
    func lifecycleMessagesAreReliable() {
        let hello = MultiplayerHello(sessionID: "session", peerID: "peer", startedAt: 1, protocolVersion: 1)
        let announcement = MultiplayerHostAnnouncement(sessionID: "session", hostID: "host", hostStartedAt: 1, protocolVersion: 1)
        let request = MultiplayerJoinRequest(sessionID: "session", peerID: "peer", protocolVersion: 1)
        let accepted = MultiplayerJoinAccepted(sessionID: "session", peerID: "peer", hostID: "host", protocolVersion: 1)

        #expect(MultiplayerWireMessage.hello(hello).deliveryPolicy == .reliable)
        #expect(MultiplayerWireMessage.hostAnnouncement(announcement).deliveryPolicy == .reliable)
        #expect(MultiplayerWireMessage.joinRequest(request).deliveryPolicy == .reliable)
        #expect(MultiplayerWireMessage.joinAccepted(accepted).deliveryPolicy == .reliable)
    }
}
