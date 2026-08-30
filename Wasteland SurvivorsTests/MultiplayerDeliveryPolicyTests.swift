import CoreGraphics
import Testing
@testable import Wasteland_Survivors

@Suite("Multiplayer Delivery Policy")
struct MultiplayerDeliveryPolicyTests {
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
