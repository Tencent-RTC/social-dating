import UIKit
import AudioToolbox
import AtomicXCore
import ImSDK_Plus
import TUIChatKit
import TUIHostBase
import AtomicX
import Foundation

final class DemoMessageBanner: NSObject, V2TIMAdvancedMsgListener {
    static let shared = DemoMessageBanner()

    private static let settle: TimeInterval = 0.12
    private static let receivedSound: SystemSoundID = 1007
    private static let c2cPrefix = "c2c_"

    private struct Arrival {
        let conversationID: String
        let message: MessageInfo
    }

    private var account: String?
    private var listening = false
    private var pending: [String: Arrival] = [:]
    private var flushWork: DispatchWorkItem?
    private let detector = DemoBannerDetector()

    var onShown: (() -> Void)?

    func ensureStarted(accountId: String) {
        if listening, account == accountId { return }
        stop()
        account = accountId
        detector.reset()
        listening = true
        V2TIMManager.sharedInstance().addAdvancedMsgListener(listener: self)
    }

    func stop() {
        if listening { V2TIMManager.sharedInstance().removeAdvancedMsgListener(listener: self) }
        listening = false
        account = nil
        flushWork?.cancel()
        flushWork = nil
        pending.removeAll()
        detector.reset()
        MsgBanner.hide()
    }

    func onRecvNewMessage(msg: V2TIMMessage) {
        DispatchQueue.main.async { [weak self] in self?.received(msg) }
    }

    private func received(_ msg: V2TIMMessage) {
        guard listening, !DemoHostSession.preview else { return }
        let peer = msg.userID ?? ""
        let isC2C = (msg.groupID ?? "").isEmpty && !peer.isEmpty
        let conversationID = isC2C ? Self.c2cPrefix + peer : ""
        let info = ChatUtil.convertToMessageInfo(rawMessage: msg)
        guard !ConversationBannerSummary.isCallMessage(info) else { return }
        let incoming = DemoBannerIncoming(
            messageID: msg.msgID ?? "",
            conversationID: conversationID,
            isC2C: isC2C,
            isSelf: msg.isSelf,
            timestampSeconds: Int64(msg.timestamp?.timeIntervalSince1970 ?? 0),
            excludedFromUnread: msg.isExcludedFromUnreadCount,
            isTyping: ConversationBannerSummary.isTypingMessage(info)
        )
        guard detector.accept(incoming) else { return }
        pending[conversationID] = Arrival(conversationID: conversationID, message: info)
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushPending() }
        flushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle, execute: work)
    }

    private func flushPending() {
        let batch = pending.values.sorted { ($0.message.timestamp ?? 0) < ($1.message.timestamp ?? 0) }
        pending.removeAll()
        for arrival in batch {
            V2TIMManager.sharedInstance().getConversation(conversationID: arrival.conversationID, succ: { [weak self] conversation in
                guard let conversation else { return }
                DispatchQueue.main.async { self?.present(arrival, conversation) }
            }, fail: { code, desc in
                HostDiagnostics.record("banner.conversation", code: Int(code), message: desc ?? "")
            })
        }
    }

    private func present(_ arrival: Arrival, _ conversation: V2TIMConversation) {
        guard listening, !DemoHostSession.preview, MsgBanner.isForeground else { return }
        guard ChatUtil.convertToReceiveMessageOpt(conversation.recvOpt) == .receive else { return }
        if let page = Self.topController() as? ChatPage, page.conversationID == arrival.conversationID { return }
        if CallStore.shared.state.value.selfInfo.status != .none { return }
        let summary = ConversationBannerSummary.text(forMessage: arrival.message)
        guard !summary.isEmpty else { return }
        let peerID = String(arrival.conversationID.dropFirst(Self.c2cPrefix.count))
        let title = (conversation.showName?.isEmpty == false ? conversation.showName : nil)
            ?? DemoPeerProfiles.forUser(peerID)?.name ?? peerID
        let rich = ConversationBannerSummary.attributedText(forMessage: arrival.message, font: .adaptiveSystemFont(ofSize: 13),
                                                            color: Host.tokens.textColorSecondary)
        let model = MsgBanner.Model(key: arrival.conversationID, title: title, summary: summary, attributedSummary: rich,
                                    time: DemoText.get("demo_just_now"), avatar: conversation.faceUrl)
        let shown = MsgBanner.show(model) {
            (UIApplication.shared.delegate as? AppDelegate)?.openChat(userID: peerID, title: title)
        }
        guard shown else { return }
        onShown?()
        alert()
    }

    private func alert() {
        guard HostNotifyPrefs.messageAlerts else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        AudioServicesPlaySystemSound(Self.receivedSound)
    }

    private static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while true {
            if let nav = top as? UINavigationController, let visible = nav.visibleViewController, visible !== nav {
                top = visible
            } else if let tabs = top as? UITabBarController, let selected = tabs.selectedViewController {
                top = selected
            } else if let presented = top?.presentedViewController {
                top = presented
            } else {
                break
            }
        }
        return top
    }
}

struct DemoBannerIncoming: Equatable {
    let messageID: String
    let conversationID: String
    let isC2C: Bool
    let isSelf: Bool
    let timestampSeconds: Int64
    let excludedFromUnread: Bool
    let isTyping: Bool
}

final class DemoBannerDetector {
    static let maxAgeSeconds: Int64 = 20
    static let memory = 64

    private let now: () -> TimeInterval
    private let maxAge: Int64
    private let memory: Int
    private var order: [String] = []
    private var seen = Set<String>()

    init(now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
         maxAge: Int64 = DemoBannerDetector.maxAgeSeconds,
         memory: Int = DemoBannerDetector.memory) {
        self.now = now
        self.maxAge = maxAge
        self.memory = memory
    }

    func reset() {
        order.removeAll()
        seen.removeAll()
    }

    func accept(_ incoming: DemoBannerIncoming) -> Bool {
        guard !incoming.messageID.isEmpty, seen.insert(incoming.messageID).inserted else { return false }
        order.append(incoming.messageID)
        while order.count > memory { seen.remove(order.removeFirst()) }
        guard isWorthy(incoming) else { return false }
        return Int64(now()) - incoming.timestampSeconds <= maxAge
    }

    private func isWorthy(_ m: DemoBannerIncoming) -> Bool {
        m.isC2C && !m.conversationID.isEmpty && !m.isSelf && !m.excludedFromUnread && !m.isTyping
    }
}
