//
//  CallSkin.swift
//  Design S9 / S10 call-page skin helpers (Chat 1v1).
//
//  The call page is always rendered with the **dark** tokens of the user's current social palette
//  (design: screen root carries data-mode="dark"), regardless of the app-wide light / dark mode.
//  Everything is code-drawn from tokens; only glyphs are PNG templates tinted at runtime.
//

import UIKit
import AtomicX
import AtomicXCore
import Combine

enum CallSkin {
    /// Resting state of the translucent round call buttons: deep, mostly opaque scrim + thin white rim
    /// (same values as Android `CallSkin.OFF_FILL` / `OFF_RIM`).
    static let offFill = UIColor(red: 0x10 / 255, green: 0x12 / 255, blue: 0x18 / 255, alpha: 0xB3 / 255)
    static let offRim = UIColor(white: 1, alpha: 0x38 / 255)

    static var tokens: ColorTokens {
        Theme.darkTheme.tokens.color.applying(palette: ThemeStore.shared.currentPaletteKey, dark: true)
    }

    static func loc(_ key: String) -> String {
        CallKitLocalization.localized(key)
    }

    static func image(_ name: String, template: Bool = true) -> UIImage? {
        guard let image = CallKitBundle.getBundleImage(name: name) else { return nil }
        return template ? image.withRenderingMode(.alwaysTemplate) : image
    }

    static func glyph(_ name: String, size: CGFloat, tint: UIColor?) -> UIImageView {
        let view = UIImageView(image: image(name, template: tint != nil))
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        if let tint { view.tintColor = tint }
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        return view
    }

    static func label(_ text: String, size: CGFloat, color: UIColor, bold: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: bold ? .bold : .regular)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        // Call labels sit on a live camera picture of any brightness; a soft shadow keeps them readable.
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.43
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
        return label
    }

    static func lerp(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}

/// Plain gradient-backed view (layerClass), used for capsules, the gift base and the shades.
final class CallSkinGradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradient: CAGradientLayer { layer as! CAGradientLayer }

    init(colors: [UIColor], start: CGPoint, end: CGPoint, locations: [NSNumber]? = nil) {
        super.init(frame: .zero)
        gradient.colors = colors.map { $0.cgColor }
        gradient.startPoint = start
        gradient.endPoint = end
        gradient.locations = locations
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Round 48 / 52 / 60 call button: translucent `buttonColorOff`, or white `buttonColorOn` when active.
final class CallSkinCircle: UIView {
    private let glyph = UIImageView()
    private let glyphSize: CGFloat

    init(size: CGFloat, glyph glyphSize: CGFloat) {
        self.glyphSize = glyphSize
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = size / 2
        isUserInteractionEnabled = false
        glyph.contentMode = .scaleAspectFit
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: glyphSize),
            glyph.heightAnchor.constraint(equalToConstant: glyphSize)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func render(icon: String, active: Bool, fill: UIColor? = nil, tint: UIColor? = nil) {
        let t = CallSkin.tokens
        backgroundColor = fill ?? (active ? t.buttonColorOn : CallSkin.offFill)
        // Resting state also gets a thin white rim so the circle reads on very dark (or very bright) video.
        layer.borderWidth = (fill == nil && !active) ? 1 : 0
        layer.borderColor = CallSkin.offRim.cgColor
        glyph.image = CallSkin.image(icon)
        glyph.tintColor = tint ?? (active ? t.bgColorDefault : .white)
    }
}

/// Tappable column with press feedback (design `:active { transform: scale(.9) }`).
final class CallSkinTap: UIControl {
    private let pressScale: CGFloat
    var onTap: (() -> Void)?

    init(pressScale: CGFloat = 0.9) {
        self.pressScale = pressScale
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: isHighlighted ? 0.09 : 0.14) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: self.pressScale, y: self.pressScale) : .identity
            }
        }
    }

    @objc private func tapped() { onTap?() }
}

public enum CallGiftBridge {
    public static var sender: ((_ peerId: String, _ onResult: @escaping (Bool) -> Void) -> Void)?
    public static var inspector: ((_ customData: String?) -> String?)?
}

/// State of the entertainment layer (topic card, gift banner) plus the request to open the sound / beauty panel.
/// Nothing here changes the SDK call state. The gift is handed to `CallGiftBridge` so the host can send it as a
/// real custom message and the peer's call page can show it too.
final class CallSkinHub {
    let topicChanged = PassthroughSubject<Void, Never>()
    let giftSent = PassthroughSubject<Int, Never>()
    let peerGiftReceived = PassthroughSubject<(name: String, combo: Int), Never>()
    private(set) var peerGiftCombo = 0

    static let topicCount = 12
    /// Each call starts on a different topic, so two calls in a row do not open with the same question.
    private(set) var topicIndex = Int.random(in: 0..<CallSkinHub.topicCount)
    private(set) var topicVisible = false
    private(set) var giftCombo = 0
    private var giftToastShown = false

    var topicText: String { CallSkin.loc("skin.topic_\(topicIndex % Self.topicCount + 1)") }
    var topicTitle: String { CallSkin.loc("skin.topic_title_\(topicIndex % Self.topicCount + 1)") }
    var giftName: String { CallSkin.loc("skin.gift_name") }

    func nextTopic() {
        topicIndex = (topicIndex + 1) % Self.topicCount
        topicChanged.send()
    }

    func toggleTopic() {
        topicVisible.toggle()
        topicChanged.send()
    }

    func showTopic(_ visible: Bool) {
        topicVisible = visible
        topicChanged.send()
    }

    /// Set by the call view; opens the sound-effect or beauty sheet above the whole call page.
    var panelOpener: ((CallEffectsPanel.Kind) -> Void)?

    func openPanel(_ kind: CallEffectsPanel.Kind) { panelOpener?(kind) }

    func peerId() -> String? {
        let state = CallStore.shared.state.value
        return state.allParticipants.first(where: { $0.id != state.selfInfo.id })?.id
    }

    @discardableResult
    func sendGift(onFailed: @escaping () -> Void = {}) -> Bool {
        giftCombo += 1
        giftSent.send(giftCombo)
        if let sender = CallGiftBridge.sender, let peer = peerId(), !peer.isEmpty {
            sender(peer) { ok in if !ok { onFailed() } }
        }
        defer { giftToastShown = true }
        return !giftToastShown
    }

    func receivePeerGift(_ name: String) {
        peerGiftCombo += 1
        peerGiftReceived.send((name, peerGiftCombo))
    }
}
