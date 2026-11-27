import UIKit
import Combine
import AtomicXCore
import TUIChatKit
import TUICallKit
import TUIHomeKit
import TUIMineKit
import TUIHostBase

enum DemoHostSession {
    static var accountId = ""
    static var preview = false
}

final class DemoChatThemeBridge: HostThemeBridge {
    func apply(mode: DemoThemeCoordinator.Mode, palette: String) {
        let chat: TUIChatKit.ThemeMode
        switch mode {
        case .system: chat = .system
        case .light: chat = .light
        case .dark: chat = .dark
        }
        TUIChatKit.ThemeState.shared.setThemeMode(chat)
        TUIChatKit.ThemeState.shared.setPalette(palette)
    }
}

private func toast(_ text: String, on controller: UIViewController, kind: SocialToast.Kind = .default) {
    SocialToast.show(text, kind: kind)
}

final class DemoHomeActions: HomeActions {
    func addFriend(from controller: UIViewController, user: HomeUserCard, completion: @escaping (FriendAddOutcome) -> Void) {
        guard !user.userId.isEmpty else { return completion(.failed) }
        DemoFriendGate.add(peer: user.userId, completion: completion)
    }

    func isFriend(user: HomeUserCard, completion: @escaping (Bool) -> Void) {
        DemoFriendGate.check(peer: user.userId) { completion($0?.isFriend == true) }
    }

    func deleteFriend(from controller: UIViewController, user: HomeUserCard, completion: @escaping (Bool) -> Void) {
        guard !user.userId.isEmpty else { return completion(false) }
        DemoFriendGate.delete(peer: user.userId) { deleted in
            if deleted {
                toast(DemoText.get("demo_friend_deleted"), on: controller, kind: .success)
            } else {
                toast(DemoText.get("demo_delete_friend_failed"), on: controller, kind: .error)
            }
            completion(deleted)
        }
    }

    func openChat(from controller: UIViewController, user: HomeUserCard) {
        resolvePeer(from: controller, user: user, onCancel: {}) { [weak self, weak controller] peer in
            guard let controller else { return }
            DemoGroupWatcher.shared.noteReplied("c2c_\(peer)")
            self?.openChat(from: controller, peer: peer, user: user)
        }
    }

    func videoChat(from controller: UIViewController, user: HomeUserCard) {
        resolvePeer(from: controller, user: user, onCancel: {}) { peer in
            ChatCallEventPublisher.publishStartCall(participantIDs: [peer], mediaType: .video)
        }
    }

    func voiceSignatureTapped(from controller: UIViewController, user: HomeUserCard) {
        toast(DemoText.get("demo_the_voice_signature_is_a_demo_no"), on: controller)
    }

    func moreTapped(from controller: UIViewController, user: HomeUserCard) {
        toast(DemoText.get("demo_more_report_block_are_demo_entries_and"), on: controller)
    }

    func albumPhotoTapped(from controller: UIViewController, user: HomeUserCard, photo: String) {
        toast(DemoText.get("demo_demo_album_design_sample_images_only"), on: controller)
    }

    func commentTapped(from controller: UIViewController, user: HomeUserCard, post: HomeProfilePost) {
        toast(DemoText.get("demo_comment_demo_placeholder"), on: controller)
    }

    private func resolvePeer(from controller: UIViewController, user: HomeUserCard, onCancel: @escaping () -> Void,
                             then: @escaping (String) -> Void) {
        if !user.userId.isEmpty { return then(user.userId) }
        let alert = UIAlertController(title: DemoText.get("demo_demo_account_not_configured"),
                                      message: DemoText.get("demo_demo_mock_is_a_local_mock_person_2", "\(user.displayName)"),
                                      preferredStyle: .alert)
        alert.addTextField { $0.placeholder = DemoText.get("demo_real_test_userid"); $0.autocorrectionType = .no }
        alert.addAction(UIAlertAction(title: DemoText.get("demo_cancel"), style: .cancel) { _ in onCancel() })
        alert.addAction(UIAlertAction(title: DemoText.get("demo_bind_and_chat"), style: .default) { [weak alert] _ in
            guard let peer = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !peer.isEmpty, peer != DemoHostSession.accountId else { return onCancel() }
            then(peer)
        })
        controller.present(alert, animated: true)
    }

    private func openChat(from controller: UIViewController, peer: String, user: HomeUserCard) {
        var info = ConversationInfo(conversationID: "c2c_\(peer)")
        info.type = .c2c
        info.title = user.displayName
        let subtitle = DemoPeerProfiles.subtitle(city: user.city, height: user.height, age: user.age)
        controller.navigationController?.pushViewController(DemoChat.makePage(conversation: info, subtitle: subtitle, onBack: { [weak controller] in
            controller?.navigationController?.popViewController(animated: true)
        }), animated: true)
    }
}

