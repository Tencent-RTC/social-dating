import UIKit
import AtomicXCore
import AtomicX
import TUIChatKit
import TUICallKit
import TUIHomeKit
import TUIHostBase
import Foundation

// MARK: - Fixture: chat.json

/// Chat chrome copy and quick-interaction chips from design/fixtures/chat.json.
struct DemoChatCopy: Decodable {
    struct Chip: Decodable {
        let id: String
        let label: String
        let icon: String
        let kind: String
        let summary: String
        let payload: [String: DemoJSONValue]
    }

    /// One E4 more-panel tile. `action` is "card" (send chat.card) or "notice".
    struct MoreItem: Decodable {
        let id: String
        let label: String
        let tile: String
        let badge: String?
        let action: String
        let kind: String?
        let summary: String?
        let notice: String?
        let payload: [String: DemoJSONValue]?
    }

    /// Host content of the 1:1 chat settings page (S6); the IM SDK owns none of it.
    struct ChatSetting: Decodable {
        let title: String
        let profileTags: [String]
        let intimacyLabel: String
        let intimacyBadge: String
        let backgroundLabel: String
        let nicknameLabel: String
        let nicknameValue: String
        let reportLabel: String
        let footer: String
        let mockNotice: String
    }

    struct InputBar: Decodable {
        let placeholder: String
        let sendText: String
    }

    struct QuickAction: Decodable {
        let id: String
        let label: String
        let icon: String
        let iconOn: String?
        let primary: Bool?
        let dot: Bool?
        let action: String
        let kind: String?
        let summary: String?
        let payload: [String: DemoJSONValue]?
    }

    /// Local gift catalogue; `value` is display text, never a price.
    struct Gift: Decodable {
        let ref: String
        let name: String
        let value: Int
        let unit: String
        let icon: String
    }

    struct GiftPanelCopy: Decodable {
        let title: String
        let sendText: String
        let comboWindowMs: Int64
        let gifts: [Gift]
    }

    let safetyBanner: String
    let defaultSubtitle: String
    let quickChips: [Chip]
    let morePanel: [MoreItem]?
    let inputBar: InputBar?
    let quickActions: [QuickAction]?
    let chatSetting: ChatSetting?
    let giftPanel: GiftPanelCopy?

    static func load() -> DemoChatCopy {
        DemoFixtures.load(DemoChatCopy.self, "chat")
            ?? DemoChatCopy(safetyBanner: "", defaultSubtitle: DemoText.get("demo_1v1_chat"), quickChips: [], morePanel: nil,
                            inputBar: nil, quickActions: nil, chatSetting: nil, giftPanel: nil)
    }
}

/// Flat JSON scalar used by fixture payloads (nested values are intentionally unsupported).
enum DemoJSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        self = .string(try container.decode(String.self))
    }

    var any: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value ? Int64(value) : value
        case .bool(let value): return value
        }
    }
}

// MARK: - Protocol: chat.card

/// Demo interaction card protocol (spec 03 §3), identical to Android
/// `DemoCardProtocol`. Content is fake; the CUSTOM message carrying it is real IM.
/// `call` is never an allowed kind, so the SDK call message format is untouched.
enum DemoCardProtocol {
    static let businessID = "chat1v1.card"
    static let version = 1
    static let dataSource = "demo_mock"
    static let allowedKinds: Set<String> = ["pat", "listen", "photoSwap", "location", "burn", "dice", "rps", "quiz", "gift", "redpacket"]
    static let maxBytes = 4096

    struct Card {
        let kind: String
        let version: Int
        let instanceId: String
        let eventId: String
        let actorSequence: Int
        let payload: [String: String]
        var isKnownKind: Bool { DemoCardProtocol.allowedKinds.contains(kind) }
    }

