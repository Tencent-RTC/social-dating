//
//  SocialCallControlsView.swift
//  Bottom block of the S9 (voice) / S10 (video) call page:
//
//    voice : 音效 | 送礼 | 话题 · 麦克风 | 挂断 | 扬声器   (the topic card is a draggable overlay of CallSkinLayerView)
//    video : tip pill · 音效 | 美颜 | 送礼 | 话题 | 虚化 · 麦克风 | 摄像头 | 挂断 | 扬声器 | 翻转
//
//  The control row is the original TUICallKit capability (mic / camera / audio route / flip / hang up /
//  background blur) bound through `CallSkinController`; the function row is the demo's local
//  entertainment layer (`CallSkinHub`).
//

import UIKit
import Combine
import AVKit
import AtomicX

final class SocialCallControlsView: UIView {
    private static let tipVisible: TimeInterval = 5
    private let controller: CallSkinController
    private let hub: CallSkinHub
    private let video: Bool
    private let t = CallSkin.tokens
    private var cancellables = Set<AnyCancellable>()
    private var hangingUp = false
    private var blurOn = false
    private var routeTimer: Timer?

    private var micCircle: CallSkinCircle!
    private var micLabel: UILabel!
    private var cameraCircle: CallSkinCircle?
    private var cameraLabel: UILabel?
    private var speakerCircle: CallSkinCircle!
    private var speakerLabel: UILabel!
    private var blurCircle: CallSkinCircle?
    private var routePicker: AVRoutePickerView?
    private var otherControls: [UIView] = []

