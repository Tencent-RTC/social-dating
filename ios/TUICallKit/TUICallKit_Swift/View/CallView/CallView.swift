//
//  CallView.swift
//  Pods
//
//  Created by vincepzhang on 2025/2/21.
//

import UIKit
import AtomicX
import SnapKit
import AtomicXCore
import Combine
import RTCRoomEngine
import SDWebImage
import Foundation

public enum Feature: String {
    case aiTranscriber = "aiTranscriber"
    case virtualBackground = "virtualBackground"
}

public class CallView: UIView, UIGestureRecognizerDelegate {
    // MARK: - Init
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        multiCallControlsView.delegate = self
        setupCoreViewStaticResources()
        subscribeCallState()
        updateControlsView()
        updateBackgroundAvatar()
        let blankTap = UITapGestureRecognizer(target: self, action: #selector(handleBlankTap))
        blankTap.cancelsTouchesInView = false
        blankTap.delegate = self
        addGestureRecognizer(blankTap)
    }

    @objc private func handleBlankTap() {
        guard CallStore.shared.state.value.activeCall.mediaType == .video else { return }
        singleCallControlsView.toggleControls()
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view: UIView? = touch.view
        while let current = view, current !== self {
            if current is UIControl { return false }
            if let recognizers = current.gestureRecognizers, !recognizers.isEmpty { return false }
            view = current.superview
        }
        return true
    }
    
    public func disableFeatures(_ features: [Feature]?) {
        guard let features = features else { return }
        if features.contains(.aiTranscriber) {
            callTranscriberView.isEnabled = false
        }
        if features.contains(.virtualBackground) {
            singleCallControlsView.enableVirtualBackground = false
            multiCallControlsView.enableVirtualBackground = false
        }
    }

    func playEndHintTransition(text: String, onComplete: @escaping () -> Void) {
        freezeContentForEnd()
        hideSDKNicknameBars()
        hintView.isHidden = false
        hintView.playEndCallTransition(text: text, onComplete: onComplete)
    }

    func cancelEndHintTransition() {
        hintView.cancelEndCallTransition()
        unfreezeContentAfterEnd()
    }
    
    // MARK: - Private
    private let timerView = TimerView(frame: .zero)
    private let hintView = HintView(frame: .zero)
    private let callCoreView = CallCoreView(frame: .zero)
    private let aiSubtitle = AISubtitle(frame: .zero)
    private let callTranscriberView = CallTranscriberView(frame: .zero)
    private let waitingParticipantsView = WaitingParticipantsView(frame: .zero)
    private let skinHub = CallSkinHub()
    private lazy var singleCallControlsView = SingleCallControlsView(hub: skinHub)
    private var skinLayer: CallSkinLayerView?
    private var skinShade: UIView?
    private var effectsPanel: CallEffectsPanel?
    private let multiCallControlsView = MultiCallControlsView(frame: .zero)
    private var multiCallControlsHeight: CGFloat = CallConstants.groupFunctionViewHeight
    
    private lazy var backgroundAvatarView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        return imageView
    }()
    
    private lazy var backgroundBlurView: UIVisualEffectView = {
        return UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    }()
    
    private var isViewReady = false
    private var isGroupCallSession = false
    private var isContentFrozen = false
    private var endFreezeView: UIView?
    private var cancellables = Set<AnyCancellable>()
    private var hintTopConstraint: Constraint?
    private let deviceStore = DeviceStore.shared
    
    private var isGroupCall: Bool {
        let call = CallStore.shared.state.value.activeCall
        return !call.chatGroupId.isEmpty || call.inviteeIds.count > 1
    }
}