    static func build(kind: String, payload: [String: Any], instanceId: String = UUID().uuidString,
                      eventId: String = UUID().uuidString, actorSequence: Int = 1) -> String? {
        guard allowedKinds.contains(kind) else { return nil }
        let json: [String: Any] = [
            "businessID": businessID, "version": version, "kind": kind, "dataSource": dataSource,
            "instanceId": instanceId, "eventId": eventId, "actorSequence": actorSequence, "payload": payload
        ]
        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
              data.count <= maxBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Control events (`businessID = chat.event`). Only declared kind/action pairs exist and
    /// `call` is not among them. Sending is deliberately NOT wired: whether online-only custom
    /// messages stay out of unread counts, summaries and push is unverified on the locked SDK
    /// (spec 03 §4.5/§4.6), so choices stay local-only demos until that is measured.
    static let eventBusinessID = "chat1v1.event"
    static let eventActions: [String: Set<String>] = ["quiz": ["select"]]

    static func buildEvent(kind: String, targetInstanceId: String, action: String, params: [String: Any],
                           eventId: String = UUID().uuidString, actorSequence: Int = 1) -> String? {
        guard eventActions[kind]?.contains(action) == true, !targetInstanceId.isEmpty else { return nil }
        var payload = params
        payload["action"] = action
        let json: [String: Any] = [
            "businessID": eventBusinessID, "version": version, "kind": kind, "dataSource": dataSource,
            "targetInstanceId": targetInstanceId, "eventId": eventId, "actorSequence": actorSequence,
            "payload": payload
        ]
        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
              data.count <= maxBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// `senderId` must be the real SDK sender of the message, never anything from the payload.
    static func parseEvent(_ customData: String?, senderId: String) -> DemoInteractionState.Event? {
        guard let customData, let data = customData.data(using: .utf8), data.count <= maxBytes,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["businessID"] as? String == eventBusinessID,
              json["dataSource"] as? String == dataSource,
              let version = json["version"] as? Int, version > 0,
              let target = json["targetInstanceId"] as? String, !target.isEmpty,
              let rawPayload = json["payload"] as? [String: Any],
              let kind = json["kind"] as? String else { return nil }
        var params: [String: String] = [:]
        for (key, value) in rawPayload {
            switch value {
            case let text as String: params[key] = text
            case let number as NSNumber: params[key] = number.stringValue
            default: continue
            }
        }
        guard let action = params["action"], eventActions[kind]?.contains(action) == true else { return nil }
        params["action"] = nil
        return DemoInteractionState.Event(
            targetInstanceId: target, eventId: json["eventId"] as? String ?? "", senderId: senderId,
            actorSequence: json["actorSequence"] as? Int ?? 0, kind: kind, action: action, params: params)
    }

    static func parse(_ customData: String?) -> Card? {
        guard let customData, let data = customData.data(using: .utf8), data.count <= maxBytes,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["businessID"] as? String == businessID,
              json["dataSource"] as? String == dataSource,
              let version = json["version"] as? Int, version > 0 else { return nil }
        var flat: [String: String] = [:]
        for (key, value) in json["payload"] as? [String: Any] ?? [:] {
            switch value {
            case let text as String: flat[key] = text
            case let number as NSNumber: flat[key] = number.stringValue
            default: continue // nested values dropped (depth limit)
            }
        }
        return Card(kind: json["kind"] as? String ?? "", version: version,
                    instanceId: json["instanceId"] as? String ?? "", eventId: json["eventId"] as? String ?? "",
                    actorSequence: json["actorSequence"] as? Int ?? 0, payload: flat)
    }

    static func summary(_ card: Card?) -> String {
        guard let card else { return DemoText.get("demo_message") }
        return summaryOf(kind: card.kind)
    }

    static func summaryOf(kind: String) -> String {
        switch kind {
        case "pat": return DemoText.get("demo_pat")
        case "listen": return DemoText.get("demo_listen_together_2")
        case "photoSwap": return DemoText.get("demo_photo_swap")
        case "location": return DemoText.get("demo_location")
        case "burn": return DemoText.get("demo_burn_after_reading")
        case "dice": return DemoText.get("demo_dice")
        case "rps": return DemoText.get("demo_rock_paper_scissors")
        case "quiz": return DemoText.get("demo_crush_quiz")
        case "gift": return DemoText.get("demo_gift")
        case "redpacket": return DemoText.get("demo_red_packet")
        default: return DemoText.get("demo_interaction_card")
        }
    }
}

/// Content of the rock-paper-scissors card, identical to Android `DemoRps`. The sender rolls the
/// hand and a sample outcome once and carries both in the payload (like the dice value), so neither end
/// re-rolls. The outcome is local sample text, not a rules engine: the receiver has not thrown yet, so only
/// the sender's card words it and the receiver is invited to play again.
enum DemoRps {
    static let hands = ["rock", "scissors", "paper"]
    static let outcomes = ["win", "draw", "lose"]

    static func roll<G: RandomNumberGenerator>(using generator: inout G) -> [String: Any] {
        [
            "hand": hands[Int.random(in: 0..<hands.count, using: &generator)],
            "outcome": outcomes[Int.random(in: 0..<outcomes.count, using: &generator)]
        ]
    }

    static func handLabel(_ hand: String?) -> String {
        switch hand {
        case "scissors": return DemoText.get("demo_scissors")
        case "paper": return DemoText.get("demo_paper")
        default: return DemoText.get("demo_rock")
        }
    }

    static func handImageName(_ hand: String?) -> String {
        switch hand {
        case "scissors": return "demo_rps_scissors"
        case "paper": return "demo_rps_paper"
        default: return "demo_rps_rock"
        }
    }
}

/// Values the sender decides once at send time. Receivers render what the payload carries and
/// never roll again, so both ends show one result (spec 03 section 6).
enum DemoCardRolls {
    static func rolled<G: RandomNumberGenerator>(kind: String, payload: [String: Any], using generator: inout G) -> [String: Any] {
        var payload = payload
        switch kind {
        case "dice": payload["value"] = Int.random(in: 1...6, using: &generator)
        case "rps": DemoRps.roll(using: &generator).forEach { payload[$0.key] = $0.value }
        default: break
        }
        return payload
    }

    static func rolled(kind: String, payload: [String: Any]) -> [String: Any] {
        var generator = SystemRandomNumberGenerator()
        return rolled(kind: kind, payload: payload, using: &generator)
    }
}

// MARK: - Interaction state and effect gate

/// Client-side interaction state for chat.card / chat.event (spec 03 §4),
/// identical to Android `DemoInteractionState`. Local, in-memory; no backend or revision.
/// - the same `eventId` is applied at most once;
/// - per (instance, SDK sender) `actorSequence` only moves forward, older ones never roll back;
/// - actions are declarative (`select optionId`), never "toggle on every receipt".
final class DemoInteractionState {
    enum Outcome { case applied, duplicate, stale, invalid }

    struct Event {
        let targetInstanceId: String
        let eventId: String
        /// The real SDK sender, never a name claimed inside the payload.
        let senderId: String
        let actorSequence: Int
        let kind: String
        let action: String
        let params: [String: String]
    }

    /// Actor for choices made on this device; real peer events must use the SDK sender id.
    static let localActor = "local"
    static let maxRememberedEvents = 512

    private var seenOrder: [String] = []
    private var seen = Set<String>()
    private var lastSequence: [String: Int] = [:]
    private var selections: [String: [String: String]] = [:]
    private let lock = NSLock()

    func apply(_ event: Event) -> Outcome {
        lock.lock(); defer { lock.unlock() }
        guard !event.targetInstanceId.isEmpty, !event.eventId.isEmpty, !event.senderId.isEmpty,
              DemoCardProtocol.eventActions[event.kind]?.contains(event.action) == true else { return .invalid }
        let optionId = event.params["optionId"]
        if event.action == "select", optionId?.isEmpty != false { return .invalid }
        if seen.contains(event.eventId) { return .duplicate }
        remember(event.eventId)
        let key = "\(event.targetInstanceId)|\(event.senderId)"
        if event.actorSequence <= (lastSequence[key] ?? 0) { return .stale }
        lastSequence[key] = event.actorSequence
        if event.action == "select", let optionId {
            selections[event.targetInstanceId, default: [:]][event.senderId] = optionId
        }
        return .applied
    }

    func selection(instanceId: String, senderId: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return selections[instanceId]?[senderId]
    }

    /// Next local sequence for `senderId` on `instanceId`; strictly greater than any applied one.
    func nextSequence(instanceId: String, senderId: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return (lastSequence["\(instanceId)|\(senderId)"] ?? 0) + 1
    }

    private func remember(_ eventId: String) {
        seen.insert(eventId)
        seenOrder.append(eventId)
        if seenOrder.count > Self.maxRememberedEvents { seen.remove(seenOrder.removeFirst()) }
    }
}

/// One state per conversation; demo state is lost on process exit.
enum DemoInteractionStore {
    private static var states: [String: DemoInteractionState] = [:]
    private static let lock = NSLock()

    static func state(for conversationKey: String) -> DemoInteractionState {
        lock.lock(); defer { lock.unlock() }
        if let existing = states[conversationKey] { return existing }
        let created = DemoInteractionState()
        states[conversationKey] = created
        return created
    }

    static func clear() {
        lock.lock(); defer { lock.unlock() }
        states.removeAll()
    }
}

/// Decides whether a card effect (pat wobble, dice roll, gift pulse) may play (spec 03 §4.4).
/// History paging and cell reuse re-bind old cards: only a fresh message whose `eventId` has
/// not played yet animates, once.
enum DemoEffectGate {
    /// Message age that still counts as "just arrived"; server clock skew beyond it suppresses the effect.
    static let realtimeWindowMs: Int64 = 10_000
    private static let maxRemembered = 256
    private static var played: [String] = []
    private static var playedSet = Set<String>()
    private static let lock = NSLock()

    static func shouldPlay(eventId: String, messageTimeMs: Int64,
                           nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !eventId.isEmpty, nowMs - messageTimeMs <= realtimeWindowMs,
              playedSet.insert(eventId).inserted else { return false }
        played.append(eventId)
        if played.count > maxRemembered { playedSet.remove(played.removeFirst()) }
        return true
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        played.removeAll()
        playedSet.removeAll()
    }
}

enum DemoCardLocalState {
    enum Burn { case sealed, viewing, expired }
    enum Swap { case invited, ready, revealed }

    struct BurnView { let state: Burn; let remainingMs: Int64 }
    struct ListenView { let joined: Bool; let playing: Bool; let positionMs: Int64 }

    static let defaultBurnSeconds = 5
    static let maxBurnSeconds = 30
    static let swapRevealDelayMs: Int64 = 500

    private final class Listen {
        var playing: Bool
        var offsetMs: Int64
        var startedAt: Int64
        init(playing: Bool, offsetMs: Int64, startedAt: Int64) {
            self.playing = playing; self.offsetMs = offsetMs; self.startedAt = startedAt
        }
    }

    private static var burnDeadlines: [String: Int64] = [:]
    private static var swaps: [String: Swap] = [:]
    private static var swapReadyAt: [String: Int64] = [:]
    private static var openedRedPackets = Set<String>()
    private static var listens: [String: Listen] = [:]
    private static let lock = NSLock()

    static func burnSeconds(_ raw: String?) -> Int {
        min(max(Int(raw ?? "") ?? defaultBurnSeconds, 1), maxBurnSeconds)
    }

    static func burn(instanceId: String, nowMs: Int64) -> BurnView {
        lock.lock(); defer { lock.unlock() }
        guard let deadline = burnDeadlines[instanceId] else { return BurnView(state: .sealed, remainingMs: 0) }
        let remaining = deadline - nowMs
        return remaining > 0 ? BurnView(state: .viewing, remainingMs: remaining) : BurnView(state: .expired, remainingMs: 0)
    }

    @discardableResult
    static func openBurn(instanceId: String, seconds: Int, nowMs: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !instanceId.isEmpty, burnDeadlines[instanceId] == nil else { return false }
        burnDeadlines[instanceId] = nowMs + Int64(min(max(seconds, 1), maxBurnSeconds)) * 1000
        return true
    }

    private static func swapLocked(_ instanceId: String, _ nowMs: Int64) -> Swap {
        let current = swaps[instanceId] ?? .invited
        if current == .ready, let readyAt = swapReadyAt[instanceId], nowMs - readyAt >= swapRevealDelayMs {
            swaps[instanceId] = .revealed
            return .revealed
        }
        return current
    }

    static func swap(instanceId: String, nowMs: Int64) -> Swap {
        lock.lock(); defer { lock.unlock() }
        return swapLocked(instanceId, nowMs)
    }

    static func swapRevealRemainingMs(instanceId: String, nowMs: Int64) -> Int64 {
        lock.lock(); defer { lock.unlock() }
        guard swapLocked(instanceId, nowMs) == .ready, let readyAt = swapReadyAt[instanceId] else { return 0 }
        return max(readyAt + swapRevealDelayMs - nowMs, 0)
    }

    @discardableResult
    static func pickSwap(instanceId: String, nowMs: Int64) -> Swap {
        lock.lock(); defer { lock.unlock() }
        guard !instanceId.isEmpty else { return .invited }
        let current = swapLocked(instanceId, nowMs)
        guard current == .invited else { return current }
        swaps[instanceId] = .ready
        swapReadyAt[instanceId] = nowMs
        return .ready
    }

    static func redPacketOpened(instanceId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return openedRedPackets.contains(instanceId)
    }

    @discardableResult
    static func openRedPacket(instanceId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !instanceId.isEmpty else { return false }
        return openedRedPackets.insert(instanceId).inserted
    }

    private static func listenLocked(_ instanceId: String, _ durationMs: Int64, _ nowMs: Int64) -> ListenView {
        guard let item = listens[instanceId] else { return ListenView(joined: false, playing: false, positionMs: 0) }
        let raw = item.offsetMs + (item.playing ? nowMs - item.startedAt : 0)
        let position = durationMs > 0 ? min(max(raw, 0), durationMs) : max(raw, 0)
        return ListenView(joined: true, playing: item.playing && (durationMs <= 0 || position < durationMs), positionMs: position)
    }

    static func listen(instanceId: String, durationMs: Int64, nowMs: Int64) -> ListenView {
        lock.lock(); defer { lock.unlock() }
        return listenLocked(instanceId, durationMs, nowMs)
    }

    @discardableResult
    static func toggleListen(instanceId: String, durationMs: Int64, nowMs: Int64) -> ListenView {
        lock.lock(); defer { lock.unlock() }
        guard !instanceId.isEmpty else { return ListenView(joined: false, playing: false, positionMs: 0) }
        let current = listenLocked(instanceId, durationMs, nowMs)
        if let item = listens[instanceId] {
            item.offsetMs = current.positionMs
            item.playing = !current.playing
            item.startedAt = nowMs
        } else {
            listens[instanceId] = Listen(playing: true, offsetMs: 0, startedAt: nowMs)
        }
        return listenLocked(instanceId, durationMs, nowMs)
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        burnDeadlines.removeAll(); swaps.removeAll(); swapReadyAt.removeAll(); openedRedPackets.removeAll(); listens.removeAll()
    }
}

/// Local gift combo counter (spec 03 §5). Only drives the "x N" pop in the gift panel; it is
/// not a ledger and never sent. Counted on a successful send, keyed by the card's instanceId so a
/// retried send of the same card cannot bump the combo twice.
enum DemoGiftCombo {
    static let defaultWindowMs: Int64 = 2600
    private static let maxRemembered = 64
    private static var lastRef: String?
    private static var lastAtMs: Int64 = 0
    private static var count = 0
    private static var counted: [String: Int] = [:]
    private static var order: [String] = []
    private static let lock = NSLock()

    static func register(instanceId: String, giftRef: String, nowMs: Int64, windowMs: Int64 = defaultWindowMs) -> Int {
        lock.lock(); defer { lock.unlock() }
        if !instanceId.isEmpty, let existing = counted[instanceId] { return existing }
        let delta = nowMs - lastAtMs
        count = (giftRef == lastRef && delta >= 0 && delta < windowMs) ? count + 1 : 1
        lastRef = giftRef
        lastAtMs = nowMs
        if !instanceId.isEmpty {
            counted[instanceId] = count
            order.append(instanceId)
            if order.count > maxRemembered { counted[order.removeFirst()] = nil }
        }
        return count
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        lastRef = nil; lastAtMs = 0; count = 0; counted.removeAll(); order.removeAll()
    }
}

/// Chat chrome that lives for one app session: dismissed safety tips and the seen-gift dot.
enum DemoChatSession {
    private static var dismissedBanners = Set<String>()
    private static var giftDot = false
    private static let lock = NSLock()

    static func isBannerDismissed(_ conversationID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return dismissedBanners.contains(conversationID)
    }

    static func dismissBanner(_ conversationID: String) {
        lock.lock(); defer { lock.unlock() }
        dismissedBanners.insert(conversationID)
    }

    static var giftDotSeen: Bool {
        lock.lock(); defer { lock.unlock() }
        return giftDot
    }

    static func markGiftDotSeen() {
        lock.lock(); defer { lock.unlock() }
        giftDot = true
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        dismissedBanners.removeAll()
        giftDot = false
    }
}

/// Tappable quiz option; carries its option id so the card can record the choice.
private final class DemoQuizOptionLabel: UILabel {
    var optionId = ""
}

// MARK: - Card content view

private func cardMix(_ from: UIColor, _ to: UIColor, _ fraction: CGFloat) -> UIColor {
    var a: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    var b: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    from.getRed(&a.0, green: &a.1, blue: &a.2, alpha: &a.3)
    to.getRed(&b.0, green: &b.1, blue: &b.2, alpha: &b.3)
    let t = max(0, min(1, fraction))
    return UIColor(red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t, alpha: a.3 + (b.3 - a.3) * t)
}

private func cardTint(_ accent: UIColor, _ strength: CGFloat = 0.2) -> [UIColor] {
    let surface = Host.tokens.bgColorDialog
    return [cardMix(surface, accent, strength), surface]
}

private func cardRing(_ accent: UIColor, _ alpha: CGFloat = 0.24) -> UIColor { accent.withAlphaComponent(alpha) }

private final class DemoTapView: UIView {
    var onTap: (() -> Void)?
    /// Brand-gradient fill of a primary button; sized here because the button is 0x0 when the card first lays out.
    var gradient: CAGradientLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() { onTap?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient?.frame = bounds
    }
}

private final class DemoProgressBar: UIView {
    private let fillView = UIView()
    var fraction: CGFloat = 0 { didSet { setNeedsLayout() } }

    init(track: UIColor, fill: UIColor) {
        super.init(frame: .zero)
        backgroundColor = track
        fillView.backgroundColor = fill
        addSubview(fillView)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        fillView.frame = CGRect(x: 0, y: 0, width: bounds.width * min(max(fraction, 0), 1), height: bounds.height)
    }
}

private final class DemoDiceView: UIView {
    private let value: Int

    init(value: Int) {
        self.value = value
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let size: CGFloat = 40
        let face = CGRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
        let tokens = Host.tokens
        func luminance(_ color: UIColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        let ends = [tokens.textColorButton, tokens.textColorPrimary, tokens.bgColorDialog].sorted { luminance($0) < luminance($1) }
        ends.last?.setFill()
        UIBezierPath(roundedRect: face, cornerRadius: 9).fill()
        let darkDot = ends.first ?? .black
        let cells: [Int]
        switch value {
        case 1: cells = [5]
        case 2: cells = [1, 9]
        case 3: cells = [1, 5, 9]
        case 4: cells = [1, 3, 7, 9]
        case 5: cells = [1, 3, 5, 7, 9]
        default: cells = [1, 3, 4, 6, 7, 9]
        }
        let innerW = size - 13
        let innerH = size - 11
        for cell in cells {
            let col = CGFloat((cell - 1) % 3)
            let row = CGFloat((cell - 1) / 3)
            let center = CGPoint(x: face.minX + 6.5 + innerW / 3 * (col + 0.5), y: face.minY + 5.5 + innerH / 3 * (row + 0.5))
            (cell == 1 || cell == 9 || value == 1 ? tokens.tagColorLevel4 : darkDot).setFill()
            UIBezierPath(arcCenter: center, radius: 3.25, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
        }
    }
}

private final class DemoMapView: UIView {
    static let size = CGSize(width: 216, height: 112)

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        let map = UIImageView(image: Host.image("demo_card_map_river"))
        map.contentMode = .scaleAspectFill
        map.clipsToBounds = true
        map.translatesAutoresizingMaskIntoConstraints = false
        addSubview(map)
        Host.pin(map, to: self)
        let pin = UIImageView(image: Host.image("demo_ic_map_pin"))
        pin.contentMode = .scaleAspectFit
        pin.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pin)
        NSLayoutConstraint.activate([
            pin.centerXAnchor.constraint(equalTo: centerXAnchor), pin.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18),
            pin.widthAnchor.constraint(equalToConstant: 32), pin.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Renders a chat.card inside the SDK bubble. Sender/direction come from the real
/// message; text is local demo content. No animation replays on re-bind. The card paints its own
/// full-bleed fill, so the SDK bubble shape (18/6 corners) is the card outline.
final class DemoCardContentView: UIView, MessageContentView, MessageBubblelessContentView {

    private let stack = UIStackView()
    private let fillLayer = CAGradientLayer()
    /// The prototype's `inset 0 0 0 1px` ring: above the fill, below the content (a map or photo covers it).
    private let ringLayer = CALayer()
    private var widthConstraint: NSLayoutConstraint!
    private var topConstraint: NSLayoutConstraint!
    private var bottomConstraint: NSLayoutConstraint!
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    private var ticker: Timer?
    private var source: (data: String?, me: Bool, timeMs: Int64?, quizKey: String)?
    private var boundCard: DemoCardProtocol.Card?
    private var burnTap: UITapGestureRecognizer?
    private var replayTap: UITapGestureRecognizer?
    private var packetTap: UITapGestureRecognizer?
    private weak var packetIcon: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(fillLayer)
        layer.addSublayer(ringLayer)
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        widthConstraint = stack.widthAnchor.constraint(equalToConstant: 232)
        topConstraint = stack.topAnchor.constraint(equalTo: topAnchor, constant: 12)
        bottomConstraint = stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        leadingConstraint = stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14)
        trailingConstraint = stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
        NSLayoutConstraint.activate([widthConstraint, topConstraint, bottomConstraint, leadingConstraint, trailingConstraint])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame = bounds
        ringLayer.frame = bounds
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { ticker?.invalidate(); ticker = nil }
    }

    deinit { ticker?.invalidate() }

    private func configure(width: CGFloat, top: CGFloat, side: CGFloat, bottom: CGFloat, fill: [UIColor],
                           start: CGPoint = .zero, end: CGPoint = CGPoint(x: 1, y: 1), centered: Bool = false,
                           radius: CGFloat = 14, stroke: UIColor? = nil) {
        layer.cornerRadius = radius
        clipsToBounds = true
        ringLayer.cornerRadius = radius
        ringLayer.borderWidth = stroke == nil ? 0 : 1
        ringLayer.borderColor = stroke?.cgColor
        widthConstraint.constant = width
        topConstraint.constant = top
        leadingConstraint.constant = side
        trailingConstraint.constant = -side
        bottomConstraint.constant = -bottom
        fillLayer.colors = (fill.count == 1 ? [fill[0], fill[0]] : fill).map { $0.cgColor }
        fillLayer.startPoint = start
        fillLayer.endPoint = end
        stack.alignment = centered ? .center : .fill
    }

    private func solidFill(_ color: UIColor) -> [UIColor] { [color] }

    private func schedule(after delay: TimeInterval = 0.5) {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.window != nil else { return }
            self.render()
        }
    }

    private func rebind() { render() }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    func bind(message: MessageInfo, context: MessageContentContext) {
        var customData: String?
        if case .custom(let payload) = message.messagePayload { customData = payload.customData }
        let key = [message.from.userID, message.to].sorted().joined(separator: "|")
        let next = (data: customData, me: message.isSentBySelf, timeMs: message.timestamp.map { $0 * 1000 }, quizKey: key)
        // The list re-binds a visible card in place when only the send status changed: keep what is on screen
        // (rebuilding it from scratch is what made old cards blink on every send).
        if window != nil, let current = source, !stack.arrangedSubviews.isEmpty,
           current.data == next.data, current.me == next.me, current.timeMs == next.timeMs, current.quizKey == next.quizKey {
            return
        }
        source = next
        render()
    }

    private func render() {
        guard let source else { return }
        ticker?.invalidate()
        ticker = nil
        burnTap.map { removeGestureRecognizer($0) }
        burnTap = nil
        replayTap.map { removeGestureRecognizer($0) }
        replayTap = nil
        packetTap.map { removeGestureRecognizer($0) }
        packetTap = nil
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let card = DemoCardProtocol.parse(source.data)
        let me = source.me
        boundCard = card
        var effectTarget: UIView?
        if let card, card.isKnownKind {
            switch card.kind {
            case "pat": effectTarget = buildPat(card, me: me)
            case "listen": buildListen(card, me: me)
            case "photoSwap": buildSwap(card, me: me)
            case "location": buildLocation(card)
            case "burn": buildBurn(card, me: me)
            case "dice": effectTarget = buildDice(card, me: me)
            case "rps": effectTarget = buildRps(card, me: me)
            case "quiz": buildQuiz(card, key: source.quizKey)
            case "gift": effectTarget = buildGift(card, me: me)
            case "redpacket": effectTarget = buildRedPacket(card, me: me)
            default: break
            }
        } else {
            configure(width: 232, top: 12, side: 14, bottom: 10, fill: solidFill(Host.tokens.bgColorBubbleReciprocal))
            stack.addArrangedSubview(label(DemoText.get("demo_unsupported_demo_card_update_the_demo_to"), 12, Host.tokens.textColorSecondary))
        }
        if let card, let effectTarget {
            let messageMs = source.timeMs ?? nowMs()
            if DemoEffectGate.shouldPlay(eventId: card.eventId, messageTimeMs: messageMs, nowMs: nowMs()) {
                let kind = card.kind
                DispatchQueue.main.async { [weak effectTarget] in
                    if let effectTarget { Self.playEffect(kind: kind, on: effectTarget) }
                }
            }
        }
    }

    private func spacer(_ view: UIView, after: CGFloat) {
        stack.addArrangedSubview(view)
        stack.setCustomSpacing(after, after: view)
    }

    private func sized(_ view: UIView, _ width: CGFloat, _ height: CGFloat) -> UIView {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func rounded(_ view: UIView, _ radius: CGFloat) -> UIView {
        view.layer.cornerRadius = radius
        view.clipsToBounds = true
        return view
    }

    private func row(_ views: [UIView], spacing: CGFloat = 0, alignment: UIStackView.Alignment = .center) -> UIStackView {
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.alignment = alignment
        row.spacing = spacing
        return row
    }

    private func column(_ views: [UIView]) -> UIStackView {
        let column = UIStackView(arrangedSubviews: views)
        column.axis = .vertical
        return column
    }

    private func centered(_ text: String, _ size: CGFloat, _ color: UIColor, bold: Bool = false) -> UILabel {
        let item = label(text, size, color, bold: bold)
        item.textAlignment = .center
        return item
    }

    private func buildPat(_ card: DemoCardProtocol.Card, me: Bool) -> UIView {
        configure(width: 200, top: 6, side: 14, bottom: 6, fill: cardTint(Host.tokens.textColorWarning), start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5),
                  radius: 16, stroke: cardRing(Host.tokens.textColorWarning, 0.3))
        let hand = UIImageView(image: Host.image("demo_pat_hand"))
        hand.contentMode = .scaleAspectFit
        let title = label(me ? DemoText.get("demo_you_patted_their_head") : card.payload["text"] ?? DemoText.get("demo_patted_your_head"), 13, Host.tokens.textColorWarning, bold: true)
        let box = sized(hand, 52, 52)
        stack.addArrangedSubview(row([box, title], spacing: 8))
        return box
    }

    private func buildListen(_ card: DemoCardProtocol.Card, me: Bool) {
        configure(width: 232, top: 10, side: 10, bottom: 10, fill: cardTint(Host.tokens.buttonColorPrimaryDefault), start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5),
                  stroke: cardRing(Host.tokens.buttonColorPrimaryDefault))
        let duration = Int64(card.payload["durationMs"] ?? "") ?? 0
        let view = DemoCardLocalState.listen(instanceId: card.instanceId, durationMs: duration, nowMs: nowMs())
        let cover = rounded(Host.photo("demo_photo_records"), 10)
        let invite: String
        if let title = card.payload["title"], !title.isEmpty {
            invite = me ? DemoText.get("demo_you_invited_them_to_listen_song", title) : DemoText.get("demo_invited_you_to_listen_song", title)
        } else {
            invite = me ? DemoText.get("demo_you_invited_them_to_listen_together") : DemoText.get("demo_invited_you_to_listen_together")
        }
        let status: String
        if !view.joined { status = DemoText.get("demo_tap_to_listen_together") }
        else if view.playing { status = DemoText.get("demo_listening_together", "\(clock(String(view.positionMs)))") }
        else { status = DemoText.get("demo_listening_together_paused") }
        let song = label(invite, 13, Host.tokens.textColorPrimary, bold: true)
        song.numberOfLines = 2
        let sub = label(status, 10, Host.tokens.textColorTertiary)
        sub.numberOfLines = 1
        let bar = DemoProgressBar(track: Host.tokens.strokeColorPrimary, fill: Host.tokens.buttonColorPrimaryDefault)
        bar.fraction = duration > 0 ? CGFloat(view.positionMs) / CGFloat(duration) : 0
        let meta = column([song, sub, bar])
        meta.spacing = 5
        bar.heightAnchor.constraint(equalToConstant: 3).isActive = true
        let button = DemoTapView()
        button.backgroundColor = cardRing(Host.tokens.buttonColorPrimaryDefault, 0.2)
        button.accessibilityLabel = view.playing ? DemoText.get("demo_pause_listening_together") : DemoText.get("demo_listen_together")
        let glyph = Host.icon(view.playing ? "demo_ic_pause" : "demo_ic_note", size: 15, tint: Host.tokens.buttonColorPrimaryDefault)
        button.addSubview(glyph)
        NSLayoutConstraint.activate([glyph.centerXAnchor.constraint(equalTo: button.centerXAnchor), glyph.centerYAnchor.constraint(equalTo: button.centerYAnchor)])
        button.layer.cornerRadius = 15
        button.onTap = { [weak self] in
            DemoCardLocalState.toggleListen(instanceId: card.instanceId, durationMs: duration, nowMs: self?.nowMs() ?? 0)
            self?.rebind()
        }
        let line = row([sized(cover, 50, 50), meta, sized(button, 30, 30)], spacing: 10)
        stack.addArrangedSubview(line)
        if view.playing { schedule() }
    }

    private func buildSwap(_ card: DemoCardProtocol.Card, me: Bool) {
        configure(width: 216, top: 12, side: 12, bottom: 12, fill: cardTint(Host.tokens.buttonColorPrimaryDefault), start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5),
                  stroke: cardRing(Host.tokens.buttonColorPrimaryDefault))
        let now = nowMs()
        let state = DemoCardLocalState.swap(instanceId: card.instanceId, nowMs: now)
        let title: String
        switch state {
        case .invited: title = me ? DemoText.get("demo_you_started_a_photo_swap") : card.payload["text"] ?? DemoText.get("demo_invited_you_to_swap_photos")
        case .ready: title = DemoText.get("demo_your_demo_photo_is_ready")
        case .revealed: title = DemoText.get("demo_demo_photos_swapped")
        }
        spacer(label(title, 14, Host.tokens.textColorPrimary, bold: true), after: 8)
        func slot(_ text: String, _ photo: String, shown: Bool) -> UIView {
            let box = UIView()
            box.backgroundColor = Host.tokens.bgColorFunction
            _ = rounded(box, 10)
            if shown {
                let image = Host.photo(photo)
                image.translatesAutoresizingMaskIntoConstraints = false
                box.addSubview(image)
                Host.pin(image, to: box)
                let tap = DemoTapView()
                tap.translatesAutoresizingMaskIntoConstraints = false
                tap.accessibilityLabel = text
                tap.onTap = { [weak box] in
                    guard let box else { return }
                    DemoPhotoPreviewController.present(ref: photo, source: box)
                }
                box.addSubview(tap)
                Host.pin(tap, to: box)
            } else {
                let caption = centered(text, 10, Host.tokens.textColorSecondary)
                caption.translatesAutoresizingMaskIntoConstraints = false
                box.addSubview(caption)
                NSLayoutConstraint.activate([caption.centerXAnchor.constraint(equalTo: box.centerXAnchor), caption.centerYAnchor.constraint(equalTo: box.centerYAnchor)])
            }
            box.heightAnchor.constraint(equalToConstant: 76).isActive = true
            return box
        }
        let slots = UIStackView(arrangedSubviews: [
            slot(DemoText.get("demo_my_photo"), "demo_photo_coffee", shown: state != .invited),
            slot(DemoText.get("demo_their_photo"), "demo_photo_sea", shown: state == .revealed)
        ])
        slots.axis = .horizontal
        slots.distribution = .fillEqually
        slots.spacing = 8
        stack.addArrangedSubview(slots)
        switch state {
        case .invited:
            let text = DemoText.get("demo_pick_a_demo_photo")
            let button = DemoTapView()
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            button.layer.cornerRadius = 14
            button.clipsToBounds = true
            let gradient = Host.brandGradientLayer()
            button.layer.insertSublayer(gradient, at: 0)
            button.gradient = gradient
            button.layer.setValue(gradient, forKey: "demo.gradient")
            let caption = centered(text, 12, Host.tokens.textColorButton, bold: true)
            caption.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(caption)
            NSLayoutConstraint.activate([caption.centerXAnchor.constraint(equalTo: button.centerXAnchor), caption.centerYAnchor.constraint(equalTo: button.centerYAnchor)])
            button.accessibilityLabel = text
            button.onTap = { [weak self] in
                guard let self else { return }
                DemoCardLocalState.pickSwap(instanceId: card.instanceId, nowMs: self.nowMs())
                self.rebind()
            }
            stack.setCustomSpacing(8, after: slots)
            stack.addArrangedSubview(button)
        case .ready:
            schedule(after: Double(DemoCardLocalState.swapRevealRemainingMs(instanceId: card.instanceId, nowMs: now)) / 1000 + 0.02)
        case .revealed:
            break
        }
    }

