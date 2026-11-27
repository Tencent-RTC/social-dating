//
//  SwiftLoad.swift
//  TUICallKit
//
//  Created by WesleyLei on 2022/9/23.
//  Copyright © 2022 Tencent. All rights reserved.
//

import Foundation
import UIKit
import Combine
import TUICore
import AtomicXCore
import AtomicX

extension NSObject {
    @objc class func swiftLoad() {
        // Runs from +load, before UIApplicationMain: LoginStore is only touched once launch has finished.
        CallKitLoginBridge.startAfterLaunch()

        ChatCallEventSubscriber.shared.ensureSubscribed()

        TUICore.registerService(TUICore_TUICallingService, object: TUICallKitService.instance)
        
        TUICore.registerService(TUICore_TUIAudioMessageRecordService, object: TUIAudioMessageRecordService.instance)
        
        TUICore.registerExtension(TUICore_TUIChatExtension_NavigationMoreItem_MinimalistExtensionID,
                                  object: TUICallKitExtension.instance)
        TUICore.registerExtension(TUICore_TUIChatExtension_InputViewMoreItem_ClassicExtensionID,
                                  object: TUICallKitExtension.instance)
        TUICore.registerExtension(TUICore_TUIContactExtension_FriendProfileActionMenu_ClassicExtensionID,
                                  object: TUICallKitExtension.instance)
        TUICore.registerExtension(TUICore_TUIContactExtension_FriendProfileActionMenu_MinimalistExtensionID,
                                  object: TUICallKitExtension.instance)
        TUICore.registerExtension(TUICore_TUIContactExtension_GroupInfoCardActionMenu_MinimalistExtensionID,
                                  object: TUICallKitExtension.instance)
        
        TUICore.registerExtension(TUICore_TUIChatExtension_ChatViewTopArea_ClassicExtensionID,
                                  object: TUICallKitExtension.instance)
        TUICore.registerExtension(TUICore_TUIChatExtension_ChatViewTopArea_MinimalistExtensionID,
                                  object: TUICallKitExtension.instance)
        
        TUICore.registerObjectFactory(TUICore_TUICallingObjectFactory, objectFactory: TUICallKitObjectFactory.instance)
        
        TUIThemeManager.share().registerThemeResourcePath(TUICoreDefineConvert.getTUICallKitThemePath(), for: .calling)
    }
}

/// Connects CallKit to AtomicXCore `LoginStore` instead of TUILogin notifications.
///
/// The app signs in through `LoginStore` only, and TUILogin notifications are posted by TUILogin itself, so
/// `TUIInitSdkSuccess` / `TUILoginSuccess` / `TUILogoutSuccess` never arrive. On `.logined` the CallKit
/// singleton is created right away, so it is subscribed to `CallStore.callEventPublisher` (which does not
/// replay past events) before the app finishes initializing the call engine and the first invitation is
/// delivered. Logout, kick-off and userSig expiry end the session; the initial `.unlogin` value is ignored.
/// The call engine itself is still initialized by the app, which is the only one holding the userSig.
final class CallKitLoginBridge {
    static let shared = CallKitLoginBridge()

    private var cancellables = Set<AnyCancellable>()
    private var launchObserver: NSObjectProtocol?
    private var logined = false

    static func startAfterLaunch() {
        guard shared.launchObserver == nil, shared.cancellables.isEmpty else { return }
        shared.launchObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { _ in
            shared.start()
        }
    }

    func start() {
        if let observer = launchObserver {
            NotificationCenter.default.removeObserver(observer)
            launchObserver = nil
        }
        guard cancellables.isEmpty else { return }
        LoginStore.shared.state
            .subscribe(StatePublisherSelector(keyPath: \LoginState.loginStatus))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.update(isLogined: status == .logined)
            }
            .store(in: &cancellables)
        LoginStore.shared.loginEventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // .kickedOffline / .loginExpired: the session is over even if the status lags behind.
                self?.update(isLogined: false)
            }
            .store(in: &cancellables)
    }

    private func update(isLogined: Bool) {
        if isLogined {
            guard !logined else { return }
            logined = true
            TUICallKit.createInstance()
            TUICallKitImpl.shared.handleLogin()
            TUIAudioMessageRecordService.instance.handleLogin()
        } else {
            guard logined else { return }
            logined = false
            TUICallKitImpl.shared.handleLogout()
        }
    }
}
