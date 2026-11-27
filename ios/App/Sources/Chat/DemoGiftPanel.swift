import UIKit
import TUIHostBase
import AtomicX

/// giftRef -> bundled glyph (same refs as design/fixtures/chat.json `giftPanel.gifts`).
enum DemoGiftIcons {
    private static let names = [
        "star_candy": "demo_gift_star_candy",
        "autumn_tea": "demo_gift_autumn_tea",
        "little_heart": "demo_gift_little_heart",
        "mystery_box": "demo_gift_mystery_box"
    ]

    static func name(_ ref: String) -> String { names[ref] ?? "demo_gift_mystery_box" }
}

/// One-shot gift hearts (prototype `.flyheart`, design S10): 7 small hearts rise from the gift
/// card and fade out over ~2s. Decorative only; skipped when Reduce Motion is on.
enum DemoHeartBurst {
    private static let duration: CFTimeInterval = 2
    private static let stagger: CFTimeInterval = 0.09

    static func play(from target: UIView, count: Int = 7) {
        guard !UIAccessibility.isReduceMotionEnabled, let window = target.window else { return }
        let origin = target.convert(CGPoint(x: target.bounds.midX, y: target.bounds.minY), to: window)
        let image = Host.image("demo_ic_heart_big")?.withRenderingMode(.alwaysTemplate)
        for index in 0..<count {
            let size = CGFloat(14 + Int.random(in: 0..<12))
            let heart = UIImageView(image: image)
            heart.tintColor = Host.tokens.tagColorLevel4
            heart.contentMode = .scaleAspectFit
            heart.isUserInteractionEnabled = false
            heart.frame = CGRect(x: origin.x + CGFloat.random(in: -24..<24) - size / 2, y: origin.y - size / 2, width: size, height: size)
            heart.layer.opacity = 0
            window.addSubview(heart)

            let delay = CFTimeInterval(index) * stagger
            let drift = CGFloat.random(in: -52..<52)
            let rise = 200 + CGFloat.random(in: 0..<60)
            func move(_ keyPath: String, to value: CGFloat) -> CABasicAnimation {
                let animation = CABasicAnimation(keyPath: keyPath)
                animation.fromValue = 0
                animation.toValue = value
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                return animation
            }
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.4, 1, 0.9]
            scale.keyTimes = [0, 0.15, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 0]
            fade.keyTimes = [0, 0.15, 1]
            let group = CAAnimationGroup()
            group.animations = [move("transform.translation.x", to: drift), move("transform.translation.y", to: -rise), scale, fade]
            group.duration = duration
            group.beginTime = CACurrentMediaTime() + delay
            group.fillMode = .both
            heart.layer.add(group, forKey: "demo.heart")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration + 0.05) { heart.removeFromSuperview() }
        }
    }
}