    private func buildLocation(_ card: DemoCardProtocol.Card) {
        let tokens = Host.tokens
        configure(width: DemoMapView.size.width, top: 0, side: 0, bottom: 10, fill: solidFill(tokens.bgColorDialog), stroke: tokens.strokeColorPrimary)
        let map = DemoMapView()
        map.heightAnchor.constraint(equalToConstant: DemoMapView.size.height).isActive = true
        stack.addArrangedSubview(map)
        let title = label(card.payload["title"] ?? DemoText.get("demo_demo_place"), 12, tokens.textColorPrimary, bold: true)
        title.numberOfLines = 1
        let address = label(card.payload["address"] ?? DemoText.get("demo_demo_address"), 10, tokens.textColorTertiary)
        address.numberOfLines = 1
        let info = column([title, address])
        info.spacing = 3
        info.isLayoutMarginsRelativeArrangement = true
        info.layoutMargins = UIEdgeInsets(top: 9, left: 11, bottom: 0, right: 11)
        stack.addArrangedSubview(info)
    }

    private static let burnSide: CGFloat = 173

    private func buildBurn(_ card: DemoCardProtocol.Card, me: Bool) {
        let side = Self.burnSide
        let seconds = DemoCardLocalState.burnSeconds(card.payload["viewSeconds"])
        let view = DemoCardLocalState.burn(instanceId: card.instanceId, nowMs: nowMs())
        let tokens = Host.tokens
        let box = UIView()
        func centeredColumn(_ views: [UIView]) {
            let inner = UIStackView(arrangedSubviews: views)
            inner.axis = .vertical
            inner.alignment = .center
            inner.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(inner)
            NSLayoutConstraint.activate([
                inner.centerXAnchor.constraint(equalTo: box.centerXAnchor), inner.centerYAnchor.constraint(equalTo: box.centerYAnchor),
                inner.leadingAnchor.constraint(greaterThanOrEqualTo: box.leadingAnchor, constant: 14),
                inner.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -14)
            ])
        }
        switch view.state {
        case .sealed:
            configure(width: side, top: 0, side: 0, bottom: 0, fill: cardTint(tokens.buttonColorPrimaryDefault, 0.26),
                      stroke: cardRing(Host.tokens.buttonColorPrimaryDefault))
            let lock = Host.icon("demo_ic_lock", size: 30, tint: tokens.buttonColorPrimaryDefault)
            let title = centered(me ? DemoText.get("demo_private_photo_sent") : DemoText.get("demo_they_sent_you_a_private_photo"), 13, tokens.textColorPrimary, bold: true)
            let hint = centered(me ? DemoText.get("demo_self_destructs_s_after_they_open_it", "\(seconds)") : DemoText.get("demo_tap_to_view_self_destructs_after_s", "\(seconds)"), 10, tokens.textColorTertiary)
            centeredColumn([lock, title, hint])
            if let column = box.subviews.first as? UIStackView {
                column.spacing = 8
            }
            if !me {
                let tap = UITapGestureRecognizer(target: self, action: #selector(burnTapped))
                addGestureRecognizer(tap)
                burnTap = tap
            }
        case .viewing:
            configure(width: side, top: 0, side: 0, bottom: 0, fill: solidFill(tokens.bgColorFunction))
            let photo = Host.photo("demo_photo_chengdu")
            photo.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(photo)
            Host.pin(photo, to: box)
            let left = Int((view.remainingMs + 999) / 1000)
            let counter = label(DemoText.get("demo_self_destructs_in_s_demo_asset", "\(left)"), 11, tokens.textColorButton, bold: true)
            counter.numberOfLines = 1
            counter.textAlignment = .center
            let pill = UIView()
            pill.backgroundColor = tokens.bgColorMask
            pill.layer.cornerRadius = 11
            counter.translatesAutoresizingMaskIntoConstraints = false
            pill.addSubview(counter)
            pill.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(pill)
            NSLayoutConstraint.activate([
                counter.topAnchor.constraint(equalTo: pill.topAnchor, constant: 4), counter.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -4),
                counter.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10), counter.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
                pill.centerXAnchor.constraint(equalTo: box.centerXAnchor), pill.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10)
            ])
            schedule()
        case .expired:
            configure(width: side, top: 0, side: 0, bottom: 0, fill: solidFill(tokens.bgColorBubbleReciprocal))
            let eye = Host.icon("demo_ic_eye", size: 26, tint: tokens.textColorTertiary)
            let title = centered(DemoText.get("demo_photo_destroyed"), 13, tokens.textColorSecondary, bold: true)
            let hint = centered(DemoText.get("demo_burn_after_reading_viewed"), 10, tokens.textColorTertiary)
            centeredColumn([eye, title, hint])
            if let column = box.subviews.first as? UIStackView {
                column.spacing = 8
            }
        }
        stack.addArrangedSubview(sized(box, side, side))
    }

    @objc private func burnTapped() {
        guard let card = boundCard else { return }
        if DemoCardLocalState.openBurn(instanceId: card.instanceId, seconds: DemoCardLocalState.burnSeconds(card.payload["viewSeconds"]), nowMs: nowMs()) {
            rebind()
        }
    }

    /// Demo red packet: no payment, the amount is display-only. The receiver taps once to open; the state is local.
    private func buildRedPacket(_ card: DemoCardProtocol.Card, me: Bool) -> UIView? {
        let tokens = Host.tokens
        let opened = DemoCardLocalState.redPacketOpened(instanceId: card.instanceId)
        let base = tokens.textColorError
        let warm = cardMix(base, tokens.textColorWarning, 0.4)
        let faded = cardMix(base, tokens.bgColorDialog, 0.45)
        let fadedWarm = cardMix(warm, tokens.bgColorDialog, 0.45)
        configure(width: 216, top: 12, side: 12, bottom: 12, fill: opened ? [faded, fadedWarm] : [base, warm],
                  start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5), radius: 14)
        let icon = UIImageView(image: Host.image("demo_card_redpacket"))
        icon.contentMode = .scaleAspectFit
        let white = tokens.textColorButton
        let plate = UIView()
        plate.backgroundColor = white.withAlphaComponent(0.92)
        plate.layer.cornerRadius = 12
        icon.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: 5),
            icon.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -5),
            icon.topAnchor.constraint(equalTo: plate.topAnchor, constant: 5),
            icon.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -5)
        ])
        let box = sized(plate, 44, 44)
        packetIcon = box
        let greeting = label(card.payload["greeting"] ?? DemoText.get("demo_red_packet_greeting"), 14, white, bold: true)
        greeting.numberOfLines = 2
        let value = card.payload["displayValue"] ?? "0"
        let unit = card.payload["displayUnit"] ?? DemoText.get("demo_fx_diamond_unit")
        let status: String
        if opened { status = DemoText.get("demo_red_packet_opened", value, unit) }
        else if me { status = DemoText.get("demo_red_packet_waiting") }
        else { status = DemoText.get("demo_red_packet_tap_to_open") }
        let sub = label(status, 11, white.withAlphaComponent(0.88))
        let meta = column([greeting, sub])
        meta.spacing = 3
        stack.addArrangedSubview(row([box, meta], spacing: 10))
        if !me && !opened {
            let tap = UITapGestureRecognizer(target: self, action: #selector(redPacketTapped))
            addGestureRecognizer(tap)
            packetTap = tap
            isAccessibilityElement = true
            accessibilityLabel = DemoText.get("demo_red_packet_tap_to_open")
            accessibilityTraits = .button
        } else {
            isAccessibilityElement = false
        }
        return nil
    }

    @objc private func redPacketTapped() {
        guard let card = boundCard, card.kind == "redpacket" else { return }
        if DemoCardLocalState.openRedPacket(instanceId: card.instanceId) {
            rebind()
            guard !UIAccessibility.isReduceMotionEnabled, let target = packetIcon else { return }
            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = [1, 1.35, 0.92, 1]
            pulse.duration = 0.5
            target.layer.add(pulse, forKey: "demo.effect")
        }
    }

    private func buildDice(_ card: DemoCardProtocol.Card, me: Bool) -> UIView {
        configure(width: 176, top: 14, side: 18, bottom: 10, fill: [Host.tokens.buttonColorPrimaryDefault, Host.tokens.tagColorLevel4], centered: true, radius: 16)
        let value = min(max(Int(card.payload["value"] ?? "") ?? 1, 1), 6)
        let die = sized(DemoDiceView(value: value), 46, 46)
        spacer(die, after: 8)
        spacer(centered(DemoText.get("demo_rolled", "\(me ? DemoText.get("demo_you") : DemoText.get("demo_they"))", "\(value)"), 15, Host.tokens.textColorButton, bold: true), after: 8)
        spacer(centered(value >= 4 ? DemoText.get("demo_the_higher_roll_asks_a_question") : DemoText.get("demo_the_lower_roll_answers"), 10, Host.tokens.textColorButton.withAlphaComponent(0.85)), after: 0)
        return die
    }

    /// Same shell as the dice card; hand and outcome come from the payload, nothing is rolled here.
    private func buildRps(_ card: DemoCardProtocol.Card, me: Bool) -> UIView {
        configure(width: 112, top: 10, side: 12, bottom: 8, fill: [Host.tokens.buttonColorPrimaryDefault, Host.tokens.tagColorLevel4], centered: true, radius: 16)
        let picture = UIImageView(image: Host.image(DemoRps.handImageName(card.payload["hand"])))
        picture.contentMode = .scaleAspectFit
        picture.isAccessibilityElement = true
        picture.accessibilityLabel = DemoRps.handLabel(card.payload["hand"])
        let box = sized(picture, 72, 72)
        spacer(box, after: 2)
        spacer(centered(DemoRps.handLabel(card.payload["hand"]), 13, Host.tokens.textColorButton, bold: true), after: 0)
        if !me {
            let tap = UITapGestureRecognizer(target: self, action: #selector(replayTapped))
            addGestureRecognizer(tap)
            replayTap = tap
        }
        return box
    }

    @objc private func replayTapped() {
        guard let card = boundCard, card.kind == "rps" else { return }
        DemoChat.requestReplay(kind: card.kind, from: self)
    }

    private func buildQuiz(_ card: DemoCardProtocol.Card, key: String) {
        configure(width: 218, top: 13, side: 14, bottom: 10, fill: cardTint(Host.tokens.tagColorLevel4, 0.18), start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5),
                  stroke: cardRing(Host.tokens.tagColorLevel4, 0.3))
        let chosen = DemoInteractionStore.state(for: key).selection(instanceId: card.instanceId, senderId: DemoInteractionState.localActor)
        spacer(label(DemoText.get("demo_crush_quiz_question", "\(card.payload["round"] ?? "1")"), 11, Host.tokens.tagColorLevel4, bold: true), after: 9)
        spacer(label(card.payload["question"] ?? "", 13, Host.tokens.textColorPrimary), after: 9)
        var chips: [UIView] = []
        for (id, text) in [("A", card.payload["optionA"]), ("B", card.payload["optionB"])] {
            guard let text else { continue }
            let picked = chosen == id
            let chip = DemoQuizOptionLabel()
            chip.optionId = id
            chip.text = picked ? "✓ \(text)" : text
            chip.font = .adaptiveSystemFont(ofSize: 12, weight: picked ? .semibold : .regular)
            chip.textColor = picked ? Host.tokens.tagColorLevel4 : Host.tokens.textColorSecondary
            chip.textAlignment = .center
            chip.numberOfLines = 1
            chip.backgroundColor = picked ? Host.tokens.tagColorLevel4.withAlphaComponent(0.16) : Host.tokens.bgColorFunction
            chip.layer.cornerRadius = 10
            chip.layer.borderWidth = 1
            chip.layer.borderColor = (picked ? Host.tokens.tagColorLevel4.withAlphaComponent(0.4) : Host.tokens.strokeColorPrimary).cgColor
            chip.clipsToBounds = true
            chip.isUserInteractionEnabled = true
            chip.isAccessibilityElement = true
            chip.accessibilityLabel = picked ? DemoText.get("demo_selected", "\(text)") : DemoText.get("demo_select", "\(text)")
            chip.accessibilityTraits = .button
            chip.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(quizOptionTapped(_:))))
            chip.heightAnchor.constraint(equalToConstant: 32).isActive = true
            chips.append(chip)
        }
        let options = UIStackView(arrangedSubviews: chips)
        options.axis = .horizontal
        options.distribution = .fillEqually
        options.spacing = 8
        spacer(options, after: 8)
        spacer(label(chosen == nil ? DemoText.get("demo_pick_an_answer_local_demo_only_not") : DemoText.get("demo_your_choice_is_recorded_local_demo_only"), 10, Host.tokens.textColorTertiary), after: 0)
    }

    private func buildGift(_ card: DemoCardProtocol.Card, me: Bool) -> UIView {
        let tokens = Host.tokens
        configure(width: 196, top: 12, side: 12, bottom: 10, fill: solidFill(tokens.bgColorDialog), radius: 12, stroke: tokens.strokeColorPrimary)
        let gift = giftRow(card, tokens: tokens)
        spacer(gift.row, after: me ? 8 : 0)
        if me {
            // Only the sender's own card says "已送出"; a received gift no longer invites a gift back.
            let rule = UIView()
            rule.backgroundColor = tokens.strokeColorPrimary
            rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
            spacer(rule, after: 8)
            spacer(label(DemoText.get("demo_sent_demo_gift_no_charge_and_no"), 10, tokens.textColorSecondary), after: 0)
        }
        return gift.tile
    }

    override func layoutSublayers(of layer: CALayer) {
        super.layoutSublayers(of: layer)
        updateGradients(in: self)
    }

    private func updateGradients(in view: UIView) {
        for sub in view.subviews {
            if let gradient = sub.layer.value(forKey: "demo.gradient") as? CAGradientLayer { gradient.frame = sub.bounds }
            updateGradients(in: sub)
        }
    }

    @objc private func quizOptionTapped(_ gesture: UITapGestureRecognizer) {
        guard let option = gesture.view as? DemoQuizOptionLabel, let source, let card = boundCard else { return }
        let state = DemoInteractionStore.state(for: source.quizKey)
        let outcome = state.apply(.init(
            targetInstanceId: card.instanceId, eventId: UUID().uuidString,
            senderId: DemoInteractionState.localActor,
            actorSequence: state.nextSequence(instanceId: card.instanceId, senderId: DemoInteractionState.localActor),
            kind: "quiz", action: "select", params: ["optionId": option.optionId]))
        if outcome == .applied { render() }
    }

    /// One-shot, short, decorative effects; skipped when Reduce Motion is on.
    private static func playEffect(kind: String, on target: UIView) {
        guard !UIAccessibility.isReduceMotionEnabled, target.window != nil else { return }
        switch kind {
        case "pat":
            let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shake.values = [0, -8, 8, -6, 6, -3, 0]
            shake.duration = 0.55
            target.layer.add(shake, forKey: "demo.effect")
        case "dice", "rps":
            let roll = CABasicAnimation(keyPath: "transform.rotation.z")
            roll.fromValue = 0
            roll.toValue = 4 * Double.pi
            roll.duration = 0.65
            roll.timingFunction = CAMediaTimingFunction(name: .easeOut)
            target.layer.add(roll, forKey: "demo.effect")
        case "gift":
            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = [1, 1.3, 0.95, 1]
            pulse.duration = 0.6
            target.layer.add(pulse, forKey: "demo.effect")
            DemoHeartBurst.play(from: target)
        default:
            break
        }
    }

    private func giftRow(_ card: DemoCardProtocol.Card?, tokens: ColorTokens) -> (row: UIView, tile: UIView) {
        let tile = UIImageView(image: Host.image(DemoGiftIcons.name(card?.payload["giftRef"] ?? "")))
        tile.contentMode = .scaleAspectFit
        let name = card?.payload["name"] ?? DemoText.get("demo_demo_gift")
        let quantity = card?.payload["quantity"] ?? "1"
        let meta = UIStackView(arrangedSubviews: [
            label("\(name) ×\(quantity)", 14, tokens.textColorPrimary, bold: true),
            label(DemoText.get("demo_worth", "\(card?.payload["displayValue"] ?? "0")", "\(card?.payload["displayUnit"] ?? "")"), 10, tokens.textColorSecondary)
        ])
        meta.axis = .vertical
        meta.spacing = 2
        let row = UIStackView(arrangedSubviews: [tile, meta])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 48),
            tile.heightAnchor.constraint(equalToConstant: 48)
        ])
        return (row, tile)
    }

    private func clock(_ ms: String?) -> String {
        let total = (Int(ms ?? "") ?? 0) / 1000
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

// MARK: - Chat page factory

/// Builds the 1v1 chat page with host chrome (design S3/S4). Real: messages, card
/// transport, calls, greeting/recent routing. Local content: subtitle, safety copy, card content.
enum DemoChat {
    private static var registered = false

    /// Posted by a received card that invites another round; only the chat page that owns the card answers it.
    static let replayRequested = Notification.Name("chat.demoCard.replayRequested")

    fileprivate static func requestReplay(kind: String, from view: UIView) {
        var responder: UIResponder? = view
        while let current = responder {
            if let page = current as? ChatPage {
                NotificationCenter.default.post(name: replayRequested, object: page, userInfo: ["kind": kind])
                return
            }
            responder = current.next
        }
    }

    static func registerRenderersOnce() {
        guard !registered else { return }
        registered = true
        MessageListView.registerCustomMessageCell(
            businessID: DemoCardProtocol.businessID,
            summaryProvider: { DemoCardProtocol.summary(DemoCardProtocol.parse($0.customData)) },
            makeContentView: { DemoCardContentView() }
        )
    }

    /// Neutral pill for peers the demo knows nothing about (real accounts such as 100480): no city / age / height.
    static var unknownChip: ChatHeaderChip {
        ChatHeaderChip(text: DemoText.get("demo_unknown"),
                       color: Host.tokens.bgColorFunction,
                       textColor: Host.tokens.textColorSecondary)
    }

    static func headerChips(for profile: DemoPeerProfile) -> [ChatHeaderChip] {
        var chips: [ChatHeaderChip] = []
        if !profile.city.isEmpty {
            chips.append(ChatHeaderChip(text: profile.city, color: Host.tagAccent(.city).withAlphaComponent(0.92)))
        }
        if profile.age > 0 {
            chips.append(ChatHeaderChip(text: DemoText.get("demo_age_years", "\(profile.age)"), color: Host.tagAccent(Host.ageKind(sex: profile.sex)).withAlphaComponent(0.92)))
        }
        if profile.height > 0 {
            chips.append(ChatHeaderChip(text: DemoText.get("demo_height_cm", "\(profile.height)"), color: Host.tagAccent(.height).withAlphaComponent(0.92)))
        }
        return chips
    }

    static func makePage(conversation: ConversationInfo, subtitle: String? = nil,
                         locateMessage: MessageInfo? = nil,
                         preview: Bool = false, onBack: @escaping () -> Void) -> ChatPage {
        registerRenderersOnce()
        var conversation = conversation
        if conversation.conversationID.hasPrefix("c2c_") {
            let peerID = String(conversation.conversationID.dropFirst(4))
            let current = conversation.title ?? ""
            if current.isEmpty || current == peerID, let known = DemoPeerProfiles.forUser(peerID) {
                conversation.title = known.name
            }
        }
        let copy = DemoChatCopy.load()
        let config = ChatMessageListConfig(
            isShowRightAvatar: false,
            ownBubbleAppearance: MessageBubbleAppearance(
                background: .gradient(colors: [Palette.accent, Palette.brandEnd],
                                      startPoint: CGPoint(x: 0, y: 0.5), endPoint: CGPoint(x: 1, y: 0.5)),
                cornerRadius: MessageBubbleCornerRadius(topLeft: 18, topRight: 6, bottomLeft: 18, bottomRight: 18)
            ),
            incomingBubbleAppearance: MessageBubbleAppearance(
                background: .color(Palette.bubbleIn),
                cornerRadius: MessageBubbleCornerRadius(topLeft: 6, topRight: 18, bottomLeft: 18, bottomRight: 18)
            )
        )
        let id = conversation.conversationID
        weak var pageRef: ChatPage?
        let promote: () -> Void = {
            guard !preview else { return }
            DemoGroupWatcher.shared.noteReplied(id)
        }
        let sender = DemoCardSender(conversationID: id, preview: preview, onSent: promote)
        let customizer: MessageInputActionCustomizer = { editor in
            if !(copy.morePanel ?? []).isEmpty {
                for (actionID, tileName) in [(MessageInputActionIDs.takePhoto, "demo_fn_camera"), (MessageInputActionIDs.recordVideo, "demo_fn_video")] {
                    guard let native = editor.items.first(where: { $0.ID == actionID }), let tile = UIImage(named: tileName) else { continue }
                    editor.remove(actionID)
                    editor.insertBefore(MessageInputActionIDs.album, MessageInputMenuAction(
                        ID: actionID, title: native.title, iconName: "", icon: tile, fullBleedIcon: true, onClick: native.onClick))
                }
            }
            for item in copy.morePanel ?? [] {
                guard let tile = UIImage(named: item.tile) else { continue }
                editor.insertBefore(MessageInputActionIDs.album, MessageInputMenuAction(
                    ID: "chat.more.\(item.id)", title: item.label, iconName: "", icon: tile,
                    fullBleedIcon: true, badgeText: item.badge,
                    onClick: {
                        guard let page = pageRef else { return }
                        if item.action == "card", let kind = item.kind {
                            let payload = DemoCardRolls.rolled(kind: kind, payload: (item.payload ?? [:]).mapValues { $0.any })
                            sender.send(key: item.id, kind: kind, summary: item.summary ?? DemoText.get("demo_interaction_card"),
                                        payload: payload, from: page)
                        } else {
                            alert(page, item.notice ?? DemoText.get("demo_demo_placeholder", "\(item.label)"))
                        }
                    }))
            }
            if !(copy.morePanel ?? []).isEmpty {
                [MessageInputActionIDs.album, MessageInputActionIDs.file,
                 MessageInputActionIDs.videoCall, MessageInputActionIDs.audioCall]
                    .forEach { _ = editor.remove($0) }
            }
        }
        let quickActions = copy.quickActions ?? []
        let inputConfig: ChatMessageInputConfig
        if quickActions.isEmpty {
            inputConfig = ChatMessageInputConfig(actionCustomizer: customizer)
        } else {
            inputConfig = ChatMessageInputConfig(isShowMore: false, isShowEmoji: false,
                                                 actionCustomizer: customizer,
                                                 appearance: inputAppearance(copy))
        }
        let settingPeer = id.hasPrefix("c2c_") ? String(id.dropFirst(4)) : ""
        let page = ChatPage(conversation: conversation, locateMessage: locateMessage, messageListConfig: config,
                            messageInputConfig: inputConfig, onBack: onBack,
                            onMoreClick: {
                                guard let page = pageRef else { return }
                                openChatSettings(from: page, peer: settingPeer, copy: copy, preview: preview)
                            },
                            onMessageSent: promote)
        pageRef = page
        DemoReplayObserver.attach(to: page) { [weak page] kind in
            guard let page, kind == "rps" else { return }
            sender.send(key: kind, kind: kind, summary: DemoCardProtocol.summaryOf(kind: kind),
                        payload: DemoCardRolls.rolled(kind: kind, payload: [:]), from: page)
        }
        page.hidesBottomBarWhenPushed = true
        let peer = id.hasPrefix("c2c_") ? String(id.dropFirst(4)) : ""
        let peerProfile = peer.isEmpty ? nil : DemoPeerProfiles.forUser(peer)
        if preview {
            page.headerSubtitle = DemoText.get("demo_ui_preview_not_logged_in_no_message_2")
        } else if let peerProfile {
            let chips = headerChips(for: peerProfile)
            page.headerChips = chips.isEmpty ? [unknownChip] : chips
        } else if let subtitle, !subtitle.isEmpty {
            // Opened from a home card: the caller already resolved the peer's city / height / age into text.
            page.headerSubtitle = subtitle
        } else {
            page.headerChips = [unknownChip]
        }
        if !preview, let fixtureID = peerProfile?.fixtureID {
            page.headerAccessibilityLabel = DemoText.get("demo_view_profile")
            page.onHeaderClick = { [weak page] in
                guard let page else { return }
                page.navigationController?.pushViewController(ProfileViewController(userKey: fixtureID, fromChat: true), animated: true)
            }
        }
        page.typingTitleText = DemoTypingSubtitle.title
        if !copy.safetyBanner.isEmpty, !DemoChatSession.isBannerDismissed(id) {
            page.topBannerView = safetyBanner(copy.safetyBanner) { [weak page] in
                DemoChatSession.dismissBanner(id)
                page?.topBannerView = nil
            }
        }
        let chipsView: UIView? = copy.quickChips.isEmpty ? nil : chipRow(copy.quickChips) { [weak page] chip in
            guard let page else { return }
            sender.send(key: chip.id, kind: chip.kind, summary: chip.summary,
                        payload: DemoCardRolls.rolled(kind: chip.kind, payload: chip.payload.mapValues { $0.any }),
                        from: page)
        }
        page.footerAccessoryView = chipsView
        if let fixtureID = peerProfile?.fixtureID {
            installIcebreaker(on: page, fixtureID: fixtureID)
        }
        if !quickActions.isEmpty {
            let row = DemoQuickRow(actions: quickActions, showsDot: !DemoChatSession.giftDotSeen)
            row.onTap = { [weak page, weak row] action in
                guard let page, let row else { return }
                if DemoQuickRowPolicy.collapsesPanelFirst(action.id, panel: row.panel) {
                    page.collapseInputPanels()
                }
                switch action.action {
                case "album":
                    if preview {
                        alert(page, DemoText.get("demo_preview_mode_not_logged_in_image_not"))
                    } else {
                        page.pickAlbumAndSend()
                    }
                case "call":
                    chooseCall(page, peer: peer, preview: preview)
                case "card":
                    guard let kind = action.kind else { return }
                    if action.dot == true {
                        DemoChatSession.markGiftDotSeen()
                        row.dismissDot()
                    }
                    sender.send(key: action.id, kind: kind, summary: action.summary ?? DemoText.get("demo_interaction_card"),
                                payload: (action.payload ?? [:]).mapValues { $0.any }, from: page)
                case "gift":
                    if action.dot == true {
                        DemoChatSession.markGiftDotSeen()
                        row.dismissDot()
                    }
                    openGiftPanel(copy: copy, sender: sender, from: page)
                case "emoji":
                    page.toggleEmojiPanel()
                case "more":
                    page.toggleMorePanel()
                default:
                    break
                }
            }
            page.inputBottomAccessoryView = row
            page.onInputPanelChanged = { [weak row] panel in row?.update(panel: panel) }
        }
        return page
    }

    /// S6: the real IM settings (mute / pin / blacklist / clear / background) plus host demo rows.
    /// Ice-breaker card: the first item of the chat (docs/05 §14.166, design board M). Mock data from the peer's fixture
    /// profile only; no IM data. Hidden when the profile is too thin to show.
    private static func installIcebreaker(on page: ChatPage, fixtureID: String) {
        let show: (HomeUserDetail) -> Void = { [weak page] detail in
            guard let page, IcebreakerCard.hasContent(detail) else { return }
            let card = IcebreakerCard.build(detail: detail, actions: IcebreakerCard.Actions(
                onProfile: { [weak page] in
                    page?.navigationController?.pushViewController(ProfileViewController(userKey: fixtureID, fromChat: true), animated: true)
                },
                onAlbum: { [weak page] in
                    page?.navigationController?.pushViewController(AlbumViewController(userKey: fixtureID), animated: true)
                }))
            page.setMessageListHeader(card, heightFraction: 1.0 / 3.0, minHeight: icebreakerMinHeight)
        }
        if let cached = HomeKit.cachedDetail(fixtureID) {
            show(cached)
            return
        }
        HomeKit.dataSource.loadUserDetail(userKey: fixtureID) { result in
            guard case .success(let detail) = result else { return }
            HomeKit.cacheDetail(fixtureID, detail)
            show(detail)
        }
    }

    /// One third of the chat page, but never shorter than 280pt (the tallest content: two-line common box + voice pill).
    private static let icebreakerMinHeight: CGFloat = 280

    private static func openChatSettings(from page: UIViewController, peer: String, copy: DemoChatCopy, preview: Bool) {
        if preview || peer.isEmpty {
            alert(page, preview ? DemoText.get("demo_preview_mode_not_logged_in_cannot_open") : DemoText.get("demo_chat_settings_are_only_available_in_one"))
            return
        }
        let setting = copy.chatSetting
        DemoFriendGate.check(peer: peer) { [weak page] info in
            guard let page else { return }
            let isFriend = info?.isFriend == true
            let controller = C2CChatSettingViewController(
                userID: peer,
                config: C2CChatSettingConfig(
                    isShowRemark: false,
                    isShowSendMessage: false,
                    isShowVoiceCall: false,
                    isShowVideoCall: false,
                    isShowDeleteFriend: false
                ),
                onContactDelete: { [weak page] in
                    // Deleting closes the settings page and the chat itself, back to the list.
                    guard let navigation = page?.navigationController else { return }
                    var stack = navigation.viewControllers
                    if stack.count >= 2 { stack.removeLast(2) }
                    navigation.setViewControllers(stack, animated: true)
                },
                sceneExtras: C2CSceneExtras(
                    profileTagView: { Host.verifiedTag(DemoText.get("demo_verified")) },
                    intimacyLabel: setting?.intimacyLabel ?? DemoText.get("demo_relationship"),
                    intimacyBadge: setting?.intimacyBadge,
                    backgroundLabel: setting?.backgroundLabel ?? DemoText.get("demo_chat_background"),
                    nicknameLabel: setting?.nicknameLabel ?? DemoText.get("demo_custom_nickname"),
                    nicknameValue: setting?.nicknameValue,
                    reportLabel: setting?.reportLabel ?? DemoText.get("demo_report_them"),
                    footer: setting?.footer,
                    onMockRowClick: { [weak page] _ in
                        guard let page else { return }
                        alert(page, setting?.mockNotice ?? DemoText.get("demo_demo_mock_demo_item_no_business_request"))
                    },
                    addFriendLabel: isFriend ? nil : DemoText.get("demo_add_friend"),
                    onAddFriendClick: { DemoFriendGate.add(peer: peer) },
                    deleteFriendLabel: isFriend ? DemoText.get("demo_delete_friend") : nil
                )
            )
            controller.title = setting?.title
            controller.hidesBottomBarWhenPushed = true
            page.navigationController?.pushViewController(controller, animated: true)
        }
    }

    /// Gift chooser: each tap sends one real chat.card gift; combo and hearts are local decoration.
    private static func openGiftPanel(copy: DemoChatCopy, sender: DemoCardSender, from page: UIViewController) {
        guard let panel = copy.giftPanel, !panel.gifts.isEmpty else { return }
        let controller = DemoGiftPanelController(panel: panel) { gift, done in
            sender.send(key: "gift:\(gift.ref)", kind: "gift", summary: DemoText.get("demo_gift"),
                        payload: ["giftRef": gift.ref, "name": gift.name, "quantity": 1,
                                  "displayValue": gift.value, "displayUnit": gift.unit], from: page) { instanceId in
                done(instanceId.map {
                    DemoGiftCombo.register(instanceId: $0, giftRef: gift.ref,
                                           nowMs: Int64(Date().timeIntervalSince1970 * 1000), windowMs: panel.comboWindowMs)
                })
            }
        }
        page.present(controller, animated: false)
    }

    private static func inputAppearance(_ copy: DemoChatCopy) -> MessageInputAppearance {
        MessageInputAppearance(
            fieldBackgroundColor: Palette.input,
            fieldCornerRadius: 18,
            fieldMinHeight: 40,
            placeholder: copy.inputBar?.placeholder,
            placeholderAlignment: .natural,
            audioButtonImage: UIImage(named: "demo_ic_mic"),
            audioButtonActiveImage: UIImage(named: "demo_ic_keyboard"),
            audioButtonTint: Palette.muted,
            audioButtonKeepsColors: true,
            audioButtonSize: 36,
            sendButtonTitle: copy.inputBar?.sendText ?? DemoText.get("demo_send"),
            sendButtonGradient: [Palette.accent, Palette.brandEnd],
            sendButtonHeight: 28,
            sendButtonFont: .adaptiveSystemFont(ofSize: 13, weight: .bold)
        )
    }

    private static func chooseCall(_ page: UIViewController, peer: String, preview: Bool) {
        guard !peer.isEmpty else { alert(page, DemoText.get("demo_audio_and_video_calls_are_only_available")); return }
        let sheet = DemoCallChoiceSheet(
            onVideo: { [weak page] in page.map { startCall($0, peer: peer, mediaType: .video, preview: preview) } },
            onAudio: { [weak page] in page.map { startCall($0, peer: peer, mediaType: .audio, preview: preview) } }
        )
        page.present(sheet, animated: true)
    }

    private static func startCall(_ page: UIViewController, peer: String, mediaType: CallMediaType, preview: Bool) {
        guard !preview else { alert(page, DemoText.get("demo_preview_mode_not_logged_in_cannot_start")); return }
        ChatCallEventPublisher.publishStartCall(
            participantIDs: [peer],
            mediaType: mediaType == .video ? .video : .audio
        )
    }

    fileprivate static func alert(_ page: UIViewController, _ text: String, kind: SocialToast.Kind = .warning) {
        SocialToast.show(text, kind: kind)
    }

    /// Screen-level mock safety tip; not an IM message and never a faked recall.
    /// Same geometry as Android `ChatActivity.safetyBanner`: 14 / 3 / 6 / 3 padding, 18pt warning glyph, 12pt single-line
    /// text with 6pt left padding, 32 x 28 close target holding a small round-capped cross (not a system symbol).
    private static func safetyBanner(_ text: String, onClose: @escaping () -> Void) -> UIView {
        let amber = Host.tokens.textColorWarning
        let bar = UIView()
        bar.backgroundColor = Host.tokens.toastColorWarning
        let icon = BannerGlyph(kind: .warning, color: amber)
        let message = label(text, 12, amber)
        message.numberOfLines = 1
        let close = BannerGlyph(kind: .close, color: amber)
        close.isUserInteractionEnabled = true
        close.isAccessibilityElement = true
        close.accessibilityLabel = DemoText.get("demo_dismiss")
        close.onTap(onClose)
        let row = UIStackView(arrangedSubviews: [icon, message, close])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: bar.topAnchor, constant: 3),
            row.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -3),
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -6),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            close.widthAnchor.constraint(equalToConstant: 32),
            close.heightAnchor.constraint(equalToConstant: 28)
        ])
        message.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return bar
    }

    private static func chipRow(_ chips: [DemoChatCopy.Chip], onTap: @escaping (DemoChatCopy.Chip) -> Void) -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)
        for chip in chips {
            let button = UIButton(type: .custom)
            button.setImage(UIImage(named: chip.icon)?.withRenderingMode(.alwaysOriginal), for: .normal)
            button.setTitle(chip.label, for: .normal)
            button.setTitleColor(Palette.text, for: .normal)
            button.titleLabel?.font = .adaptiveSystemFont(ofSize: 14)
            button.backgroundColor = Palette.surfaceHigh
            button.layer.cornerRadius = 17
            button.layer.borderWidth = 1
            button.layer.borderColor = Palette.stroke.cgColor
            button.imageView?.contentMode = .scaleAspectFit
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -2.5, bottom: 0, right: 2.5)
            button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 2.5, bottom: 0, right: -2.5)
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 11, bottom: 0, right: 13)
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            button.addAction(UIAction { _ in onTap(chip) }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 2),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            scroll.heightAnchor.constraint(equalTo: row.heightAnchor, constant: 6)
        ])
        return scroll
    }
}