// MARK: - Layout
extension CallView {
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        // The sound effects and the beauty levels are user preferences: the call opens with the saved ones.
        if window != nil { CallEffectsState.apply(to: TrtcCallEffectsEngine()) }
        guard !isViewReady else { return }
        isViewReady = true
        isGroupCallSession = isGroupCall
        constructViewHierarchy()
        activateConstraints()
        checkViewVisibility()
    }
    
    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        guard newWindow == nil else { return }
        effectsPanel?.removeFromSuperview()
        effectsPanel = nil
    }

    /// Sound-effect / beauty sheet over the whole call page; opening the other kind replaces the current one.
    private func showEffectsPanel(_ kind: CallEffectsPanel.Kind) {
        hideEffectsPanel(animated: false)
        let panel = CallEffectsPanel(kind: kind, engine: TrtcCallEffectsEngine()) { [weak self] in self?.hideEffectsPanel(animated: true) }
        effectsPanel = panel
        addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        panel.alpha = 0
        UIView.animate(withDuration: 0.16) { panel.alpha = 1 }
    }

    private func hideEffectsPanel(animated: Bool) {
        guard let panel = effectsPanel else { return }
        effectsPanel = nil
        if animated {
            UIView.animate(withDuration: 0.12, animations: { panel.alpha = 0 }, completion: { _ in panel.removeFromSuperview() })
        } else {
            panel.removeFromSuperview()
        }
    }

    private func constructViewHierarchy() {
        addSubview(backgroundAvatarView)
        addSubview(backgroundBlurView)
        let isSingleVideo = !isGroupCall && CallStore.shared.state.value.activeCall.mediaType == .video
        if !isGroupCall && !isSingleVideo {
            // Design S9: scrim + glow under the SDK avatar.
            let shade = CallVoiceShadeView(frame: .zero)
            skinShade = shade
            addSubview(shade)
        }
        addSubview(callCoreView)
        if !isGroupCall {
            // Design S10: the black scrims over the remote picture live in the SDK overlay *under* the controls
            // (see onCreateOverlayView); a shade above callCoreView would also dim the control buttons.
            let layer = CallSkinLayerView(hub: skinHub, video: isSingleVideo)
            skinLayer = layer
            addSubview(layer)
            skinHub.panelOpener = { [weak self] kind in self?.showEffectsPanel(kind) }
            updatePeerName()
        }
        addSubview(waitingParticipantsView)
        addSubview(multiCallControlsView)
        addSubview(aiSubtitle)
        addSubview(callTranscriberView)
        addSubview(timerView)
        addSubview(hintView)

        callCoreView.callViewAdapter = self
    }
    
    private func activateConstraints() {
        backgroundAvatarView.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        backgroundBlurView.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
        skinShade?.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
        skinLayer?.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        if isGroupCall {
            callCoreView.snp.remakeConstraints { make in
                make.top.equalToSuperview().offset(CallConstants.statusBar_Height + 40.scale375Height())
                make.leading.trailing.bottom.equalToSuperview()
            }
        } else {
            callCoreView.snp.remakeConstraints { make in
                make.edges.equalToSuperview()
            }
        }
        
        waitingParticipantsView.snp.remakeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.equalToSuperview()
            make.height.equalTo(65.scale375Width())
            make.centerY.equalToSuperview()
        }
        
        multiCallControlsView.snp.remakeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(260.scale375Height())
        }
        
        let activeCall = CallStore.shared.state.value.activeCall
        let isSingleAudioCall = !isGroupCall && activeCall.mediaType == .audio
        let aiSubtitleBottomOffset = isSingleAudioCall ? -330.scale375Height() : -250.scale375Height()
        
        aiSubtitle.snp.remakeConstraints { make in
            make.centerX.equalToSuperview()
            make.height.equalTo(200.scale375Height())
            make.width.equalToSuperview().multipliedBy(0.95)
            make.bottom.equalToSuperview().offset(aiSubtitleBottomOffset)
        }
        
        let singleCallControlsHeight: CGFloat = isSingleAudioCall ? 330.scale375Height() : 250.scale375Height()
        let controlsHeight = isGroupCall ? multiCallControlsHeight : singleCallControlsHeight
        
        callTranscriberView.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(safeAreaLayoutGuide.snp.top)
            make.bottom.equalToSuperview().offset(-controlsHeight - 10.scale375Height())
        }
        
        if UIWindow.isPortrait {
            if isGroupCall {
                timerView.snp.remakeConstraints { make in
                    make.top.equalTo(safeAreaLayoutGuide.snp.top).offset(6.scale375Height())
                    make.centerX.equalToSuperview()
                    make.height.equalTo(24.scale375Height())
                }

                hintView.snp.remakeConstraints { make in
                    make.centerX.equalToSuperview()
                    make.bottom.equalToSuperview().offset(-300.scale375Height() - 10.scale375Height())
                    make.height.equalTo(32.scale375Height())
                }
            } else {
                // Design S9 / S10: time (or status hint) sits right under the peer name, 28pt below the status bar.
                timerView.snp.remakeConstraints { make in
                    make.top.equalTo(safeAreaLayoutGuide.snp.top).offset(28)
                    make.centerX.equalToSuperview()
                    make.height.equalTo(16)
                }

                hintView.snp.remakeConstraints { make in
                    make.centerX.equalToSuperview()
                    hintTopConstraint = make.top.equalTo(safeAreaLayoutGuide.snp.top).offset(hintTopOffset()).constraint
                    make.height.equalTo(16)
                }
            }
        } else {
            timerView.snp.remakeConstraints { make in
                make.top.equalToSuperview().offset(10.scale375Height())
                make.centerX.equalToSuperview()
                make.height.equalTo(24.scale375Height())
            }
            
            hintView.snp.remakeConstraints { make in
                make.centerX.equalToSuperview()
                make.bottom.equalToSuperview().offset(-150.scale375Height())
                make.height.equalTo(32.scale375Height())
            }
        }
    }
    
    @objc private func handleOrientationChange() {
        DispatchQueue.main.async { [weak self] in
            self?.activateConstraints()
        }
    }
    
    /// The status hint ("对方网络不佳" ...) takes the timer's line while no timer is shown (waiting) and sits right
    /// under the timer once the call is accepted, so the two never overlap.
    private func hintTopOffset() -> CGFloat {
        CallStore.shared.state.value.selfInfo.status == .accept ? 28 + 16 + 4 : 28
    }

    private func updateHintOffset() {
        hintTopConstraint?.update(offset: hintTopOffset())
    }

    private func updateControlsView() {
        updateHintOffset()
        singleCallControlsView.isHidden = isGroupCall
        multiCallControlsView.isHidden = !isGroupCall
        
        if isGroupCall {
            multiCallControlsView.updateViewForCallState()
        } else {
            singleCallControlsView.updateViewForCallState()
        }
        
        checkViewVisibility()
    }
    
    private func checkViewVisibility() {
        guard !isContentFrozen else { return }
        let activeCall = CallStore.shared.state.value.activeCall
        let selfInfo = CallStore.shared.state.value.selfInfo
        let isCalledWaiting = selfInfo.id != activeCall.inviterId && selfInfo.status == .waiting
        let shouldShowWaitingView = isGroupCall && isCalledWaiting
        waitingParticipantsView.isHidden = !shouldShowWaitingView
        callCoreView.isHidden = shouldShowWaitingView
    }
    
    private func updateCamera() {
        let activeCall = CallStore.shared.state.value.activeCall
        let cameraStatus = deviceStore.state.value.cameraStatus
        
        if activeCall.mediaType == .video && cameraStatus == .on {
            deviceStore.openLocalCamera(isFront: deviceStore.state.value.isFrontCamera) { result in
                switch result {
                case .success:
                    Logger.info("CallView - openLocalCamera success in updateCamera.")
                case .failure(let error):
                    Logger.error("CallView - openLocalCamera failed in updateCamera. Code: \(error.code), Message: \(error.message)")
                }
            }
        }
    }
    
    /// Design S9: the blurred background is the *other* party's avatar (TUICallKit used the own avatar).
    private func updatePeerName() {
        guard !isContentFrozen else { return }
        let state = CallStore.shared.state.value
        guard let peer = state.allParticipants.first(where: { $0.id != state.selfInfo.id }) else { return }
        let name = !peer.remark.isEmpty ? peer.remark : (!peer.name.isEmpty ? peer.name : peer.id)
        skinLayer?.setPeerName(name)
    }

    private var isGroupSession: Bool {
        isViewReady ? isGroupCallSession : isGroupCall
    }

    private func updateBackgroundAvatar() {
        guard !isContentFrozen else { return }
        let state = CallStore.shared.state.value
        let other = state.allParticipants.first(where: { $0.id != state.selfInfo.id })
        guard let peer = other ?? (isGroupSession ? state.selfInfo : nil) else {
            if backgroundAvatarView.image == nil {
                backgroundAvatarView.image = CallKitBundle.getBundleImage(name: "default_participant_icon")
            }
            return
        }
        let avatarURL = peer.avatarURL

        if !avatarURL.isEmpty, let url = URL(string: avatarURL) {
            if let cached = CallView.cachedAvatar(for: url) {
                backgroundAvatarView.sd_cancelCurrentImageLoad()
                backgroundAvatarView.image = cached
            } else {
                backgroundAvatarView.sd_setImage(with: url)
            }
        } else {
            backgroundAvatarView.sd_cancelCurrentImageLoad()
            backgroundAvatarView.image = CallKitBundle.getBundleImage(name: "default_participant_icon")
        }
    }

    private func freezeContentForEnd() {
        guard isViewReady, !isGroupCallSession, !isContentFrozen else { return }
        isContentFrozen = true
        backgroundAvatarView.sd_cancelCurrentImageLoad()
        guard let snapshot = callCoreView.snapshotView(afterScreenUpdates: false) else { return }
        snapshot.frame = callCoreView.frame
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snapshot.isUserInteractionEnabled = false
        insertSubview(snapshot, aboveSubview: callCoreView)
        endFreezeView = snapshot
        callCoreView.isHidden = true
    }

    private func unfreezeContentAfterEnd() {
        guard isContentFrozen else { return }
        isContentFrozen = false
        endFreezeView?.removeFromSuperview()
        endFreezeView = nil
        checkViewVisibility()
        updatePeerName()
        updateBackgroundAvatar()
    }

    private static func cachedAvatar(for url: URL) -> UIImage? {
        SDImageCache.shared.imageFromCache(forKey: SDWebImageManager.shared.cacheKey(for: url))
    }

    private static let transparentAvatar: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
    }()

    private func avatarPlaceholder() -> UIImage? {
        let fallback = CallKitBundle.getBundleImage(name: "default_participant_icon")
        if isGroupCall { return fallback }
        let state = CallStore.shared.state.value
        guard let peer = state.allParticipants.first(where: { $0.id != state.selfInfo.id }),
              !peer.avatarURL.isEmpty, let url = URL(string: peer.avatarURL) else { return fallback }
        return CallView.cachedAvatar(for: url) ?? CallView.transparentAvatar
    }

    private func hideSDKNicknameBars() {
        guard isViewReady, !isGroupCallSession else { return }
        CallView.hideNicknameBars(in: callCoreView)
    }

    private static func hideNicknameBars(in view: UIView) {
        for sub in view.subviews {
            if let stack = sub as? UIStackView, stack.arrangedSubviews.count == 3,
               stack.arrangedSubviews[0] is UILabel, stack.arrangedSubviews[1] is UIImageView,
               stack.arrangedSubviews[2] is UIImageView {
                stack.alpha = 0
            } else {
                hideNicknameBars(in: sub)
            }
        }
    }

    private func updateTranscriberViewConstraints() {
        guard isViewReady, callTranscriberView.superview != nil else { return }
        
        callTranscriberView.snp.updateConstraints { make in
            make.bottom.equalToSuperview().offset(-multiCallControlsHeight - 10.scale375Height())
        }
        
        UIView.animate(withDuration: CallConstants.groupFunctionAnimationDuration) { [weak self] in
            self?.layoutIfNeeded()
        }
    }
    
}

