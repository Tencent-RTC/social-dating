import UIKit

public enum MsgBanner {
    public struct Model {
        public let key: String
        public let title: String
        public let summary: String
        /// Optional rich summary (emoji pictures); the plain [summary] stays the accessibility text.
        public let attributedSummary: NSAttributedString?
        public let time: String
        public let avatar: String?

        public init(key: String, title: String, summary: String, attributedSummary: NSAttributedString? = nil, time: String, avatar: String?) {
            self.attributedSummary = attributedSummary
            self.key = key
            self.title = title
            self.summary = summary
            self.time = time
            self.avatar = avatar
        }
    }

    public static var isForeground: Bool {
        UIApplication.shared.applicationState == .active
    }

    @discardableResult
    public static func show(_ model: Model, onTap: @escaping () -> Void) -> Bool {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { _ = MsgBannerCenter.shared.present(model, onTap: onTap) }
            return true
        }
        return MsgBannerCenter.shared.present(model, onTap: onTap)
    }

    public static func hide() {
        if Thread.isMainThread {
            MsgBannerCenter.shared.dismiss(animated: true)
        } else {
            DispatchQueue.main.async { MsgBannerCenter.shared.dismiss(animated: true) }
        }
    }
}

private final class MsgBannerWindow: UIWindow {
    override var canBecomeKey: Bool { false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self || hit === rootViewController?.view { return nil }
        return hit
    }
}

private final class MsgBannerHostController: UIViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle { Host.isDark ? .lightContent : .darkContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
}

private final class MsgBannerCenter {
    static let shared = MsgBannerCenter()

    private static let enterDuration: TimeInterval = 0.36
    private static let swapDuration: TimeInterval = 0.28
    private static let exitDuration: TimeInterval = 0.24
    private static let autoHide: TimeInterval = 3.5
    private static let sideGap: CGFloat = 8
    private static let topGap: CGFloat = 8
    private static let maxWidth: CGFloat = 560

    private var window: MsgBannerWindow?
    private var banner: MsgBannerView?
    private var timer: Timer?

    private init() {}

    func present(_ model: MsgBanner.Model, onTap: @escaping () -> Void) -> Bool {
        guard let scene = activeScene() else { return false }
        let swapping = banner != nil
        let controller: MsgBannerHostController
        if let window, swapping, let existing = window.rootViewController as? MsgBannerHostController {
            controller = existing
            banner?.removeFromSuperview()
        } else {
            dismiss(animated: false)
            let window = MsgBannerWindow(windowScene: scene)
            window.windowLevel = UIWindow.Level.alert + 1
            window.backgroundColor = .clear
            controller = MsgBannerHostController()
            window.rootViewController = controller
            window.isHidden = false
            self.window = window
        }
        let view = MsgBannerView(model: model)
        view.onTap = { [weak self] in
            self?.dismiss(animated: false)
            onTap()
        }
        view.onPanBegan = { [weak self] in self?.timer?.invalidate() }
        view.onPanEnded = { [weak self] dismissed in
            if dismissed { self?.dismiss(animated: true) } else { self?.scheduleDismiss() }
        }
        let root = controller.view!
        root.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        let width = view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -Self.sideGap * 2)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: Self.topGap),
            view.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            width,
            view.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxWidth)
        ])
        root.layoutIfNeeded()
        banner = view
        if swapping {
            view.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
            UIView.animate(withDuration: Self.swapDuration, delay: 0, usingSpringWithDamping: 0.55,
                           initialSpringVelocity: 0.6, options: [.allowUserInteraction]) { view.transform = .identity }
        } else {
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: -120)
            UIView.animate(withDuration: Self.enterDuration, delay: 0, usingSpringWithDamping: 0.78,
                           initialSpringVelocity: 0.5, options: [.allowUserInteraction]) {
                view.alpha = 1
                view.transform = .identity
            }
        }
        UIAccessibility.post(notification: .announcement, argument: "\(model.title), \(model.summary)")
        scheduleDismiss()
        return true
    }

    func dismiss(animated: Bool) {
        timer?.invalidate()
        timer = nil
        guard let banner, let window else {
            self.banner = nil
            self.window = nil
            return
        }
        self.banner = nil
        self.window = nil
        let finish = {
            banner.removeFromSuperview()
            window.isHidden = true
            window.rootViewController = nil
        }
        guard animated else { finish(); return }
        UIView.animate(withDuration: Self.exitDuration, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            banner.alpha = 0
            banner.transform = CGAffineTransform(translationX: 0, y: -120)
        } completion: { _ in finish() }
    }

    private func scheduleDismiss() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.autoHide, repeats: false) { [weak self] _ in
            self?.dismiss(animated: true)
        }
    }

    private func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
    }
}

private final class MsgBannerView: UIView {
    var onTap: (() -> Void)?
    var onPanBegan: (() -> Void)?
    var onPanEnded: ((Bool) -> Void)?

    private static let avatarSize: CGFloat = 40
    private static let dismissDistance: CGFloat = 24

    init(model: MsgBanner.Model) {
        super.init(frame: .zero)
        let tokens = Host.tokens
        let dark = Host.isDark
        backgroundColor = (dark ? tokens.bgColorOperate : tokens.bgColorDialog).withAlphaComponent(1)
        layer.cornerRadius = 18
        layer.borderWidth = 1
        layer.borderColor = tokens.strokeColorPrimary.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = dark ? 0.45 : 0.18
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 10)

        let avatar = DemoRemoteAvatar(name: model.title, url: model.avatar, size: Self.avatarSize)
        let name = label(model.title, 14, tokens.textColorPrimary, bold: true)
        name.numberOfLines = 1
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let time = label(model.time, 11, tokens.textColorTertiary)
        time.numberOfLines = 1
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        let top = UIStackView(arrangedSubviews: [name, time])
        top.axis = .horizontal
        top.alignment = .center
        top.spacing = 8
        let summary = label(model.summary, 13, tokens.textColorSecondary)
        if let rich = model.attributedSummary { summary.attributedText = rich }
        summary.numberOfLines = 1
        summary.lineBreakMode = .byTruncatingTail
        let texts = UIStackView(arrangedSubviews: [top, summary])
        texts.axis = .vertical
        texts.spacing = 4
        let row = UIStackView(arrangedSubviews: [avatar, texts])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
        isAccessibilityElement = true
        accessibilityLabel = "\(model.title), \(model.summary)"
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 18).cgPath
    }

    @objc private func tapped() { onTap?() }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let dy = gesture.translation(in: superview).y
        switch gesture.state {
        case .began:
            onPanBegan?()
        case .changed:
            transform = CGAffineTransform(translationX: 0, y: min(0, dy))
        case .ended, .cancelled, .failed:
            let dismissed = gesture.state == .ended && dy < -Self.dismissDistance
            if !dismissed {
                UIView.animate(withDuration: 0.18) { self.transform = .identity }
            }
            onPanEnded?(dismissed)
        default:
            break
        }
    }
}