private final class DemoGoldTileView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    init() {
        super.init(frame: .zero)
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        clipsToBounds = false
        setSelected(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSelected(_ selected: Bool) {
        backgroundColor = Host.tokens.textColorPrimary.withAlphaComponent(selected ? 0.11 : 0.055)
        layer.borderWidth = selected ? 2 : 0
        layer.borderColor = Host.tokens.buttonColorPrimaryDefault.cgColor
    }
}

private final class DemoBrandPillView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    init() {
        super.init(frame: .zero)
        let gradient = layer as! CAGradientLayer
        gradient.colors = [Host.tokens.buttonColorPrimaryDefault.cgColor, Host.tokens.tagColorLevel4.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer.cornerRadius = 22
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Gift chooser sheet. No design export exists for it (the prototype's chat gift button sends
/// one fixed gift), so it is composed from existing tokens: `.sheet` surface r16, gift-card gold tile 12 and
/// the brand-gradient pill. Each tap sends one real `chat.card` gift through `onSend`; the combo only
/// decorates this panel and never touches a wallet (spec 03 §5).
final class DemoGiftPanelController: UIViewController {
    private let panel: DemoChatCopy.GiftPanelCopy
    private let onSend: (DemoChatCopy.Gift, @escaping (Int?) -> Void) -> Void

    private let dim = UIView()
    private let sheet = UIView()
    private let sendLabel = UILabel()
    private let comboLabel = UILabel()
    private let sendPill = DemoBrandPillView()
    private var tiles: [(gift: DemoChatCopy.Gift, tile: DemoGoldTileView, column: UIView)] = []
    private var selected: DemoChatCopy.Gift?
    private var busy = false
    private var shown = false

    init(panel: DemoChatCopy.GiftPanelCopy, onSend: @escaping (DemoChatCopy.Gift, @escaping (Int?) -> Void) -> Void) {
        self.panel = panel
        self.onSend = onSend
        self.selected = panel.gifts.first
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let tokens = Host.tokens
        view.backgroundColor = .clear
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        dim.alpha = 0
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        dim.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dim)

        sheet.backgroundColor = tokens.bgColorDialog
        sheet.layer.cornerRadius = 16
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheet.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sheet)

        let title = label(panel.title, 16, tokens.textColorPrimary, bold: true)
        let header = UIStackView(arrangedSubviews: [title, UIView()])
        header.alignment = .center

        let grid = UIStackView()
        grid.axis = .horizontal
        grid.distribution = .fillEqually
        for gift in panel.gifts.prefix(4) {
            let column = makeColumn(gift)
            grid.addArrangedSubview(column)
        }

        sendLabel.font = .adaptiveSystemFont(ofSize: 15, weight: .bold)
        sendLabel.textColor = tokens.textColorButton
        sendLabel.textAlignment = .center
        sendLabel.translatesAutoresizingMaskIntoConstraints = false
        sendPill.addSubview(sendLabel)
        sendPill.isAccessibilityElement = true
        sendPill.accessibilityTraits = .button
        sendPill.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(send)))
        sendPill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sendLabel.centerXAnchor.constraint(equalTo: sendPill.centerXAnchor),
            sendLabel.centerYAnchor.constraint(equalTo: sendPill.centerYAnchor),
            sendPill.heightAnchor.constraint(equalToConstant: 44)
        ])

        comboLabel.font = .adaptiveSystemFont(ofSize: 22, weight: .bold)
        comboLabel.textColor = tokens.textColorWarning
        comboLabel.textAlignment = .center
        comboLabel.alpha = 0
        comboLabel.translatesAutoresizingMaskIntoConstraints = false

        let content = UIStackView(arrangedSubviews: [header, grid, sendPill])
        content.axis = .vertical
        content.spacing = 12
        content.setCustomSpacing(22, after: grid)
        content.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(content)
        view.addSubview(comboLabel)

        NSLayoutConstraint.activate([
            dim.topAnchor.constraint(equalTo: view.topAnchor), dim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dim.leadingAnchor.constraint(equalTo: view.leadingAnchor), dim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor), sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheet.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: sheet.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            comboLabel.centerXAnchor.constraint(equalTo: sendPill.centerXAnchor),
            comboLabel.bottomAnchor.constraint(equalTo: sendPill.topAnchor, constant: -4)
        ])
        select(selected)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !shown else { return }
        shown = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.layoutIfNeeded()
        sheet.transform = CGAffineTransform(translationX: 0, y: sheet.bounds.height)
        UIView.animate(withDuration: 0.28, delay: 0, options: .curveEaseOut) {
            self.sheet.transform = .identity
            self.dim.alpha = 1
        }
    }

    private func label(_ text: String, _ size: CGFloat, _ color: UIColor, bold: Bool = false) -> UILabel {
        let item = UILabel()
        item.text = text
        item.font = .adaptiveSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        item.textColor = color
        return item
    }

    private func makeColumn(_ gift: DemoChatCopy.Gift) -> UIView {
        let tokens = Host.tokens
        let tile = DemoGoldTileView()
        tile.translatesAutoresizingMaskIntoConstraints = false
        let glyph = UIImageView(image: Host.image(DemoGiftIcons.name(gift.ref)))
        glyph.contentMode = .scaleAspectFit
        glyph.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(glyph)
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 64), tile.heightAnchor.constraint(equalToConstant: 64),
            glyph.centerXAnchor.constraint(equalTo: tile.centerXAnchor), glyph.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 48), glyph.heightAnchor.constraint(equalToConstant: 48)
        ])
        let name = label(gift.name, 11, tokens.textColorSecondary)
        let worth = label("\(gift.value) \(gift.unit)", 10, tokens.textColorTertiary)
        let column = UIStackView(arrangedSubviews: [tile, name, worth])
        column.axis = .vertical
        column.alignment = .center
        column.setCustomSpacing(6, after: tile)
        column.setCustomSpacing(1, after: name)
        column.isAccessibilityElement = true
        column.accessibilityTraits = .button
        column.accessibilityLabel = "\(gift.name)，\(gift.value) \(gift.unit)"
        column.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tileTapped(_:))))
        tiles.append((gift, tile, column))
        return column
    }

    private func select(_ gift: DemoChatCopy.Gift?) {
        guard let gift else { return }
        selected = gift
        for item in tiles {
            let on = item.gift.ref == gift.ref
            item.tile.setSelected(on)
            item.column.alpha = on ? 1 : 0.86
        }
        sendLabel.text = "\(panel.sendText)「\(gift.name)」"
        sendPill.accessibilityLabel = sendLabel.text
    }

    @objc private func tileTapped(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view, let item = tiles.first(where: { $0.column === view }) else { return }
        select(item.gift)
    }

    @objc private func send() {
        guard let gift = selected, !busy else { return }
        busy = true
        sendPill.alpha = 0.7
        onSend(gift) { [weak self] combo in
            guard let self else { return }
            self.busy = false
            self.sendPill.alpha = 1
            if let combo { self.showCombo(combo) }
        }
    }

    private func showCombo(_ combo: Int) {
        comboLabel.text = "×\(combo)"
        comboLabel.layer.removeAllAnimations()
        comboLabel.alpha = 0
        comboLabel.transform = CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.7, y: 0.7)
        UIView.animate(withDuration: 0.16, animations: {
            self.comboLabel.alpha = 1
            self.comboLabel.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }, completion: { _ in
            UIView.animate(withDuration: 0.42, delay: 0.6, options: [], animations: {
                self.comboLabel.alpha = 0
                self.comboLabel.transform = CGAffineTransform(translationX: 0, y: -12)
            })
        })
    }

    @objc private func close() {
        UIView.animate(withDuration: 0.2, animations: {
            self.sheet.transform = CGAffineTransform(translationX: 0, y: self.sheet.bounds.height)
            self.dim.alpha = 0
        }, completion: { _ in self.dismiss(animated: false) })
    }
}