/// Answers `DemoChat.replayRequested` for exactly one chat page and unregisters when that page goes away.
private final class DemoReplayObserver {
    private static var attachedKey: UInt8 = 0
    private var token: NSObjectProtocol?

    static func attach(to page: ChatPage, handler: @escaping (String) -> Void) {
        let observer = DemoReplayObserver()
        observer.token = NotificationCenter.default.addObserver(
            forName: DemoChat.replayRequested, object: page, queue: .main) { note in
            if let kind = note.userInfo?["kind"] as? String { handler(kind) }
        }
        objc_setAssociatedObject(page, &attachedKey, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    deinit { token.map { NotificationCenter.default.removeObserver($0) } }
}

/// Sends chips as real IM CUSTOM messages. A failed send keeps its ids so the next
/// tap retries the same interaction instead of creating a new one (spec 03 §3).
private final class DemoCardSender {
    private let store: MessageInputStore
    private let preview: Bool
    private let onSent: () -> Void
    private var pending: [String: (String, String)] = [:]
    private var sending = Set<String>()

    init(conversationID: String, preview: Bool, onSent: @escaping () -> Void) {
        store = MessageInputStore.create(conversationID: conversationID)
        self.preview = preview
        self.onSent = onSent
    }

    /// [key] identifies the entry point (chip or tile) so a retry reuses the same ids.
    func send(key: String, kind: String, summary: String, payload: [String: Any], from page: UIViewController,
              completion: ((String?) -> Void)? = nil) {
        guard !preview else { DemoChat.alert(page, DemoText.get("demo_preview_mode_not_logged_in_interaction_card")); completion?(nil); return }
        guard !sending.contains(key) else { completion?(nil); return }
        let ids = pending[key] ?? (UUID().uuidString, UUID().uuidString)
        guard let data = DemoCardProtocol.build(kind: kind, payload: payload,
                                                instanceId: ids.0, eventId: ids.1) else {
            DemoChat.alert(page, DemoText.get("demo_this_interaction_card_format_is_not_supported"))
            completion?(nil)
            return
        }
        sending.insert(key)
        store.sendMessage(payload: .custom(CustomSendMessagePayload(customData: data, description: summary,
                                                                    extensionInfo: nil)),
                          option: nil) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    if case .failure = result {
                        SocialToast.show(DemoText.get("demo_send_failed_tap_again_to_retry_the"), kind: .error)
                    }
                    return
                }
                self.sending.remove(key)
                switch result {
                case .success:
                    self.pending[key] = nil
                    self.onSent()
                    completion?(ids.0)
                case .failure(let error):
                    self.pending[key] = ids
                    HostDiagnostics.record("chat.sendCard", code: error.code, message: error.message)
                    SocialToast.show(DemoText.get("demo_send_failed_tap_again_to_retry_the"), kind: .error)
                    completion?(nil)
                }
            }
        }
    }
}

