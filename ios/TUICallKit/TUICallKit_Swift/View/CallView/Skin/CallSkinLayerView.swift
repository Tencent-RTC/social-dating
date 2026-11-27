//
//  CallSkinLayerView.swift
//  Overlay above the SDK call picture: peer name, voice-page safety tip, the draggable topic card, and the
//  gift banner / flying hearts (own gifts and gifts received from the peer as custom messages). It never
//  intercepts touches except on the topic card (tap "next", or drag the card anywhere).
//

import UIKit
import SDWebImage
import Combine
import AtomicX
import AtomicXCore

/// S9 background: dark scrim over the blurred peer avatar + a palette-coloured glow behind the avatar.
final class CallVoiceShadeView: UIView {
    private let t = CallSkin.tokens

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let space = CGColorSpaceCreateDeviceRGB()
        let bg = t.bgColorDefault
        let scrimColors = [bg.withAlphaComponent(0.35).cgColor, bg.withAlphaComponent(0.60).cgColor, bg.withAlphaComponent(0.94).cgColor] as CFArray
        if let scrim = CGGradient(colorsSpace: space, colors: scrimColors, locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(scrim, start: .zero, end: CGPoint(x: 0, y: bounds.height), options: [])
        }
        // Design `.callglow`: 440x360 box at (-40,108), radial primary colour at 50% opacity.
        let scale = bounds.width / 360
        ctx.saveGState()
        ctx.translateBy(x: bounds.midX, y: (108 + 180) * scale)
        ctx.scaleBy(x: 220 * scale, y: 180 * scale)
        let glowColors = [t.buttonColorPrimaryDefault.withAlphaComponent(0.5).cgColor, t.buttonColorPrimaryDefault.withAlphaComponent(0).cgColor] as CFArray
        if let glow = CGGradient(colorsSpace: space, colors: glowColors, locations: [0, 1]) {
            ctx.drawRadialGradient(glow, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        }
        ctx.restoreGState()
    }
}

/// S10 shades: soft black gradients over the remote picture, drawn *under* the control buttons.
/// Kept light on purpose: the first version (0.55 top / 0.92 bottom, over the controls too) made the picture
/// look dim and the buttons look covered. The round buttons carry their own translucent fill for legibility.
final class CallVideoShadeView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let space = CGColorSpaceCreateDeviceRGB()
        let topColors = [UIColor.black.withAlphaComponent(0.35).cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
        if let top = CGGradient(colorsSpace: space, colors: topColors, locations: [0, 1]) {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: bounds.width, height: 180))
            ctx.drawLinearGradient(top, start: .zero, end: CGPoint(x: 0, y: 180), options: [])
            ctx.restoreGState()
        }
        let start = bounds.height * 0.58
        let bottomColors = [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.27).cgColor,
                            UIColor.black.withAlphaComponent(0.47).cgColor, UIColor.black.withAlphaComponent(0.59).cgColor] as CFArray
        if let bottom = CGGradient(colorsSpace: space, colors: bottomColors, locations: [0, 0.35, 0.7, 1]) {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: start, width: bounds.width, height: bounds.height - start))
            ctx.drawLinearGradient(bottom, start: CGPoint(x: 0, y: start), end: CGPoint(x: 0, y: bounds.height), options: [])
            ctx.restoreGState()
        }
    }
}

final class CallSkinLayerView: UIView {
    private let hub: CallSkinHub
    private let video: Bool
    private let t = CallSkin.tokens
    private let nameLabel = CallSkin.label("", size: 16, color: CallSkin.tokens.textColorPrimary, bold: true)
    private var topicCard: UIView?
    private var topicTitleLabel: UILabel?
    private var topicBody: UILabel?
    private var topicCenterX: NSLayoutConstraint?
    private var topicTop: NSLayoutConstraint?
    private var topicPlaced = false
    private var banner: UIView?
    private var bannerCombo: UILabel?
    private var bannerAvatar: UILabel?
    private var bannerAvatarImage: UIImageView?
    private var bannerWho: UILabel?
    private var bannerWhat: UILabel?
    private var peerName = ""
    private var peerMessageStore: MessageListStore?
    private var peerMessageCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var heartCount = 0
    private var bannerWork: DispatchWorkItem?