// MARK: - Resources
extension CallView {
    private func setupCoreViewStaticResources() {
        CallCoreView.defaultAvatarImage = avatarPlaceholder()
        
        var volumeLevelIcons: [VolumeLevel: String] = [:]
        if let path = getAbsolutePathForBundleImage(name: "icon_mic_off") { volumeLevelIcons[.mute] = path }
        if let path = getAbsolutePathForBundleImage(name: "icon_volume") { volumeLevelIcons[.low] = path }
        if let path = getAbsolutePathForBundleImage(name: "icon_volume") { volumeLevelIcons[.medium] = path }
        if let path = getAbsolutePathForBundleImage(name: "icon_volume") { volumeLevelIcons[.high] = path }
        if let path = getAbsolutePathForBundleImage(name: "icon_volume") { volumeLevelIcons[.peak] = path }
        callCoreView.setVolumeLevelIcons(icons: volumeLevelIcons)
        
        var networkQualityIcons: [NetworkQuality: String] = [:]
        if let path = getAbsolutePathForBundleImage(name: "group_network_low_quality") {
            networkQualityIcons[.bad] = path
        }
        callCoreView.setNetworkQualityIcons(icons: networkQualityIcons)
        
        if let bundle = CallKitBundle.getTUICallKitBundle(),
           let waitingAnimation = bundle.path(forResource: "loading", ofType: "gif") {
            callCoreView.setWaitingAnimation(path: waitingAnimation)
        }
    }
    