    init(controller: CallSkinController, hub: CallSkinHub) {
        self.controller = controller
        self.hub = hub
        self.video = controller.isVideo
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
        bind()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { routeTimer?.invalidate() }

    // MARK: - Build

    private func build() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])

        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        let pill = tipPill()
        holder.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: holder.topAnchor),
            pill.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            pill.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            pill.heightAnchor.constraint(equalToConstant: 26)
        ])
        stack.addArrangedSubview(holder)
        stack.setCustomSpacing(12, after: holder)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tipVisible) { [weak holder] in
            guard let holder else { return }
            UIView.animate(withDuration: 0.2, animations: { holder.alpha = 0 })
        }
        let functionRow = buildFunctionRow()
        stack.addArrangedSubview(functionRow)
        stack.setCustomSpacing(18, after: functionRow)
        stack.addArrangedSubview(buildControlRow())
    }

    private func tipPill() -> UIView {
        let pill = UIView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = t.bgColorTagMask
        pill.layer.cornerRadius = 13
        let icon = CallSkin.glyph("callskin_ic_shield", size: 14, tint: t.textColorWarning)
        let text = CallSkin.label(CallSkin.loc(video ? "skin.tip_video" : "skin.tip_voice"), size: 12, color: t.textColorSecondary)
        pill.addSubview(icon)
        pill.addSubview(text)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -12),
            text.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])
        return pill
    }

    static func topicText(_ text: String, color: UIColor, size: CGFloat = 14, line: CGFloat = 21) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = line
        style.maximumLineHeight = line
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: style
        ])
    }

    private func spreadRow(_ views: [UIView], alignment: UIStackView.Alignment) -> UIStackView {
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.alignment = alignment
        row.distribution = .equalSpacing
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func buildFunctionRow() -> UIView {
        let small: CGFloat = video ? 52 : 64
        var left: [UIView] = []
        left.append(funItem("callskin_ic_sfx", glyph: 26, title: "skin.fun_sfx", width: small) { [weak self] in
            self?.hub.openPanel(.sound)
        })
        if video {
            left.append(funItem("callskin_ic_beauty", glyph: 26, title: "skin.fun_beauty", width: small) { [weak self] in
                self?.hub.openPanel(.beauty)
            })
        }
        let gift = giftItem(width: video ? 60 : 64)
        var right: [UIView] = []
        right.append(funItem("callskin_ic_topic", glyph: 24, title: "skin.fun_topic", width: small) { [weak self] in
            guard let self else { return }
            self.hub.toggleTopic()
        })
        if video && controller.blurAvailable {
            let blur = funItem("callskin_ic_blur", glyph: 26, title: "skin.fun_blur", width: small) { [weak self] in
                guard let self else { return }
                self.blurOn.toggle()
                self.blurCircle?.render(icon: "callskin_ic_blur", active: self.blurOn)
                self.controller.toggleBlur()
            }
            blurCircle = blur.subviews.compactMap { ($0 as? UIStackView)?.arrangedSubviews.first as? CallSkinCircle }.first
            right.append(blur)
        }
        return centeredGiftRow(left: left, gift: gift, right: right)
    }

    /// The gift button is always the centre of the row, whatever the number of buttons on either side: the left and
    /// right groups get exactly the space on their side of the gift and spread their buttons inside it. With two
    /// buttons per side this equals `space-between`; with 1 / 2 or 2 / 1 the gift still does not move.
    private func centeredGiftRow(left: [UIView], gift: UIView, right: [UIView]) -> UIView {
        // Same as Android: every button is followed (left group) / preceded (right group) by a flexible spacer and all
        // spacers share the leftover width equally, so the buttons are spread evenly on their side of the gift.
        var spacers: [UIView] = []
        func spacer() -> UIView {
            let view = UIView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacers.append(view)
            return view
        }
        func group(_ views: [UIView]) -> UIStackView {
            let stack = UIStackView(arrangedSubviews: views)
            stack.axis = .horizontal
            stack.alignment = .bottom
            stack.distribution = .fill
            stack.translatesAutoresizingMaskIntoConstraints = false
            return stack
        }
        let leftGroup = group(left.flatMap { [$0, spacer()] })
        let rightGroup = group(right.flatMap { [spacer(), $0] })
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        gift.translatesAutoresizingMaskIntoConstraints = false
        [leftGroup, gift, rightGroup].forEach(container.addSubview)
        // Constraints between spacers of different stacks need the common hierarchy above.
        for other in spacers.dropFirst() {
            other.widthAnchor.constraint(equalTo: spacers[0].widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            gift.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            gift.topAnchor.constraint(equalTo: container.topAnchor),
            gift.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            leftGroup.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            leftGroup.trailingAnchor.constraint(equalTo: gift.leadingAnchor),
            leftGroup.topAnchor.constraint(equalTo: container.topAnchor),
            leftGroup.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rightGroup.leadingAnchor.constraint(equalTo: gift.trailingAnchor),
            rightGroup.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rightGroup.topAnchor.constraint(equalTo: container.topAnchor),
            rightGroup.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func funItem(_ icon: String, glyph: CGFloat, title: String, width: CGFloat, action: @escaping () -> Void) -> CallSkinTap {
        let circle = CallSkinCircle(size: 48, glyph: glyph)
        circle.render(icon: icon, active: false)
        let label = CallSkin.label(CallSkin.loc(title), size: 12, color: t.textColorPrimary)
        return column(circle: circle, label: label, width: width, gap: 6, topPad: 0, pressScale: 0.88, action: action)
    }

    private func giftItem(width: CGFloat) -> CallSkinTap {
        let base = CallSkinGradientView(colors: [t.buttonColorPrimaryDefault, t.tagColorLevel4],
                                        start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1, y: 1))
        base.layer.cornerRadius = 18
        base.layer.borderWidth = 1
        base.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        base.layer.shadowColor = t.tagColorLevel4.cgColor
        base.layer.shadowOpacity = 0.5
        base.layer.shadowRadius = 8
        base.layer.shadowOffset = CGSize(width: 0, height: 5)
        base.isUserInteractionEnabled = false
        let highlight = CallSkinGradientView(colors: [UIColor.white.withAlphaComponent(0.24), .clear],
                                             start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 0.52))
        highlight.layer.cornerRadius = 18
        highlight.isUserInteractionEnabled = false
        let icon = CallSkin.glyph("callskin_ic_gift", size: 34, tint: nil)
        icon.image = CallSkin.image("callskin_ic_gift", template: false)
        base.addSubview(highlight)
        base.addSubview(icon)
        NSLayoutConstraint.activate([
            base.widthAnchor.constraint(equalToConstant: 56),
            base.heightAnchor.constraint(equalToConstant: 56),
            highlight.topAnchor.constraint(equalTo: base.topAnchor),
            highlight.bottomAnchor.constraint(equalTo: base.bottomAnchor),
            highlight.leadingAnchor.constraint(equalTo: base.leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: base.trailingAnchor),
            icon.centerXAnchor.constraint(equalTo: base.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: base.centerYAnchor)
        ])
        let label = CallSkin.label(CallSkin.loc("skin.fun_gift"), size: 12, color: t.textColorPrimary, bold: true)
        return column(view: base, label: label, width: width, gap: 6, topPad: 0, pressScale: 0.88) { [weak self] in
            guard let self else { return }
            self.hub.sendGift { [weak self] in self?.showAtomicToast(text: CallSkin.loc("skin.gift_failed")) }
        }
    }

    private func buildControlRow() -> UIView {
        let size: CGFloat = video ? 52 : 60
        let width: CGFloat = video ? 52 : 64
        let gap: CGFloat = video ? 12 : 8
        let topPad: CGFloat = video ? 4 : 0
        var items: [UIView] = []

        micCircle = CallSkinCircle(size: size, glyph: 26)
        micLabel = CallSkin.label("", size: 12, color: t.textColorPrimary)
        let mic = column(circle: micCircle, label: micLabel, width: width, gap: gap, topPad: topPad) { [weak self] in
            self?.controller.toggleMic()
        }
        items.append(mic)

        if video {
            let circle = CallSkinCircle(size: size, glyph: 26)
            let label = CallSkin.label("", size: 12, color: t.textColorPrimary)
            cameraCircle = circle
            cameraLabel = label
            items.append(column(circle: circle, label: label, width: width, gap: gap, topPad: topPad) { [weak self] in
                self?.controller.toggleCamera()
            })
        }

        // Hang up: 60 circle, hang-up red, gap 8.
        let hang = CallSkinCircle(size: 60, glyph: 30)
        hang.render(icon: "callskin_ic_hangup", active: false, fill: t.buttonColorHangupDefault, tint: .white)
        hang.layer.shadowColor = t.buttonColorHangupDefault.cgColor
        hang.layer.shadowOpacity = 0.45
        hang.layer.shadowRadius = 8
        hang.layer.shadowOffset = CGSize(width: 0, height: 6)
        let hangLabel = CallSkin.label(CallSkin.loc("hangup"), size: 12, color: t.textColorPrimary)
        let hangColumn = column(circle: hang, label: hangLabel, width: video ? 60 : 64, gap: 8, topPad: 0) { [weak self] in
            self?.hangUp()
        }
        items.append(hangColumn)

        speakerCircle = CallSkinCircle(size: size, glyph: 26)
        speakerLabel = CallSkin.label("", size: 12, color: t.textColorPrimary)
        let speaker = column(circle: speakerCircle, label: speakerLabel, width: width, gap: gap, topPad: topPad) { [weak self] in
            self?.controller.toggleSpeaker()
        }
        items.append(speaker)
        if controller.usesSystemRoutePicker { installRoutePicker(over: speakerCircle, in: speaker) }

        if video {
            let flip = CallSkinCircle(size: size, glyph: 26)
            flip.render(icon: "callskin_ic_flip", active: false)
            let label = CallSkin.label(CallSkin.loc("skin.ctrl_flip"), size: 12, color: t.textColorPrimary)
            items.append(column(circle: flip, label: label, width: width, gap: gap, topPad: topPad) { [weak self] in
                self?.controller.flipCamera()
            })
        }
        otherControls = items.filter { $0 !== hangColumn }
        return spreadRow(items, alignment: .top)
    }

    /// Bluetooth headset connected: a transparent system route picker sits on the speaker button (as the
    /// original TUICallKit did) so the tap opens the system output sheet instead of toggling the speaker.
    private func installRoutePicker(over circle: UIView, in container: UIView) {
        let picker = AVRoutePickerView()
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.tintColor = .clear
        picker.activeTintColor = .clear
        picker.backgroundColor = .clear
        picker.isHidden = true
        container.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            picker.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            picker.widthAnchor.constraint(equalTo: circle.widthAnchor),
            picker.heightAnchor.constraint(equalTo: circle.heightAnchor)
        ])
        routePicker = picker
        routeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            let connected = AudioRouteManager.isBluetoothHeadsetConnected()
            AudioRouteManager.enableiOSAvroutePickerViewMode(connected)
            self?.routePicker?.isHidden = !connected
        }
    }

    private func column(circle: UIView? = nil, view: UIView? = nil, label: UILabel, width: CGFloat, gap: CGFloat,
                        topPad: CGFloat, pressScale: CGFloat = 0.9, action: @escaping () -> Void) -> CallSkinTap {
        let control = CallSkinTap(pressScale: pressScale)
        control.onTap = action
        let main = circle ?? view!
        main.isUserInteractionEnabled = false
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        let stack = UIStackView(arrangedSubviews: [main, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = gap
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        control.addSubview(stack)
        NSLayoutConstraint.activate([
            control.widthAnchor.constraint(equalToConstant: width),
            stack.topAnchor.constraint(equalTo: control.topAnchor, constant: topPad),
            stack.bottomAnchor.constraint(equalTo: control.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: control.centerXAnchor)
        ])
        // Labels can be wider than the 52pt column (design: white-space: nowrap); let them overflow.
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return control
    }

    // MARK: - State

    private func bind() {
        controller.micOn.receive(on: RunLoop.main).sink { [weak self] on in self?.renderMic(on) }.store(in: &cancellables)
        controller.speakerOn.receive(on: RunLoop.main).sink { [weak self] on in self?.renderSpeaker(on) }.store(in: &cancellables)
        if video {
            controller.cameraOn.receive(on: RunLoop.main).sink { [weak self] on in self?.renderCamera(on) }.store(in: &cancellables)
        }
    }

    private func renderMic(_ on: Bool) {
        micCircle.render(icon: on ? "callskin_ic_mic" : "callskin_ic_mic_off", active: on)
        let key: String
        switch (video, on) {
        case (true, true): key = "skin.video_mic_on"
        case (true, false): key = "skin.video_mic_off"
        case (false, true): key = "unmuted"
        case (false, false): key = "muted"
        }
        micLabel.text = CallSkin.loc(key)
    }

    private func renderSpeaker(_ on: Bool) {
        speakerCircle.render(icon: on ? "callskin_ic_speaker" : "callskin_ic_speaker_off", active: on)
        speakerLabel.text = CallSkin.loc(on ? "speakerPhone" : "earpiece")
    }

    private func renderCamera(_ on: Bool) {
        cameraCircle?.render(icon: on ? "callskin_ic_cam" : "callskin_ic_cam_off", active: on)
        cameraLabel?.text = CallSkin.loc(on ? "skin.video_cam_on" : "skin.video_cam_off")
    }

    private func hangUp() {
        guard !hangingUp else { return }
        hangingUp = true
        otherControls.forEach { $0.alpha = 0.8 }
        controller.hangup()
    }
}

/// Incoming-call actions (design `ringScreen`): 拒绝 (hang-up red) and 接听 (accept green, pulsing),
/// 68pt buttons with a 10pt gap to the 12pt label. Reject / accept behave like the original TUICallKit.
final class SocialCalleeActionsView: UIView {
    private let controller: CallSkinController
    private let t = CallSkin.tokens
    private var acted = false
    private var accept: CallSkinTap!
    private var reject: CallSkinTap!

    init(controller: CallSkinController) {
        self.controller = controller
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        reject = action(icon: "callskin_ic_hangup", glyph: 30, fill: t.buttonColorHangupDefault, title: CallSkin.loc("decline")) { [weak self] in
            guard let self, !self.acted else { return }
            self.acted = true
            self.accept.alpha = 0.8
            self.controller.reject()
        }
        accept = action(icon: controller.isVideo ? "callskin_ic_accept_video" : "callskin_ic_accept_phone", glyph: 28,
                        fill: t.buttonColorAccept, title: CallSkin.loc("answer")) { [weak self] in
            guard let self, !self.acted else { return }
            self.acted = true
            self.reject.alpha = 0.8
            self.controller.accept()
        }
        let row = UIStackView(arrangedSubviews: [reject, accept])
        row.axis = .horizontal
        row.alignment = .top
        row.distribution = .equalSpacing
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 52),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -52),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24)
        ])
    }

    private func action(icon: String, glyph: CGFloat, fill: UIColor, title: String, onTap: @escaping () -> Void) -> CallSkinTap {
        let circle = CallSkinCircle(size: 68, glyph: glyph)
        circle.render(icon: icon, active: false, fill: fill, tint: .white)
        let label = CallSkin.label(title, size: 12, color: t.textColorPrimary)
        let control = CallSkinTap()
        control.onTap = onTap
        let stack = UIStackView(arrangedSubviews: [circle, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        control.addSubview(stack)
        NSLayoutConstraint.activate([
            control.widthAnchor.constraint(equalToConstant: 76),
            stack.topAnchor.constraint(equalTo: control.topAnchor),
            stack.bottomAnchor.constraint(equalTo: control.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: control.centerXAnchor)
        ])
        if title == CallSkin.loc("answer") {
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 1.0
            pulse.toValue = 1.08
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            circle.layer.add(pulse, forKey: "ringPulse")
        }
        return control
    }
}