    init(hub: CallSkinHub, video: Bool) {
        self.hub = hub
        self.video = video
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        build()
        hub.topicChanged.receive(on: RunLoop.main).sink { [weak self] in self?.renderTopic() }.store(in: &cancellables)
        // Voice calls open with the topic card showing; video calls open with it hidden and the 话题 button brings it up.
        if !video { hub.showTopic(true) }
        hub.giftSent.receive(on: RunLoop.main).sink { [weak self] combo in
            guard let self else { return }
            self.showGift(combo, fromPeer: false, giftName: self.hub.giftName)
        }.store(in: &cancellables)
        hub.peerGiftReceived.receive(on: RunLoop.main).sink { [weak self] item in
            guard let self else { return }
            self.showGift(item.combo, fromPeer: true, giftName: item.name.isEmpty ? self.hub.giftName : item.name)
        }.store(in: &cancellables)
        listenPeerGifts()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    func setPeerName(_ name: String) {
        peerName = name
        nameLabel.text = name
    }

    private func listenPeerGifts() {
        guard CallGiftBridge.inspector != nil else { return }
        CallStore.shared.state.subscribe(StatePublisherSelector(keyPath: \.allParticipants))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.bindPeerStore() }
            .store(in: &cancellables)
        bindPeerStore()
    }

