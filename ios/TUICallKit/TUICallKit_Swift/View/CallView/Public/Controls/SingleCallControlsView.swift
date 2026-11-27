//
//  SingleCallControlsView.swift
//  Pods
//
//  Created by yukiwwwang on 2025/9/25.
//
//  Chat 1v1: skinned to design S9 / S10 (see View/CallView/Skin). The state machine is unchanged:
//  callee waiting -> accept / reject; caller waiting and accepted -> the control rows.
//

import UIKit
import AtomicX
import AtomicXCore
import SnapKit

class SingleCallControlsView: UIView {

    // MARK: - Init
    init(hub: CallSkinHub) {
        self.hub = hub
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal
    var enableVirtualBackground: Bool = true

    private(set) var controlsHidden = false

    func toggleControls() {
        guard content is SocialCallControlsView else { return }
        controlsHidden.toggle()
        let hide = controlsHidden
        if !hide { isHidden = false }
        UIView.animate(withDuration: 0.18, animations: {
            self.alpha = hide ? 0 : 1
        }, completion: { _ in
            if self.controlsHidden { self.isHidden = true }
        })
    }

    private func resetControlsVisibility() {
        controlsHidden = false
        layer.removeAllAnimations()
        alpha = 1
        isHidden = false
    }

    // MARK: Private
    private let hub: CallSkinHub
    private var content: UIView?
    private var contentKind = ""

    func updateViewForCallState() {
        let activeCall = CallStore.shared.state.value.activeCall
        let selfInfo = CallStore.shared.state.value.selfInfo
        let isVideo = activeCall.mediaType == .video
        let isCaller = selfInfo.id == activeCall.inviterId
        let isCalleeWaiting = !isCaller && selfInfo.status == .waiting
        let isActive = selfInfo.status == .waiting || selfInfo.status == .accept
        guard isActive else { return }

        // Waiting -> accepted keeps the same controls (only the labels / camera state change).
        let kind = isCalleeWaiting ? "ring-\(isVideo)" : "controls-\(isVideo)"
        guard kind != contentKind else { return }
        contentKind = kind

        content?.removeFromSuperview()
        resetControlsVisibility()
        let controller = RealCallSkinController(isVideo: isVideo, blurAvailable: enableVirtualBackground)
        let view: UIView = isCalleeWaiting
            ? SocialCalleeActionsView(controller: controller)
            : SocialCallControlsView(controller: controller, hub: hub)
        addSubview(view)
        view.snp.makeConstraints { make in
            make.top.leading.trailing.bottom.equalToSuperview()
        }
        content = view
    }
}