    private func handleParticipantsAvatarUpdate(_ participants: [CallParticipantInfo]) {
        var avatarPathsToSet: [String: String] = [:]
        
        for user in participants {
            guard !user.avatarURL.isEmpty, let url = URL(string: user.avatarURL) else { continue }
            
            let cacheKey = SDWebImageManager.shared.cacheKey(for: url)
            
            if let cachePath = SDImageCache.shared.cachePath(forKey: cacheKey),
               FileManager.default.fileExists(atPath: cachePath) {
                avatarPathsToSet[user.id] = cachePath
            } else {
                SDWebImageDownloader.shared.downloadImage(with: url) { [weak self] image, _, error, finished in
                    guard let self = self, let image = image, finished, error == nil else { return }
                    SDImageCache.shared.store(image, forKey: cacheKey, toDisk: true) {
                        if let newPath = SDImageCache.shared.cachePath(forKey: cacheKey) {
                            DispatchQueue.main.async {
                                self.callCoreView.setParticipantAvatars(avatars: [user.id: newPath])
                            }
                        }
                    }
                }
            }
        }
        
        if !avatarPathsToSet.isEmpty {
            callCoreView.setParticipantAvatars(avatars: avatarPathsToSet)
        }
    }
    
    private func getAbsolutePathForBundleImage(name: String) -> String? {
        guard let image = CallKitBundle.getBundleImage(name: name),
              let data = image.pngData() else { return nil }
        
        let tempDir = NSTemporaryDirectory()
        let fileName = "tuicallkit_res_\(name).png"
        let fullPath = (tempDir as NSString).appendingPathComponent(fileName)
        
        if !FileManager.default.fileExists(atPath: fullPath) {
            try? data.write(to: URL(fileURLWithPath: fullPath))
        }
        return fullPath
    }
    
