#if canImport(MultipeerConnectivity)
import Foundation
import MultipeerConnectivity

protocol AppleMultipeerConnectivityAdapterDelegate: AnyObject {
    func appleAdapter(_ adapter: AppleMultipeerConnectivityAdapter, didChange state: MultiplayerTransportState)
    func appleAdapter(_ adapter: AppleMultipeerConnectivityAdapter, didChangePeer peerID: String, state: MultiplayerPeerState)
    func appleAdapter(_ adapter: AppleMultipeerConnectivityAdapter, didReceive data: Data, from peerID: String)
}

protocol AppleMultipeerConnectivityAdapter: AnyObject {
    var delegate: AppleMultipeerConnectivityAdapterDelegate? { get set }
    var localPeerID: String { get }
    var sessionStartedAt: TimeInterval { get }
    var state: MultiplayerTransportState { get }
    var connectedPeerIDs: Set<String> { get }

    func connect()
    func disconnect()
    func send(_ data: Data, to peerID: String, delivery: MultiplayerDeliveryPolicy) throws
    func broadcast(_ data: Data, delivery: MultiplayerDeliveryPolicy) throws
}

final class DefaultAppleMultipeerConnectivityAdapter: NSObject, AppleMultipeerConnectivityAdapter {
    weak var delegate: AppleMultipeerConnectivityAdapterDelegate?
    let localPeerID: String
    let sessionStartedAt: TimeInterval
    private(set) var state: MultiplayerTransportState = .idle
    var connectedPeerIDs: Set<String> {
        Set(session?.connectedPeers.map(\.displayName) ?? [])
    }

    private let peerID: MCPeerID
    private let serviceType = "wasteland-surv"
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var isDisconnecting = false

    init(playerName: String = "Wasteland Player") {
        localPeerID = UUID().uuidString
        sessionStartedAt = Date().timeIntervalSince1970
        peerID = MCPeerID(displayName: localPeerID)
        super.init()
    }

    func connect() {
        isDisconnecting = false
        state = .connecting
        delegate?.appleAdapter(self, didChange: state)

        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["game": "wasteland-survivors"],
            serviceType: serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    private func markFailed() {
        guard !isDisconnecting else { return }
        state = .failed
        delegate?.appleAdapter(self, didChange: state)
    }

    func disconnect() {
        isDisconnecting = true
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        state = .disconnected
        delegate?.appleAdapter(self, didChange: state)
    }

    func send(_ data: Data, to peerID: String, delivery: MultiplayerDeliveryPolicy) throws {
        guard state == .connected else { throw MultiplayerTransportError.notConnected }
        guard let session,
              let peer = session.connectedPeers.first(where: { $0.displayName == peerID }) else {
            throw MultiplayerTransportError.peerUnavailable
        }
        try session.send(data, toPeers: [peer], with: delivery == .reliable ? .reliable : .unreliable)
    }

    func broadcast(_ data: Data, delivery: MultiplayerDeliveryPolicy) throws {
        guard state == .connected else { throw MultiplayerTransportError.notConnected }
        guard let session, !session.connectedPeers.isEmpty else { throw MultiplayerTransportError.peerUnavailable }
        try session.send(data, toPeers: session.connectedPeers, with: delivery == .reliable ? .reliable : .unreliable)
    }
}

extension DefaultAppleMultipeerConnectivityAdapter: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        markFailed()
    }
}

extension DefaultAppleMultipeerConnectivityAdapter: MCNearbyServiceBrowserDelegate {
    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard peerID != self.peerID, let session else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        markFailed()
    }
}

extension DefaultAppleMultipeerConnectivityAdapter: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard self.session === session else { return }
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.session(session, peer: peerID, didChange: state)
            }
            return
        }
        guard !isDisconnecting else { return }

        switch state {
        case .connected:
            self.state = .connected
            delegate?.appleAdapter(self, didChangePeer: peerID.displayName, state: .connected)
        case .connecting:
            self.state = .connecting
        case .notConnected:
            self.state = session.connectedPeers.isEmpty ? .connecting : .connected
            delegate?.appleAdapter(self, didChangePeer: peerID.displayName, state: .disconnected)
        @unknown default:
            self.state = .failed
        }
        delegate?.appleAdapter(self, didChange: self.state)
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard self.session === session else { return }
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.session(session, didReceive: data, fromPeer: peerID)
            }
            return
        }
        guard !isDisconnecting else { return }
        delegate?.appleAdapter(self, didReceive: data, from: peerID.displayName)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
#endif