enum DemoCallGift {
    private static let giftRef = "star_candy"
    private static var stores: [String: MessageInputStore] = [:]

    static func install() {
        CallGiftBridge.sender = { peerId, onResult in
            DispatchQueue.main.async {
                let gifts = DemoChatCopy.load().giftPanel?.gifts ?? []
                guard let gift = gifts.first(where: { $0.ref == giftRef }) ?? gifts.first,
                      let data = DemoCardProtocol.build(kind: "gift", payload: [
                          "giftRef": gift.ref, "name": gift.name, "quantity": 1,
                          "displayValue": gift.value, "displayUnit": gift.unit
                      ]) else { onResult(false); return }
                let conversationID = "c2c_\(peerId)"
                let store = stores[conversationID] ?? MessageInputStore.create(conversationID: conversationID)
                stores[conversationID] = store
                store.sendMessage(payload: .custom(CustomSendMessagePayload(customData: data, description: DemoText.get("demo_gift"),
                                                                            extensionInfo: nil)),
                                  option: nil) { result in
                    DispatchQueue.main.async {
                        if case .success = result { onResult(true) } else { onResult(false) }
                    }
                }
            }
        }
        CallGiftBridge.inspector = { customData in
            guard let card = DemoCardProtocol.parse(customData), card.kind == "gift" else { return nil }
            return card.payload["name"] ?? ""
        }
    }
}