    private func handleNetworkTypeChanged(_ newType: NetworkType) {
        var toastString = ""
        switch newType {
        case .cellular:
            toastString = CallKitLocalization.localized("SmartCellular.SwitchedToCellular")
        case .wifi:
            toastString = CallKitLocalization.localized("SmartCellular.SwitchedToWiFi")
        case .unknown:
            return
        }
        showAtomicToast(text: toastString)
    }
}

// MARK: - Subscribe
extension CallView {
    private func subscribeCallState() {
        CallStore.shared.state
            .subscribe(StatePublisherSelector(keyPath: \.selfInfo.status))
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateControlsView()
                self.updateCamera()
            }
            .store(in: &cancellables)
        
        CallStore.shared.state
            .subscribe(StatePublisherSelector(keyPath: \.allParticipants))
            .removeDuplicates { prev, curr in
                return prev.map { "\($0.id)_\($0.avatarURL)" } == curr.map { "\($0.id)_\($0.avatarURL)" }
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] participants in
                self?.handleParticipantsAvatarUpdate(participants)
                self?.updatePeerName()
                self?.updateBackgroundAvatar()
            }
            .store(in: &cancellables)
        
        CallStore.shared.state
            .subscribe(StatePublisherSelector(keyPath: \.activeCall.inviteeIds))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.hideSDKNicknameBars() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleOrientationChange()
            }
            .store(in: &cancellables)
        
        DeviceStore.shared.state.subscribe(StatePublisherSelector<DeviceState, NetworkType>(keyPath: \.networkType))
            .receive(on: RunLoop.main)
            .sink { [weak self] newType in
                guard let self = self else { return }
                self.handleNetworkTypeChanged(newType)

            }
            .store(in: &cancellables)
    }
}

// MARK: - MultiCallControlsViewDelegate
extension CallView: MultiCallControlsViewDelegate {
    func multiCallControlsView(_ view: MultiCallControlsView, didChangeModeHeight height: CGFloat) {
        multiCallControlsHeight = height
        
        multiCallControlsView.snp.updateConstraints { make in
            make.height.equalTo(height)
        }
        
        UIView.animate(withDuration: 0.3) {
            self.layoutIfNeeded()
        }
        
        updateTranscriberViewConstraints()
    }
}

// MARK: - CallViewAdapter
extension CallView: CallViewAdapter {
    public func onCreateOverlayView(layout: CallLayoutTemplate) -> UIView? {
        guard layout == .float else { return nil }

        let container = OverlayContainerView()
        container.backgroundColor = .clear
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        if !isGroupCall && CallStore.shared.state.value.activeCall.mediaType == .video {
            let shade = CallVideoShadeView(frame: .zero)
            shade.frame = container.bounds
            shade.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(shade)
        }

        singleCallControlsView.removeFromSuperview()
        container.addSubview(singleCallControlsView)

        // Self-sizing skinned controls: anchored to the bottom safe area, height from their own layout.
        singleCallControlsView.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(container.safeAreaLayoutGuide.snp.bottom)
        }

        return container
    }
}

private final class OverlayContainerView: UIView {
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard let superview = superview else { return }
        frame = superview.bounds
    }
}
