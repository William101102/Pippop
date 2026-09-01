import Foundation
import MultipeerConnectivity
import NearbyInteraction
import simd

/// "Bump to meet" — the interaction that genuinely cannot be built in a
/// WebView, and the main reason this app is worth writing natively.
///
/// ## How it works
/// `NearbyInteraction` needs each side to hold the *other* side's
/// `NIDiscoveryToken`, and Apple provides no transport for that exchange. The
/// standard pattern is to pair over `MultipeerConnectivity` first, swap tokens,
/// then hand them to `NISession`. We piggyback the user's id and display name
/// on the same handshake so the meeting can be attributed to a real friend
/// rather than a device name.
///
/// ## Deliberately a two-sided ritual
/// Both people must have this screen open. There is no background scanning and
/// no passive proximity broadcast — that would mean a always-on Bluetooth
/// advertisement, materially worse battery, and a much heavier privacy review.
/// The mutual, foreground confirmation is what makes a bump trustworthy enough
/// to count toward a streak.
///
/// ## Requirements
/// - iPhone 11 or newer (U1). Older devices report no capability; callers
///   should fall back to the plain "wave" path rather than show a dead UI.
/// - `NSNearbyInteractionUsageDescription`, `NSLocalNetworkUsageDescription`
///   and an `NSBonjourServices` entry — all set in project.yml.
@MainActor
@Observable
final class BumpService: NSObject {
    enum Phase: Equatable {
        case unsupported
        case idle
        case searching
        /// Connected and measuring. Distance in metres; direction when available.
        case tracking(peerName: String, distance: Float?, direction: simd_float3?)
        case bumped(peerName: String)
        case failed(String)
    }

    struct Met: Equatable {
        let userId: UUID?
        let name: String
    }

    private(set) var phase: Phase = .idle

    /// Sent to the peer so a bump can be attributed to an account.
    private struct Handshake: Codable {
        let userId: UUID
        let displayName: String
        let token: Data
    }

    /// Closer than this for `bumpDwell` seconds and we call it a meeting.
    private let bumpDistance: Float = 0.12
    private let bumpDwell: TimeInterval = 0.35
    private var withinRangeSince: Date?

    private var niSession: NISession?
    private var mcSession: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var peerToken: NIDiscoveryToken?
    private var peerUserId: UUID?
    private var peerName: String?

    private var me: (id: UUID, name: String)?
    private var onBump: ((Met) -> Void)?
    private let activity = BumpActivityController()

    private static let serviceType = "pinpop-bump" // ≤15 chars, a–z 0–9 and -

    static var isSupported: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - userId/displayName: this user's identity, exchanged with the peer.
    ///     `UIDevice.current.name` is deliberately not used — on iOS 16+ it
    ///     returns a generic "iPhone" without a special entitlement, and it is
    ///     the wrong identity anyway.
    func start(userId: UUID, displayName: String, onBump: @escaping (Met) -> Void) {
        guard Self.isSupported else {
            phase = .unsupported
            return
        }
        me = (userId, displayName)
        self.onBump = onBump

        let session = NISession()
        session.delegate = self
        niSession = session

        let peerID = MCPeerID(displayName: String(displayName.prefix(60)))
        let mc = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        mc.delegate = self
        mcSession = mc

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        phase = .searching
        activity.start(friendName: "Someone nearby")
    }

    func stop() {
        let met: Bool = if case .bumped = phase { true } else { false }
        activity.finish(met: met)

        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        mcSession?.disconnect()
        niSession?.invalidate()

        advertiser = nil
        browser = nil
        mcSession = nil
        niSession = nil
        peerToken = nil
        peerUserId = nil
        peerName = nil
        withinRangeSince = nil
        onBump = nil
        me = nil
        phase = .idle
    }

    // MARK: - Handshake

    private func sendHandshake(to peer: MCPeerID) {
        guard
            let me,
            let token = niSession?.discoveryToken,
            let tokenData = try? NSKeyedArchiver.archivedData(
                withRootObject: token, requiringSecureCoding: true
            ),
            let payload = try? JSONEncoder().encode(
                Handshake(userId: me.id, displayName: me.name, token: tokenData)
            )
        else { return }
        try? mcSession?.send(payload, toPeers: [peer], with: .reliable)
    }

    private func receive(_ handshake: Handshake) {
        guard let token = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: NIDiscoveryToken.self, from: handshake.token
        ) else { return }

        peerUserId = handshake.userId
        peerName = handshake.displayName
        peerToken = token
        startRanging(with: token)
    }

    private func startRanging(with token: NIDiscoveryToken) {
        niSession?.run(NINearbyPeerConfiguration(peerToken: token))
    }

    // MARK: - Measurement

    private func evaluate(_ object: NINearbyObject) {
        let name = peerName ?? "Friend"
        phase = .tracking(peerName: name, distance: object.distance, direction: object.direction)

        activity.update(
            phase: .tracking,
            distance: object.distance.map(Double.init),
            bearing: object.direction.map { Double(atan2($0.x, -$0.z)) }
        )

        guard let distance = object.distance, distance <= bumpDistance else {
            withinRangeSince = nil
            return
        }
        // Require a short dwell so one noisy sample can't fake a meeting.
        guard let since = withinRangeSince else {
            withinRangeSince = Date()
            return
        }
        guard Date().timeIntervalSince(since) >= bumpDwell else { return }

        withinRangeSince = nil
        phase = .bumped(peerName: name)
        activity.update(phase: .met, distance: 0, bearing: nil)
        Haptics.shared.play(.bump)
        onBump?(Met(userId: peerUserId, name: name))
    }
}

// MARK: - NISessionDelegate

extension BumpService: NISessionDelegate {
    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else { return }
        Task { @MainActor in self.evaluate(object) }
    }

    nonisolated func session(
        _ session: NISession,
        didRemove nearbyObjects: [NINearbyObject],
        reason: NINearbyObject.RemovalReason
    ) {
        Task { @MainActor in
            self.withinRangeSince = nil
            if case .bumped = self.phase { return }
            self.phase = .searching
            self.activity.update(phase: .searching, distance: nil, bearing: nil)
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in self.phase = .failed(error.localizedDescription) }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor in
            if case .bumped = self.phase { return }
            self.phase = .searching
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        // Re-running the configuration resumes measurement after a suspension.
        Task { @MainActor in
            if let token = self.peerToken { self.startRanging(with: token) }
        }
    }
}

// MARK: - MultipeerConnectivity

extension BumpService: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated func session(
        _ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState
    ) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.sendHandshake(to: peerID)
            case .notConnected:
                if case .bumped = self.phase { return }
                self.phase = .searching
            default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let handshake = try? JSONDecoder().decode(Handshake.self, from: data) else { return }
        Task { @MainActor in self.receive(handshake) }
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Task { @MainActor in invitationHandler(true, self.mcSession) }
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor in
            guard let mcSession = self.mcSession else { return }
            browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 15)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    // Unused MCSessionDelegate requirements.
    nonisolated func session(_ s: MCSession, didReceive stream: InputStream, withName n: String, fromPeer p: MCPeerID) {}
    nonisolated func session(_ s: MCSession, didStartReceivingResourceWithName n: String, fromPeer p: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ s: MCSession, didFinishReceivingResourceWithName n: String, fromPeer p: MCPeerID, at url: URL?, withError e: Error?) {}
}