enum DemoQuickRowPolicy {
    static func isOn(_ actionID: String, panel: MessageInputPanel) -> Bool {
        switch actionID {
        case "more": return panel == .more
        case "emoji": return panel == .emoji
        default: return false
        }
    }

    static func collapsesPanelFirst(_ actionID: String, panel: MessageInputPanel) -> Bool {
        let panelOpen = panel == .more || panel == .emoji
        return panelOpen && actionID != "more" && actionID != "emoji"
    }

    static func iconState(_ actionID: String, panel: MessageInputPanel) -> String {
        actionID == "more" && panel == .more ? "on" : "off"
    }
}

final class DemoQuickRow: UIView {
    var onTap: ((DemoChatCopy.QuickAction) -> Void)?

    private(set) var panel: MessageInputPanel = .none

    private struct Slot {
        let action: DemoChatCopy.QuickAction
        let circle: UIView
        let icon: UIImageView
    }

    private var slots: [Slot] = []

    private var dot: UIView?

    init(actions: [DemoChatCopy.QuickAction], showsDot: Bool) {
        super.init(frame: .zero)
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.heightAnchor.constraint(equalToConstant: 54)
        ])
        for action in actions {
            stack.addArrangedSubview(item(for: action, showsDot: showsDot))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(panel: MessageInputPanel) {
        self.panel = panel
        for slot in slots {
            let on = DemoQuickRowPolicy.isOn(slot.action.id, panel: panel)
            slot.circle.backgroundColor = on ? Palette.accent.withAlphaComponent(0.2) : .clear
            let name = DemoQuickRowPolicy.iconState(slot.action.id, panel: panel) == "on"
                ? (slot.action.iconOn ?? slot.action.icon) : slot.action.icon
            UIView.transition(with: slot.icon, duration: 0.18, options: .transitionCrossDissolve) {
                slot.icon.image = UIImage(named: name)
            }
        }
    }

    func dismissDot() {
        dot?.isHidden = true
    }

    private func item(for action: DemoChatCopy.QuickAction, showsDot: Bool) -> UIView {
        let control = UIControl()
        control.isAccessibilityElement = true
        control.accessibilityLabel = action.label
        control.accessibilityTraits = .button
        control.addAction(UIAction { [weak self] _ in self?.onTap?(action) }, for: .touchUpInside)
        if action.primary == true {
            let tile = UIView()
            tile.isUserInteractionEnabled = false
            tile.translatesAutoresizingMaskIntoConstraints = false
            tile.layer.cornerRadius = 14.5
            tile.layer.shadowColor = Palette.brandEnd.cgColor
            tile.layer.shadowOpacity = 0.5
            tile.layer.shadowRadius = 6
            tile.layer.shadowOffset = CGSize(width: 0, height: 5)
            tile.layer.shadowPath = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 44, height: 44),
                                                 cornerRadius: 14.5).cgPath
            let base = CAGradientLayer()
            base.colors = [Palette.accent.cgColor, Palette.brandEnd.cgColor]
            base.locations = [0, 0.71]
            base.startPoint = CGPoint(x: 0, y: 0)
            base.endPoint = CGPoint(x: 1, y: 1)
            let shine = CAGradientLayer()
            shine.colors = [UIColor.white.withAlphaComponent(0.24).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            shine.locations = [0, 0.52]
            for layer in [base, shine] {
                layer.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
                layer.cornerRadius = 14.5
                layer.masksToBounds = true
                tile.layer.addSublayer(layer)
            }
            shine.borderWidth = 1
            shine.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
            let icon = UIImageView(image: UIImage(named: action.icon))
            icon.translatesAutoresizingMaskIntoConstraints = false
            tile.addSubview(icon)
            control.addSubview(tile)
            NSLayoutConstraint.activate([
                tile.centerXAnchor.constraint(equalTo: control.centerXAnchor),
                tile.centerYAnchor.constraint(equalTo: control.centerYAnchor),
                tile.widthAnchor.constraint(equalToConstant: 44),
                tile.heightAnchor.constraint(equalToConstant: 44),
                icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 28),
                icon.heightAnchor.constraint(equalToConstant: 28)
            ])
            if action.dot == true, showsDot {
                let badge = UIView()
                badge.translatesAutoresizingMaskIntoConstraints = false
                badge.backgroundColor = Host.unreadAccent
                badge.layer.cornerRadius = 4.5
                badge.layer.borderWidth = 1.5
                badge.layer.borderColor = Palette.bar.cgColor
                tile.addSubview(badge)
                NSLayoutConstraint.activate([
                    badge.widthAnchor.constraint(equalToConstant: 9),
                    badge.heightAnchor.constraint(equalToConstant: 9),
                    badge.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -2),
                    badge.topAnchor.constraint(equalTo: tile.topAnchor, constant: -1)
                ])
                dot = badge
            }
        } else {
            let circle = UIView()
            circle.isUserInteractionEnabled = false
            circle.translatesAutoresizingMaskIntoConstraints = false
            circle.layer.cornerRadius = 20
            let icon = UIImageView(image: UIImage(named: action.icon))
            icon.translatesAutoresizingMaskIntoConstraints = false
            circle.addSubview(icon)
            control.addSubview(circle)
            NSLayoutConstraint.activate([
                circle.centerXAnchor.constraint(equalTo: control.centerXAnchor),
                circle.centerYAnchor.constraint(equalTo: control.centerYAnchor),
                circle.widthAnchor.constraint(equalToConstant: 40),
                circle.heightAnchor.constraint(equalToConstant: 40),
                icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 32),
                icon.heightAnchor.constraint(equalToConstant: 32)
            ])
            slots.append(Slot(action: action, circle: circle, icon: icon))
        }
        return control
    }
}