    private func bindPeerStore() {
        guard let peer = hub.peerId(), !peer.isEmpty else { return }
        let conversationID = "c2c_\(peer)"
        if peerMessageStore?.conversationID == conversationID { return }
        let store = MessageListStore.create(conversationID: conversationID)
        var option = MessageLoadOption()
        option.pageCount = 1
        store.loadMessages(option: option)
        peerMessageStore = store
        peerMessageCancellable = store.messageEventPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self, case .onReceiveNewMessage(let message) = event, !message.isSentBySelf,
                      case .custom(let payload) = message.messagePayload,
                      let name = CallGiftBridge.inspector?(payload.customData) else { return }
                self.hub.receivePeerGift(name)
            }
    }

    private func build() {
        nameLabel.textAlignment = .center
        nameLabel.layer.shadowColor = UIColor.black.cgColor
        nameLabel.layer.shadowOpacity = 0.35
        nameLabel.layer.shadowRadius = 2
        nameLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(nameLabel)
        NSLayoutConstraint.activate([
            nameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            nameLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 64),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -64)
        ])
        buildTopicCard()
    }

    // MARK: Topic card (draggable)

    private var topicCardWidth: CGFloat { video ? 220 : 288 }

    private func buildTopicCard() {
        let pad: CGFloat = video ? 12 : 14
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = t.bgColorTagMask
        card.layer.cornerRadius = 16
        card.alpha = 0
        card.isHidden = true
        let bulb = CallSkin.glyph("callskin_ic_bulb", size: 14, tint: t.textColorWarning)
        let from = CallSkin.label(hub.topicTitle, size: 12, color: t.textColorWarning, bold: true)
        from.lineBreakMode = .byTruncatingTail
        from.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let next = CallSkinTap(pressScale: 0.95)
        let refresh = CallSkin.glyph("callskin_ic_refresh", size: 12, tint: t.textColorSecondary)
        let nextText = CallSkin.label(CallSkin.loc("skin.topic_next"), size: 12, color: t.textColorSecondary)
        refresh.isUserInteractionEnabled = false
        nextText.isUserInteractionEnabled = false
        next.addSubview(refresh)
        next.addSubview(nextText)
        NSLayoutConstraint.activate([
            refresh.leadingAnchor.constraint(equalTo: next.leadingAnchor),
            refresh.centerYAnchor.constraint(equalTo: next.centerYAnchor),
            nextText.leadingAnchor.constraint(equalTo: refresh.trailingAnchor, constant: 4),
            nextText.trailingAnchor.constraint(equalTo: next.trailingAnchor),
            nextText.topAnchor.constraint(equalTo: next.topAnchor),
            nextText.bottomAnchor.constraint(equalTo: next.bottomAnchor)
        ])
        next.onTap = { [weak self] in self?.hub.nextTopic() }
        let body = UILabel()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.numberOfLines = 0
        body.attributedText = topicAttributed()
        [bulb, from, next, body].forEach(card.addSubview)
        addSubview(card)
        let centerX = card.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 0)
        let top = card.topAnchor.constraint(equalTo: topAnchor, constant: 0)
        topicCenterX = centerX
        topicTop = top
        NSLayoutConstraint.activate([
            centerX, top,
            card.widthAnchor.constraint(equalToConstant: topicCardWidth),
            bulb.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: pad),
            bulb.topAnchor.constraint(equalTo: card.topAnchor, constant: pad - 2),
            from.leadingAnchor.constraint(equalTo: bulb.trailingAnchor, constant: 6),
            from.centerYAnchor.constraint(equalTo: bulb.centerYAnchor),
            next.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -pad),
            next.centerYAnchor.constraint(equalTo: bulb.centerYAnchor),
            next.leadingAnchor.constraint(greaterThanOrEqualTo: from.trailingAnchor, constant: 8),
            body.topAnchor.constraint(equalTo: bulb.bottomAnchor, constant: 6),
            body.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: pad),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -pad),
            body.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -pad)
        ])
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panTopic(_:)))
        card.addGestureRecognizer(pan)
        topicCard = card
        topicTitleLabel = from
        topicBody = body
    }

    private func topicAttributed() -> NSAttributedString {
        SocialCallControlsView.topicText(hub.topicText, color: t.textColorPrimary, size: video ? 13 : 14, line: video ? 19 : 21)
    }

    /// First layout: video opens at the top left under the header, voice above the function row. After that the
    /// position belongs to the user; layout only keeps the card inside the screen (a longer topic grows downwards).
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let card = topicCard, bounds.width > 0 else { return }
        if !topicPlaced {
            topicPlaced = true
            if video {
                topicCenterX?.constant = 16 + topicCardWidth / 2
                topicTop?.constant = safeAreaInsets.top + 56
            } else {
                let height = card.systemLayoutSizeFitting(
                    CGSize(width: topicCardWidth, height: UIView.layoutFittingCompressedSize.height),
                    withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
                topicCenterX?.constant = bounds.width / 2
                topicTop?.constant = bounds.height - 270 - height
            }
        }
        clampTopicCard()
    }

    private func clampTopicCard() {
        guard let card = topicCard, let centerX = topicCenterX, let top = topicTop else { return }
        let half = topicCardWidth / 2
        let x = min(max(centerX.constant, half), max(half, bounds.width - half))
        let minTop = safeAreaInsets.top
        let y = min(max(top.constant, minTop), max(minTop, bounds.height - card.bounds.height))
        if x != centerX.constant { centerX.constant = x }
        if y != top.constant { top.constant = y }
    }

    @objc private func panTopic(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed, let centerX = topicCenterX, let top = topicTop else { return }
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        centerX.constant += delta.x
        top.constant += delta.y
        clampTopicCard()
    }

    private func renderTopic() {
        topicTitleLabel?.text = hub.topicTitle
        topicBody?.attributedText = topicAttributed()
        guard let card = topicCard else { return }
        if hub.topicVisible, card.isHidden {
            card.isHidden = false
            card.alpha = 0
            card.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            UIView.animate(withDuration: 0.22) { card.alpha = 1; card.transform = .identity }
        } else if !hub.topicVisible, !card.isHidden {
            UIView.animate(withDuration: 0.16, animations: { card.alpha = 0 }, completion: { _ in card.isHidden = true })
        }
    }

    // MARK: Gift (local only)

    private func showGift(_ combo: Int, fromPeer: Bool, giftName: String) {
        if video {
            ensureBanner()
            let who = fromPeer ? (peerName.isEmpty ? CallSkin.loc("skin.gift_banner_peer") : peerName) : CallSkin.loc("skin.gift_banner_me")
            bannerAvatar?.text = String(who.prefix(1))
            bindBannerAvatar(fromPeer: fromPeer)
            bannerWho?.text = who
            // A gift from the peer is addressed to this user: "<peer> sent you <gift>"; our own is "Me sent <gift>".
            bannerWhat?.text = String(format: CallSkin.loc(fromPeer ? "skin.gift_banner_to_you" : "skin.gift_banner_send"), giftName)
            bannerCombo?.text = "×\(combo)"
            banner?.layer.removeAllAnimations()
            banner?.alpha = 1
            bannerWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                UIView.animate(withDuration: 0.32) { self?.banner?.alpha = 0 }
            }
            bannerWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
        }
        for _ in 0..<3 { flyHeart() }
    }

    private func bindBannerAvatar(fromPeer: Bool) {
        guard let image = bannerAvatarImage else { return }
        let state = CallStore.shared.state.value
        let url = fromPeer
            ? state.allParticipants.first(where: { $0.id != state.selfInfo.id })?.avatarURL
            : state.selfInfo.avatarURL
        guard let url, !url.isEmpty, let link = URL(string: url) else {
            image.sd_cancelCurrentImageLoad()
            image.image = nil
            return
        }
        image.sd_setImage(with: link)
    }

    private func ensureBanner() {
        guard banner == nil else { return }
        let bar = CallSkinGradientView(
            colors: [t.buttonColorPrimaryDefault.withAlphaComponent(0.85), t.tagColorLevel4.withAlphaComponent(0.85), .clear],
            start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5), locations: [0, 0.7, 1])
        bar.layer.cornerRadius = 22
        bar.clipsToBounds = true
        let avatar = UILabel()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.text = CallSkin.loc("skin.gift_banner_me")
        avatar.font = .systemFont(ofSize: 12)
        avatar.textColor = t.textColorButton
        avatar.textAlignment = .center
        avatar.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        avatar.layer.cornerRadius = 18
        avatar.clipsToBounds = true
        let avatarImage = UIImageView()
        avatarImage.translatesAutoresizingMaskIntoConstraints = false
        avatarImage.contentMode = .scaleAspectFill
        avatarImage.clipsToBounds = true
        avatarImage.layer.cornerRadius = 18
        avatar.addSubview(avatarImage)
        NSLayoutConstraint.activate([
            avatarImage.topAnchor.constraint(equalTo: avatar.topAnchor), avatarImage.bottomAnchor.constraint(equalTo: avatar.bottomAnchor),
            avatarImage.leadingAnchor.constraint(equalTo: avatar.leadingAnchor), avatarImage.trailingAnchor.constraint(equalTo: avatar.trailingAnchor)
        ])
        bannerAvatarImage = avatarImage
        let who = CallSkin.label(CallSkin.loc("skin.gift_banner_me"), size: 12, color: t.textColorPrimary, bold: true)
        let what = CallSkin.label(String(format: CallSkin.loc("skin.gift_banner_send"), hub.giftName), size: 12, color: t.textColorSecondary)
        let texts = UIStackView(arrangedSubviews: [who, what])
        texts.axis = .vertical
        texts.translatesAutoresizingMaskIntoConstraints = false
        let candy = CallSkin.glyph("callskin_ic_gift_candy", size: 36, tint: nil)
        candy.image = CallSkin.image("callskin_ic_gift_candy", template: false)
        let combo = CallSkin.label("×1", size: 22, color: t.textColorWarning, bold: true)
        combo.layer.shadowColor = UIColor(red: 1, green: 0.44, blue: 0.18, alpha: 1).cgColor
        combo.layer.shadowOpacity = 0.6
        combo.layer.shadowRadius = 2
        combo.layer.shadowOffset = CGSize(width: 0, height: 2)
        [avatar, texts, candy, combo].forEach(bar.addSubview)
        addSubview(bar)
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: 44),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -274 - 0),
            avatar.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 4),
            avatar.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 36),
            avatar.heightAnchor.constraint(equalToConstant: 36),
            texts.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 8),
            texts.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            candy.leadingAnchor.constraint(equalTo: texts.trailingAnchor, constant: 8),
            candy.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            combo.leadingAnchor.constraint(equalTo: candy.trailingAnchor, constant: 8),
            combo.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            combo.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -24)
        ])
        banner = bar
        bannerCombo = combo
        bannerAvatar = avatar
        bannerWho = who
        bannerWhat = what
    }

    private func flyHeart() {
        let colors = [t.tagColorLevel4, t.buttonColorPrimaryDefault, t.tagColorLevel4, t.textColorWarning, t.buttonColorPrimaryDefault]
        let size = CGFloat(14 + (heartCount % 3) * 7)
        let color = colors[heartCount % colors.count]
        let offset = CGFloat(22 + (heartCount * 17) % 44)
        heartCount += 1
        let heart = CallSkin.glyph("callskin_ic_heart", size: size, tint: color)
        addSubview(heart)
        NSLayoutConstraint.activate([
            heart.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -offset),
            heart.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -250)
        ])
        layoutIfNeeded()
        let delay = Double(heartCount % 3) * 0.12
        UIView.animate(withDuration: 1.8, delay: delay, options: [.curveEaseOut], animations: {
            heart.transform = CGAffineTransform(translationX: 0, y: -(190 + CGFloat(self.heartCount) * 9))
        })
        UIView.animate(withDuration: 1.8, delay: 0.7 + delay, options: [], animations: { heart.alpha = 0 }, completion: { _ in
            heart.removeFromSuperview()
        })
    }
}
