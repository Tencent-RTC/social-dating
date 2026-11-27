//
//  TimerView.swift
//  Pods
//
//  Created by vincepzhang on 2025/3/3.
//

import AtomicXCore
import AtomicX
import Combine
import RTCRoomEngine
import SnapKit
import Foundation
import UIKit

class TimerView: UIView {
    // MARK: Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        updateTimerView()
        subscribeCallListStatus()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Private
    private let timerLabel: UILabel = {
        let timerLabel = UILabel()
        // Design S9 / S10 `.calltop__time`: 12pt secondary text with a 6pt success dot, tabular digits.
        timerLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timerLabel.backgroundColor = UIColor.clear
        timerLabel.textAlignment = .center
        timerLabel.textColor = CallSkin.tokens.textColorSecondary
        return timerLabel
    }()

    private let dotView: UIView = {
        let dot = UIView()
        dot.backgroundColor = CallSkin.tokens.textColorSuccess
        dot.layer.cornerRadius = 3
        return dot
    }()
    
    private var cancellables = Set<AnyCancellable>()
    private var isViewReady: Bool = false
    
    // MARK: UI Specification Processing
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard !isViewReady else { return }
        constructViewHierarchy()
        activateConstraints()
        isViewReady = true
    }
}

// MARK: Layout
extension TimerView {
    private func constructViewHierarchy() {
        addSubview(dotView)
        addSubview(timerLabel)
    }
    
    private func activateConstraints() {
        dotView.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.size.equalTo(6)
        }
        timerLabel.snp.makeConstraints { make in
            make.top.trailing.bottom.equalToSuperview()
            make.leading.equalTo(dotView.snp.trailing).offset(4)
        }
    }
    
    private func updateTimerView() {
        let state = CallStore.shared.state.value
        let status = state.selfInfo.status
        let activeCall = state.activeCall
        let selfInfo = state.selfInfo
        let isOneToOne = activeCall.chatGroupId.isEmpty && activeCall.inviteeIds.count == 1

        switch status {
        case .accept:
            timerLabel.text = GCDTimer.secondToHMSString(second: Int(activeCall.duration))
        case .waiting:
            timerLabel.text = CallKitLocalization.localized("waitAccept")
        default:
            timerLabel.text = ""
        }

        switch status {
        case .accept:
            timerLabel.isHidden = false
        case .waiting:
            if isOneToOne {
                timerLabel.isHidden = true
            } else {
                let isInviter = selfInfo.id == activeCall.inviterId
                timerLabel.isHidden = !isInviter
            }
        default:
            timerLabel.isHidden = true
        }
        dotView.isHidden = timerLabel.isHidden || status != .accept
    }
}

// MARK: Subscribe
extension TimerView {
    func subscribeCallListStatus() {
        CallStore.shared.state.subscribe(StatePublisherSelector(keyPath: \.activeCall.duration))
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateTimerView()
            }
            .store(in: &cancellables)

        CallStore.shared.state.subscribe(StatePublisherSelector(keyPath: \.selfInfo.status))
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateTimerView()
            }
            .store(in: &cancellables)
    }
}
