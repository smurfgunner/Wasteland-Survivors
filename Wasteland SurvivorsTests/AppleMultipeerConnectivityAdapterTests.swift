#if canImport(MultipeerConnectivity)
import Foundation
import Testing
@testable import Wasteland_Survivors

@Suite("Apple Multipeer Connectivity Adapter")
struct AppleMultipeerConnectivityAdapterTests {
    @Test("Session forwards injectable adapter lifecycle and callbacks")
    func sessionForwardsAdapterLifecycleAndCallbacks() throws {
        let adapter = FakeAppleAdapter()
        let session = MultipeerConnectivitySession(adapter: adapter)
        let delegate = TransportDelegateSpy()
        var diagnostics: [String] = []
        session.delegate = delegate
        session.diagnosticHandler = { diagnostics.append($0) }

        session.connect()
        #expect(adapter.connectCallCount == 1)
        #expect(delegate.states == [.connecting, .connected])
        #expect(diagnostics.contains("connecting localPeerID=local"))
        #expect(diagnostics.contains("state=connected"))

        try session.send(Data("direct".utf8), to: "remote", delivery: .reliable)
        try session.broadcast(Data("broadcast".utf8), delivery: .replaceable)
        #expect(diagnostics.contains("sending bytes=6 to=remote delivery=reliable"))
        #expect(diagnostics.contains("broadcasting bytes=9 delivery=replaceable"))
        #expect(adapter.sent.count == 2)
        #expect(adapter.sent[0].0 == Data("direct".utf8))
        #expect(adapter.sent[0].1 == "remote")
        #expect(adapter.sent[0].2 == .reliable)
        #expect(adapter.sent[1].0 == Data("broadcast".utf8))
        #expect(adapter.sent[1].1 == nil)
        #expect(adapter.sent[1].2 == .replaceable)

        adapter.emitState(.failed)
        #expect(delegate.states.last == .failed)

        adapter.emitPeer("remote", state: .connected)
        adapter.emit(Data("hello".utf8), from: "remote")
        #expect(delegate.peerChanges.count == 1)
        #expect(delegate.peerChanges.first?.0 == "remote")
        #expect(delegate.peerChanges.first?.1 == .connected)
        #expect(delegate.received.count == 1)
        #expect(delegate.received.first?.0 == Data("hello".utf8))
        #expect(delegate.received.first?.1 == "remote")


        session.disconnect()
        #expect(adapter.disconnectCallCount == 1)
        #expect(delegate.states.last == .disconnected)
    }

    @Test("Session preserves adapter transport errors")
    func sessionPreservesAdapterTransportErrors() {
        let adapter = FakeAppleAdapter()
        adapter.error = MultiplayerTransportError.peerUnavailable
        let session = MultipeerConnectivitySession(adapter: adapter)

        #expect(throws: MultiplayerTransportError.peerUnavailable) {
            try session.send(Data(), to: "remote", delivery: .reliable)
        }
    }
}

#if canImport(MultipeerConnectivity)
private final class FakeAppleAdapter: AppleMultipeerConnectivityAdapter {
    weak var delegate: AppleMultipeerConnectivityAdapterDelegate?
    let localPeerID = "local"
    let sessionStartedAt: TimeInterval = 10
    private(set) var state: MultiplayerTransportState = .idle
    var connectedPeerIDs: Set<String> = ["remote"]
    var connectCallCount = 0
    var disconnectCallCount = 0
    var sent: [(Data, String?, MultiplayerDeliveryPolicy)] = []
    var error: Error?

    func connect() {
        connectCallCount += 1
        state = .connecting
        delegate?.appleAdapter(self, didChange: state)
        state = .connected
        delegate?.appleAdapter(self, didChange: state)
    }

    func disconnect() {
        disconnectCallCount += 1
        state = .disconnected
        delegate?.appleAdapter(self, didChange: state)
    }

    func send(_ data: Data, to peerID: String, delivery: MultiplayerDeliveryPolicy) throws {
        if let error { throw error }
        sent.append((data, peerID, delivery))
    }

    func broadcast(_ data: Data, delivery: MultiplayerDeliveryPolicy) throws {
        if let error { throw error }
        sent.append((data, nil, delivery))
    }

    func emitState(_ newState: MultiplayerTransportState) {
        state = newState
        delegate?.appleAdapter(self, didChange: newState)
    }

    func emitPeer(_ peerID: String, state: MultiplayerPeerState) {
        delegate?.appleAdapter(self, didChangePeer: peerID, state: state)
    }

    func emit(_ data: Data, from peerID: String) {
        delegate?.appleAdapter(self, didReceive: data, from: peerID)
    }
}

private final class TransportDelegateSpy: MultiplayerTransportDelegate {
    var states: [MultiplayerTransportState] = []
    var peerChanges: [(String, MultiplayerPeerState)] = []
    var received: [(Data, String)] = []

    func transport(_ transport: MultiplayerTransport, didChange state: MultiplayerTransportState) {
        states.append(state)
    }

    func transport(_ transport: MultiplayerTransport, didChangePeer peerID: String, state: MultiplayerPeerState) {
        peerChanges.append((peerID, state))
    }

    func transport(_ transport: MultiplayerTransport, didReceive data: Data, from peerID: String) {
        received.append((data, peerID))
    }
}
#endif
#endif
