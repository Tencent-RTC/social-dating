import UIKit
import AtomicX

public enum SocialToast {
    public enum Kind {
        case `default`
        case success
        case warning
        case error
    }

    public enum Duration {
        case short
        case long

        var seconds: TimeInterval {
            switch self {
            case .short: return 2.0
            case .long: return 3.2
            }
        }
    }

    public static func show(_ text: String, kind: Kind = .default, duration: Duration = .short) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if Thread.isMainThread {
            SocialToastCenter.shared.present(text, kind: kind, duration: duration)
        } else {
            DispatchQueue.main.async { SocialToastCenter.shared.present(text, kind: kind, duration: duration) }
        }
    }

    public static func hide() {
        if Thread.isMainThread {
            SocialToastCenter.shared.dismiss(animated: true)
        } else {
            DispatchQueue.main.async { SocialToastCenter.shared.dismiss(animated: true) }
        }
    }
}

private final class SocialToastWindow: UIWindow {
    override var canBecomeKey: Bool { false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self || hit === rootViewController?.view { return nil }
        return hit
    }
}

private final class SocialToastHostController: UIViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle { Host.isDark ? .lightContent : .darkContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
}

private final class SocialToastCenter {
    static let shared = SocialToastCenter()

    private static let enterDuration: TimeInterval = 0.42
    private static let exitDuration: TimeInterval = 0.2
    private static let repeatGuard: TimeInterval = 0.6
    private static let sideGap: CGFloat = 20
    private static let maxWidth: CGFloat = 420

    private var window: SocialToastWindow?
    private var bubble: SocialToastBubble?
    private var timer: Timer?
    private var lastText = ""
    private var lastAt: TimeInterval = 0

    private init() {}

    func present(_ text: String, kind: SocialToast.Kind, duration: SocialToast.Duration) {
        let now = ProcessInfo.processInfo.systemUptime
        if bubble != nil, text == lastText, now - lastAt < Self.repeatGuard { return }
        lastText = text
        lastAt = now
        dismiss(animated: false)
        guard let scene = activeScene() else { return }

        let window = SocialToastWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level.alert + 2
        window.backgroundColor = .clear
        let controller = SocialToastHostController()
        window.rootViewController = controller
        window.isHidden = false

        let bubble = SocialToastBubble(text: text, kind: kind)
        bubble.onTap = { [weak self] in self?.dismiss(animated: true) }
        bubble.onPanBegan = { [weak self] in self?.timer?.invalidate() }
        bubble.onPanEnded = { [weak self] dismissed in
            if dismissed { self?.dismiss(animated: true) } else { self?.scheduleDismiss(.short) }
        }
        let root = controller.view!
        root.addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bubble.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            bubble.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: Self.sideGap),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -Self.sideGap),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxWidth)
        ])
        root.layoutIfNeeded()

        self.window = window
        self.bubble = bubble
        bubble.alpha = 0
        bubble.transform = CGAffineTransform(translationX: 0, y: 14).scaledBy(x: 0.9, y: 0.9)
        UIView.animate(withDuration: Self.enterDuration, delay: 0, usingSpringWithDamping: 0.82,
                       initialSpringVelocity: 0.4, options: [.allowUserInteraction]) {
            bubble.alpha = 1
            bubble.transform = .identity
        }
        haptic(kind)
        UIAccessibility.post(notification: .announcement, argument: text)
        scheduleDismiss(duration)
    }

    func dismiss(animated: Bool) {
        timer?.invalidate()
        timer = nil
        guard let bubble, let window else { return }
        self.bubble = nil
        self.window = nil
        let finish = {
            bubble.removeFromSuperview()
            window.isHidden = true
            window.rootViewController = nil
        }
        guard animated else { finish(); return }
        UIView.animate(withDuration: Self.exitDuration, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            bubble.alpha = 0
            bubble.transform = CGAffineTransform(translationX: 0, y: -8).scaledBy(x: 0.96, y: 0.96)
        } completion: { _ in finish() }
    }

    private func scheduleDismiss(_ duration: SocialToast.Duration) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: duration.seconds, repeats: false) { [weak self] _ in
            self?.dismiss(animated: true)
        }
    }

    private func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private func haptic(_ kind: SocialToast.Kind) {
        let generator = UINotificationFeedbackGenerator()
        switch kind {
        case .success: generator.notificationOccurred(.success)
        case .warning: generator.notificationOccurred(.warning)
        case .error: generator.notificationOccurred(.error)
        case .default: break
        }
    }
}

private final class SocialToastBubble: UIView {
    private static let chipSize: CGFloat = 28
    private static let glyphSize: CGFloat = 16
    private static let tintAlpha: CGFloat = 0.20

    var onTap: (() -> Void)?
    var onPanBegan: (() -> Void)?
    var onPanEnded: ((Bool) -> Void)?

    private let kind: SocialToast.Kind
    private let chip = UIView()
    private let glyph = CAShapeLayer()
    private let chipGradient = CAGradientLayer()
    private let label = UILabel()

