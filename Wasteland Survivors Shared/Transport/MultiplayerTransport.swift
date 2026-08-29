import Foundation

enum MultiplayerTransportState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case disconnected
    case failed
}

enum MultiplayerPeerState: Equatable, Sendable {
    case connected
    case disconnected
}

protocol MultiplayerTransportDelegate: AnyObject {
    func transport(_ transport: MultiplayerTransport, didChange state: MultiplayerTransportState)
    func transport(_ transport: MultiplayerTransport, didChangePeer peerID: String, state: MultiplayerPeerState)
    func transport(_ transport: MultiplayerTransport, didReceive data: Data, from peerID: String)
}

extension MultiplayerTransportDelegate {
    func transport(_ transport: MultiplayerTransport, didChangePeer peerID: String, state: MultiplayerPeerState) {}
}

protocol MultiplayerTransport: AnyObject {
    var localPeerID: String { get }
    var delegate: MultiplayerTransportDelegate? { get set }
    var state: MultiplayerTransportState { get }
    var connectedPeerIDs: Set<String> { get }
    func connect()
    func disconnect()
    func send(_ data: Data, to peerID: String) throws
    func broadcast(_ data: Data) throws
    func send(_ data: Data, to peerID: String, delivery: MultiplayerDeliveryPolicy) throws
    func broadcast(_ data: Data, delivery: MultiplayerDeliveryPolicy) throws
}

extension MultiplayerTransport {
    func send(_ data: Data, to peerID: String, delivery: MultiplayerDeliveryPolicy) throws {
        try send(data, to: peerID)
    }

    func broadcast(_ data: Data, delivery: MultiplayerDeliveryPolicy) throws {
        try broadcast(data)
    }
}

enum MultiplayerTransportError: Error, Equatable, Sendable {
    case notConnected
    case peerUnavailable
}

enum MultiplayerDeliveryPolicy: Equatable, Sendable {
    case replaceable
    case reliable
}

final class OfflineTransport: MultiplayerTransport {
    let localPeerID: String
    weak var delegate: MultiplayerTransportDelegate?
    private(set) var state: MultiplayerTransportState = .idle
    private(set) var connectedPeerIDs: Set<String> = []

    init(localPeerID: String) {
        self.localPeerID = localPeerID
    }

    func connect() {
        state = .connected
        connectedPeerIDs = [localPeerID]
        delegate?.transport(self, didChange: state)
    }

    func disconnect() {
        state = .disconnected
        connectedPeerIDs.removeAll()
        delegate?.transport(self, didChange: state)
    }

    func send(_ data: Data, to peerID: String) throws {
        guard state == .connected else { throw MultiplayerTransportError.notConnected }
        guard peerID == localPeerID else { throw MultiplayerTransportError.peerUnavailable }
        delegate?.transport(self, didReceive: data, from: localPeerID)
    }

    func broadcast(_ data: Data) throws {
        try send(data, to: localPeerID)
    }
}
