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
        )).deliveryPolicy == .replaceable)
        #expect(MultiplayerWireMessage.boardSnapshot(.empty(hostID: "h", sequence: 1)).deliveryPolicy == .replaceable)
    }

    @Test("Snapshot sampling uses the sequence-ordered history")
    func snapshotSamplingUsesSequenceOrderedHistory() {
        var buffer = MultiplayerSnapshotBuffer()
        for sequence in 1...3 {
            let appended = buffer.append(MultiplayerBoardState(
                sequence: UInt64(sequence),
                simulationTick: UInt64(sequence),
                hostID: "host",
                players: [MultiplayerPlayerState(
                    id: "player",
                    position: CGPoint(x: sequence, y: 0),
                    color: .blue
                )],
                zombies: [],
                chests: [],
                powerUps: [],
                projectiles: [],
                killCount: 0
            ))
            #expect(appended)
        }

        #expect(buffer.position(
            for: "player",
            renderTick: 3,
            delayTicks: 0,
            maxExtrapolationTicks: 0
        ) == CGPoint(x: 3, y: 0))
    }

    @Test("Authoritative snapshots use a 30 Hz host cadence")
    func authoritativeSnapshotsUseThirtyHertzCadence() {
        #expect(MultiplayerSnapshotTiming.hostSnapshotInterval == 1.0 / 30.0)
    }

    @Test("Interpolation delay spans two authoritative snapshots")
    func interpolationDelaySpansTwoAuthoritativeSnapshots() {
        #expect(
            MultiplayerSnapshotTiming.interpolationDelayTicks(
                snapshotIntervalTicks: 6
            ) == 12
        )
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