    init(text: String, kind: SocialToast.Kind) {
        self.kind = kind
        super.init(frame: .zero)
        build(text)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
        isAccessibilityElement = true
        accessibilityLabel = text
        accessibilityTraits = .staticText
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        chipGradient.frame = chip.bounds
    }

    private func build(_ text: String) {
        let tokens = Host.tokens
        let dark = Host.isDark
        backgroundColor = dark ? tokens.bgColorOperate : tokens.bgColorDialog
        layer.borderWidth = 1
        layer.borderColor = tokens.strokeColorPrimary.cgColor
        layer.shadowColor = tokens.shadowColor.cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)

        let accent = accentColor()
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.layer.cornerRadius = Self.chipSize / 2
        chip.clipsToBounds = true
        if kind == .default {
            chipGradient.colors = [tokens.buttonColorPrimaryDefault.cgColor, tokens.tagColorLevel4.cgColor]
            chipGradient.startPoint = CGPoint(x: 0, y: 0)
            chipGradient.endPoint = CGPoint(x: 1, y: 1)
            chip.layer.addSublayer(chipGradient)
        } else {
            chip.backgroundColor = accent.withAlphaComponent(Self.tintAlpha)
        }
        let glyphColor = kind == .default ? tokens.textColorButton : accent
        configureGlyph(color: glyphColor)
        chip.layer.addSublayer(glyph)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .adaptiveSystemFont(ofSize: 14, weight: .medium)
        label.textColor = tokens.textColorPrimary
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail

        addSubview(chip)
        addSubview(label)
        NSLayoutConstraint.activate([
            chip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            chip.centerYAnchor.constraint(equalTo: centerYAnchor),
            chip.widthAnchor.constraint(equalToConstant: Self.chipSize),
            chip.heightAnchor.constraint(equalToConstant: Self.chipSize),
            label.leadingAnchor.constraint(equalTo: chip.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    private func accentColor() -> UIColor {
        let tokens = Host.tokens
        switch kind {
        case .default: return tokens.buttonColorPrimaryDefault
        case .success: return tokens.textColorSuccess
        case .warning: return tokens.textColorWarning
        case .error: return tokens.textColorError
        }
    }

    private func configureGlyph(color: UIColor) {
        let box = Self.chipSize
        let inset = (box - Self.glyphSize) / 2
        let scale = Self.glyphSize / 16
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: inset + x * scale, y: inset + y * scale) }
        let path = UIBezierPath()
        glyph.frame = CGRect(x: 0, y: 0, width: box, height: box)
        glyph.lineCap = .round
        glyph.lineJoin = .round
        switch kind {
        case .default:
            path.move(to: point(8, 14.2))
            path.addCurve(to: point(2, 6.9), controlPoint1: point(4.1, 11.2), controlPoint2: point(2, 9.3))
            path.addCurve(to: point(5.2, 3.7), controlPoint1: point(2, 5.1), controlPoint2: point(3.4, 3.7))
            path.addCurve(to: point(8, 5.1), controlPoint1: point(6.3, 3.7), controlPoint2: point(7.3, 4.2))
            path.addCurve(to: point(10.8, 3.7), controlPoint1: point(8.7, 4.2), controlPoint2: point(9.7, 3.7))
            path.addCurve(to: point(14, 6.9), controlPoint1: point(12.6, 3.7), controlPoint2: point(14, 5.1))
            path.addCurve(to: point(8, 14.2), controlPoint1: point(14, 9.3), controlPoint2: point(11.9, 11.2))
            path.close()
            glyph.fillColor = color.cgColor
            glyph.strokeColor = nil
        case .success:
            path.move(to: point(3.6, 8.4))
            path.addLine(to: point(6.7, 11.4))
            path.addLine(to: point(12.4, 4.9))
            glyph.fillColor = nil
            glyph.strokeColor = color.cgColor
            glyph.lineWidth = 2 * scale
        case .warning:
            path.move(to: point(8, 3.6))
            path.addLine(to: point(8, 9))
            path.move(to: point(8, 12.2))
            path.addLine(to: point(8, 12.3))
            glyph.fillColor = nil
            glyph.strokeColor = color.cgColor
            glyph.lineWidth = 2.1 * scale
        case .error:
            path.move(to: point(4.6, 4.6))
            path.addLine(to: point(11.4, 11.4))
            path.move(to: point(11.4, 4.6))
            path.addLine(to: point(4.6, 11.4))
            glyph.fillColor = nil
            glyph.strokeColor = color.cgColor
            glyph.lineWidth = 2 * scale
        }
        glyph.path = path.cgPath
    }

    @objc private func tapped() { onTap?() }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let dy = min(0, gesture.translation(in: superview).y)
        switch gesture.state {
        case .began:
            onPanBegan?()
        case .changed:
            transform = CGAffineTransform(translationX: 0, y: dy)
        case .ended, .cancelled, .failed:
            let dismissed = dy < -28 || gesture.velocity(in: superview).y < -400
            if dismissed {
                onPanEnded?(true)
            } else {
                UIView.animate(withDuration: 0.2) { self.transform = .identity }
                onPanEnded?(false)
            }
        default:
            break
        }
    }
}