final class DemoMineActions: MineActions {
    func walletTapped(from controller: UIViewController) {
        toast(DemoText.get("demo_wallet_balance_and_top_up"), on: controller)
    }

    func menuItemTapped(from controller: UIViewController, item: MineMenuItem) {
        toast(item.title, on: controller)
    }

    func editProfileTapped(from controller: UIViewController) -> Bool {
        guard DemoHostSession.preview else { return true }
        toast(DemoText.get("demo_edit_profile_needs_login"), on: controller, kind: .warning)
        return false
    }

    func isLogoutAvailable() -> Bool { !DemoHostSession.preview }

    func showLanguagePicker(from controller: UIViewController) {
        controller.present(LoginLanguageSheet(), animated: true)
    }

    func showAppearancePicker(from controller: UIViewController) {
        controller.present(LoginAppearanceSheet(), animated: true)
    }

    func showFriendAddRulePicker(from controller: UIViewController, completion: @escaping () -> Void) {
        let sheet = FriendAddRuleSheet()
        sheet.onApplied = completion
        controller.present(sheet, animated: true)
    }

    /// Signs out of IM first; only when that succeeds is the local session dropped and the login page shown.
    func logoutConfirmed(from controller: UIViewController) {
        LoginStore.shared.logout { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    Self.endSession()
                case .failure(let error):
                    HostDiagnostics.record("mine.logout", code: error.code, message: error.message)
                    toast(DemoText.get("demo_log_out_failed"), on: controller, kind: .error)
                }
            }
        }
    }
}

extension DemoMineActions {
    static func endSession(notice: String? = nil) {
        DemoMessageBanner.shared.stop()
        DemoBadgeCenter.shared.stop()
        DemoCallPromoter.shared.stop()
        DemoGroupWatcher.shared.stop()
        DemoHostSession.accountId = ""
        DemoHostSession.preview = false
        (UIApplication.shared.delegate as? AppDelegate)?.showLogin(afterLogout: true, notice: notice)
    }
}

final class DemoSessionWatcher {
    static let shared = DemoSessionWatcher()

    private var cancellable: AnyCancellable?

    func install() {
        guard cancellable == nil else { return }
        cancellable = LoginStore.shared.loginEventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                switch event {
                case .kickedOffline:
                    self?.end(reason: "kicked", messageKey: "demo_session_kicked_offline")
                case .loginExpired:
                    self?.end(reason: "expired", messageKey: "demo_session_expired")
                }
            }
    }

    private func end(reason: String, messageKey: String) {
        guard !DemoHostSession.preview, !DemoHostSession.accountId.isEmpty else { return }
        HostDiagnostics.record("session.\(reason)", code: 0, message: DemoHostSession.accountId)
        DemoMineActions.endSession(notice: DemoText.get(messageKey))
    }
}

enum DemoFriendGate {
    private static let errNeedConfirm = 30539

    static func check(peer: String, completion: @escaping (ContactInfo?) -> Void) {
        guard !peer.isEmpty else { return completion(nil) }
        ContactStore.shared.getContactInfo(userIDList: [peer], completion: FriendInfoHandler(completion: completion))
    }

    /// One-tap friend request: no remark, fixed verification wording; toasts the outcome here.
    static func add(peer: String, completion: @escaping (FriendAddOutcome) -> Void = { _ in }) {
        guard !peer.isEmpty else {
            SocialToast.show(DemoText.get("demo_friend_request_failed"), kind: .error)
            return completion(.failed)
        }
        ContactStore.shared.addFriend(userID: peer, remark: nil,
                                       addWording: DemoText.get("demo_friend_request_wording")) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    SocialToast.show(DemoText.get("demo_friend_added"), kind: .success)
                    completion(.added)
                case .failure(let error):
                    if error.code == errNeedConfirm {
                        SocialToast.show(DemoText.get("demo_friend_request_sent"), kind: .success)
                        completion(.pending)
                    } else {
                        HostDiagnostics.record("friend.add", code: error.code, message: error.message)
                        SocialToast.show(DemoText.get("demo_friend_request_failed"), kind: .error)
                        completion(.failed)
                    }
                }
            }
        }
    }

    static func delete(peer: String, completion: @escaping (Bool) -> Void) {
        guard !peer.isEmpty else { return completion(false) }
        ContactStore.shared.deleteFriend(userID: peer) { result in
            DispatchQueue.main.async {
                if case .success = result {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }
}

private final class FriendInfoHandler: GetContactInfoCompletionHandler {
    private let completion: (ContactInfo?) -> Void

    init(completion: @escaping (ContactInfo?) -> Void) {
        self.completion = completion
    }

    func onSuccess(contactInfoList: [ContactInfo]) {
        let info = contactInfoList.first
        DispatchQueue.main.async { self.completion(info) }
    }

    func onFailure(code: Int, desc: String) {
        DispatchQueue.main.async { self.completion(nil) }
    }
}