/// Warning triangle / close cross drawn like Android `DemoGlyph` (same proportions and 1.8pt round-capped stroke).
private final class BannerGlyph: UIView {
    enum Kind { case warning, close }
    private let kind: Kind
    private let color: UIColor

    init(kind: Kind, color: UIColor) {
        self.kind = kind
        self.color = color
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let cx = bounds.midX, cy = bounds.midY
        let s = min(bounds.width, bounds.height) * (kind == .warning ? 0.42 : 0.21)
        switch kind {
        case .warning:
            color.setFill()
            let triangle = UIBezierPath()
            triangle.move(to: CGPoint(x: cx, y: cy - s))
            triangle.addLine(to: CGPoint(x: cx + s * 1.05, y: cy + s * 0.85))
            triangle.addLine(to: CGPoint(x: cx - s * 1.05, y: cy + s * 0.85))
            triangle.close()
            triangle.fill()
            let ink = Host.tokens.toastColorWarning
            ink.setStroke()
            let mark = UIBezierPath()
            mark.lineWidth = 1.8
            mark.lineCapStyle = .round
            mark.move(to: CGPoint(x: cx, y: cy - s * 0.35))
            mark.addLine(to: CGPoint(x: cx, y: cy + s * 0.25))
            mark.stroke()
            ink.setFill()
            UIBezierPath(arcCenter: CGPoint(x: cx, y: cy + s * 0.55), radius: 1.08, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
        case .close:
            color.setStroke()
            let k = s * 0.7
            let cross = UIBezierPath()
            cross.lineWidth = 1.8
            cross.lineCapStyle = .round
            cross.move(to: CGPoint(x: cx - k, y: cy - k))
            cross.addLine(to: CGPoint(x: cx + k, y: cy + k))
            cross.move(to: CGPoint(x: cx + k, y: cy - k))
            cross.addLine(to: CGPoint(x: cx - k, y: cy + k))
            cross.stroke()
        }
    }
}


/// Full screen look at one card photo (an asset name or an http url); it grows out of the tapped tile and shrinks back into it.
final class DemoPhotoPreviewController: UIViewController {
    private let ref: String
    private let sourceFrame: CGRect
    private let image = UIImageView()
    private var closing = false

