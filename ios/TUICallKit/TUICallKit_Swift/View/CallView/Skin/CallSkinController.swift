//
//  CallSkinController.swift
//  What the skinned call controls need from the call engine. `RealCallSkinController` forwards to
//  the SDK exactly like the original TUICallKit control view did; `PreviewCallSkinController` keeps the
//  state locally so the page can be inspected without a call (debug preview only).
//

import UIKit
import Combine
import AtomicXCore
import RTCRoomEngine

protocol CallSkinController: AnyObject {
    var isVideo: Bool { get }
    var micOn: AnyPublisher<Bool, Never> { get }
    var cameraOn: AnyPublisher<Bool, Never> { get }
    var speakerOn: AnyPublisher<Bool, Never> { get }
    var blurAvailable: Bool { get }
    var usesSystemRoutePicker: Bool { get }

    func toggleMic()
    func toggleCamera()
    func toggleSpeaker()
    func flipCamera()
    func toggleBlur()
    func hangup()
    func accept()
    func reject()
}

final class RealCallSkinController: CallSkinController {
    let isVideo: Bool
    let blurAvailable: Bool
    private let deviceStore = DeviceStore.shared
    private var blurOn = false

    init(isVideo: Bool, blurAvailable: Bool) {
        self.isVideo = isVideo
        self.blurAvailable = blurAvailable
    }

    var micOn: AnyPublisher<Bool, Never> {
        deviceStore.state.subscribe(StatePublisherSelector { $0.microphoneStatus == .on }).removeDuplicates().eraseToAnyPublisher()
    }

    var cameraOn: AnyPublisher<Bool, Never> {
        deviceStore.state.subscribe(StatePublisherSelector { $0.cameraStatus == .on }).removeDuplicates().eraseToAnyPublisher()
    }

    var speakerOn: AnyPublisher<Bool, Never> {
        deviceStore.state.subscribe(StatePublisherSelector { $0.currentAudioRoute == .speakerphone }).removeDuplicates().eraseToAnyPublisher()
    }

    var usesSystemRoutePicker: Bool { true }

    func toggleMic() {
        if deviceStore.state.value.microphoneStatus == .on { CallManager.shared.closeLocalMicrophone() }
        else { CallManager.shared.openLocalMicrophone() }
    }

    func toggleCamera() {
        if deviceStore.state.value.cameraStatus == .on { CallManager.shared.closeLocalCamera() }
        else { CallManager.shared.openLocalCamera(isFront: deviceStore.state.value.isFrontCamera) }
    }

    func toggleSpeaker() {
        let next: AudioRoute = deviceStore.state.value.currentAudioRoute == .speakerphone ? .earpiece : .speakerphone
        CallManager.shared.setAudioRoute(next)
    }

    func flipCamera() {
        CallManager.shared.switchCamera(isFront: !deviceStore.state.value.isFrontCamera)
    }

    func toggleBlur() {
        blurOn.toggle()
        let level = blurOn ? 3 : 0
        TUICallEngine.createInstance().setBlurBackground(level) { [weak self] code, message in
            if code != 0 {
                Logger.error("Set blur background failed: \(code) \(message ?? "")")
                DispatchQueue.main.async { self?.blurOn.toggle() }
            }
        }
    }

    func hangup() {
        CallManager.shared.hangup { result in
            switch result {
            case .success: Logger.info("SocialCallControls - hangup success")
            case .failure(let error): Logger.info("SocialCallControls - hangup failed. Code: \(error.code), Message: \(error.message)")
            }
        }
    }

    func accept() {
        CallManager.shared.accept { result in
            switch result {
            case .success: Logger.info("SocialCallControls - accept success")
            case .failure(let error): Logger.info("SocialCallControls - accept failed. Code: \(error.code), Message: \(error.message)")
            }
        }
    }

    func reject() {
        CallManager.shared.reject { result in
            switch result {
            case .success: Logger.info("SocialCallControls - reject success")
            case .failure(let error): Logger.info("SocialCallControls - reject failed. Code: \(error.code), Message: \(error.message)")
            }
        }
    }
}

/// Debug-only controller: local toggles, no SDK access.
final class PreviewCallSkinController: CallSkinController {
    let isVideo: Bool
    let blurAvailable = true
    let usesSystemRoutePicker = false
    private let mic: CurrentValueSubject<Bool, Never>
    private let camera: CurrentValueSubject<Bool, Never>
    private let speaker: CurrentValueSubject<Bool, Never>

    init(isVideo: Bool, mic: Bool = true, camera: Bool = true, speaker: Bool = true) {
        self.isVideo = isVideo
        self.mic = CurrentValueSubject(mic)
        self.camera = CurrentValueSubject(camera)
        self.speaker = CurrentValueSubject(speaker)
    }

    var micOn: AnyPublisher<Bool, Never> { mic.eraseToAnyPublisher() }
    var cameraOn: AnyPublisher<Bool, Never> { camera.eraseToAnyPublisher() }
    var speakerOn: AnyPublisher<Bool, Never> { speaker.eraseToAnyPublisher() }

    func toggleMic() { mic.send(!mic.value) }
    func toggleCamera() { camera.send(!camera.value) }
    func toggleSpeaker() { speaker.send(!speaker.value) }
    func flipCamera() {}
    func toggleBlur() {}
    func hangup() {}
    func accept() {}
    func reject() {}
}