    static func present(ref: String, source: UIView) {
        guard let window = source.window else { return }
        let frame = source.convert(source.bounds, to: window)
        var responder: UIResponder? = source
        while let current = responder {
            if let controller = current as? UIViewController {
                var top = controller
                while let presented = top.presentedViewController { top = presented }
                top.present(DemoPhotoPreviewController(ref: ref, sourceFrame: frame), animated: true)
                return
            }
            responder = current.next
        }
    }

    init(ref: String, sourceFrame: CGRect) {
        self.ref = ref
        self.sourceFrame = sourceFrame
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        image.contentMode = .scaleAspectFit
        image.translatesAutoresizingMaskIntoConstraints = false
        HostImage.bind(image, ref: ref)
        view.addSubview(image)
        Host.pin(image, to: view)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        view.accessibilityViewIsModal = true
    }

    override var prefersStatusBarHidden: Bool { true }

    private func collapsedTransform() -> CGAffineTransform {
        let bounds = view.bounds
        guard bounds.width > 0 else { return .identity }
        let scale = sourceFrame.width / bounds.width
        return CGAffineTransform(translationX: sourceFrame.midX - bounds.midX, y: sourceFrame.midY - bounds.midY).scaledBy(x: scale, y: scale)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.layoutIfNeeded()
        image.transform = collapsedTransform()
        let expand = { self.image.transform = .identity }
        if let coordinator = transitionCoordinator {
            coordinator.animate(alongsideTransition: { _ in expand() })
        } else {
            expand()
        }
    }

    @objc private func close() {
        guard !closing else { return }
        closing = true
        UIView.animate(withDuration: 0.26, delay: 0, options: [.curveEaseOut]) {
            self.image.transform = self.collapsedTransform()
            self.view.backgroundColor = .clear
        } completion: { _ in
            self.dismiss(animated: false)
        }
    }
}

/// Bottom call chooser, same layout on every iOS version (mirrors Android `CallChoiceDialog`): a rounded group with
/// video / voice rows, an 8pt gap, then a separate cancel card. Never an `UIAlertController` action sheet, which iOS
/// presents differently from one release to the next.
final class DemoCallChoiceSheet: UIViewController {
    private static let rowHeight: CGFloat = 56
    private static let corner: CGFloat = 14
    private static let inset: CGFloat = 8

    private let onVideo: () -> Void
    private let onAudio: () -> Void
    private let column = UIStackView()

    init(onVideo: @escaping () -> Void, onAudio: @escaping () -> Void) {
        self.onVideo = onVideo
        self.onAudio = onAudio
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let tokens = Host.tokens
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        let backdropTap = UITapGestureRecognizer(target: self, action: #selector(close))
        backdropTap.delegate = self
        view.addGestureRecognizer(backdropTap)

        let group = UIStackView()
        group.axis = .vertical
        group.backgroundColor = tokens.bgColorDialog
        group.layer.cornerRadius = Self.corner
        group.clipsToBounds = true
        group.addArrangedSubview(row(DemoText.get("demo_video_call"), color: tokens.textColorLink, bold: false) { [weak self] in
            self?.dismiss(animated: true) { self?.onVideo() }
        })
        group.addArrangedSubview(divider(tokens.strokeColorSecondary))
        group.addArrangedSubview(row(DemoText.get("demo_voice_call"), color: tokens.textColorLink, bold: false) { [weak self] in
            self?.dismiss(animated: true) { self?.onAudio() }
        })
        let cancel = row(DemoText.get("demo_cancel"), color: tokens.textColorPrimary, bold: true) { [weak self] in self?.close() }
        cancel.backgroundColor = tokens.bgColorDialog
        cancel.layer.cornerRadius = Self.corner
        cancel.clipsToBounds = true

        column.axis = .vertical
        column.spacing = Self.inset
        column.translatesAutoresizingMaskIntoConstraints = false
        column.addArrangedSubview(group)
        column.addArrangedSubview(cancel)
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.inset),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.inset),
            column.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Self.inset)
        ])
    }

    @objc private func close() { dismiss(animated: true) }

    private func divider(_ color: UIColor) -> UIView {
        let line = UIView()
        line.backgroundColor = color
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return line
    }

    private func row(_ title: String, color: UIColor, bold: Bool, action: @escaping () -> Void) -> UIControl {
        let control = UIControl()
        control.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityLabel = title
        let label = UILabel()
        label.text = title
        label.font = .adaptiveSystemFont(ofSize: 17, weight: bold ? .bold : .regular)
        label.textColor = color
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        control.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: control.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: control.centerYAnchor)
        ])
        control.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return control
    }
}

extension DemoCallChoiceSheet: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view === view
    }
}

enum DemoTypingSubtitle {
    static var title: String { DemoText.get("demo_typing_now") }
}
