import UIKit
import AtomicX
import SDWebImage

extension Array {
    public subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Host colours are read from the current social palette on every access (S05); screens are
/// rebuilt on `DemoThemeCoordinator.didChange`, so no colour is cached across a theme change.
public enum Palette {
    private static var tokens: ColorTokens { ThemeStore.shared.colorTokens }
    public static var bg: UIColor { tokens.bgColorDefault }
    public static var surface: UIColor { tokens.bgColorEntryCard }
    public static var surfaceHigh: UIColor { tokens.bgColorFunction }
    public static var text: UIColor { tokens.textColorPrimary }
    public static var muted: UIColor { tokens.textColorSecondary }
    public static var accent: UIColor { tokens.buttonColorPrimaryDefault }
    public static var success: UIColor { tokens.textColorSuccess }
    /// Brand gradient end (`tagColorLevel4`), own bubble / send button / primary tile.
    public static var brandEnd: UIColor { tokens.tagColorLevel4 }
    public static var bubbleIn: UIColor { tokens.bgColorBubbleReciprocal }
    public static var input: UIColor { tokens.bgColorInput }
    public static var bar: UIColor { tokens.bgColorOperate }
    public static var selected: UIColor { tokens.tabColorSelected }
    public static var stroke: UIColor { tokens.strokeColorPrimary }
    public static var onAccent: UIColor { tokens.textColorButton }
}

extension UIColor {
    public convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

public func label(_ text: String, _ size: CGFloat, _ color: UIColor = Palette.text, bold: Bool = false) -> UILabel {
    let view = UILabel()
    view.text = text
    view.font = .adaptiveSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
    view.textColor = color
    view.numberOfLines = 0
    return view
}

/// Navigation bar handling shared by the three tab roots: the screen draws its own 48pt header, so
/// the system bar is hidden here and restored for pushed screens (Settings, Profile, ...).
open class DemoTabRootController: UIViewController {
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.topViewController !== self {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }
}

/// View whose backing layer is a vertical gradient (photo masks).
public final class HostGradientView: UIView {
    public override class var layerClass: AnyClass { CAGradientLayer.self }

    public init(colors: [UIColor]) {
        super.init(frame: .zero)
        let gradient = layer as! CAGradientLayer
        gradient.colors = colors.map { $0.cgColor }
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        isUserInteractionEnabled = false
    }

    public required init?(coder: NSCoder) { fatalError() }
}

/// Circular avatar loading a remote IM avatar URL; first letter of the name until it arrives.
public final class DemoRemoteAvatar: UIView {
    public init(name: String, url: String?, size: CGFloat) {
        super.init(frame: .zero)
        let tokens = Host.tokens
        backgroundColor = tokens.bgColorAvatar
        layer.cornerRadius = size / 2
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        let letter = label(String(name.prefix(1)), size * 0.4, tokens.textColorPrimary, bold: true)
        letter.translatesAutoresizingMaskIntoConstraints = false
        addSubview(letter)
        NSLayoutConstraint.activate([letter.centerXAnchor.constraint(equalTo: centerXAnchor), letter.centerYAnchor.constraint(equalTo: centerYAnchor)])
        let picture = UIImageView()
        picture.contentMode = .scaleAspectFill
        picture.translatesAutoresizingMaskIntoConstraints = false
        addSubview(picture)
        NSLayoutConstraint.activate([picture.topAnchor.constraint(equalTo: topAnchor), picture.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     picture.leadingAnchor.constraint(equalTo: leadingAnchor), picture.trailingAnchor.constraint(equalTo: trailingAnchor)])
        guard let url, let link = URL(string: url) else { return }
        // SDWebImage renders a memory-cache hit synchronously, so a row rebuilt after the profile arrived shows the
        // photo straight away instead of flashing the letter again (the old URLSession download kept no cache at all).
        picture.sd_setImage(with: link, placeholderImage: nil, options: [.retryFailed])
    }

    public required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Mine

/// Small gradient pill used for the demo recharge button.
public final class DemoGradientButton: UIButton {
    private let gradient = CAGradientLayer()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        gradient.colors = [Palette.accent.cgColor, Palette.brandEnd.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer.insertSublayer(gradient, at: 0)
        clipsToBounds = true
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        gradient.cornerRadius = bounds.height / 2
    }
}


/// Label with horizontal padding so pill backgrounds never clip their text.
public final class DemoPaddedLabel: UILabel {
    public var insets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)

    public override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }

    public override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }
}

private final class TapActionTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

extension UIView {
    /// Closure-based tap; the target object lives as long as the view.
    public func onTap(_ action: @escaping () -> Void) {
        let target = TapActionTarget(action)
        let tap = UITapGestureRecognizer(target: target, action: #selector(TapActionTarget.fire))
        objc_setAssociatedObject(tap, Unmanaged.passUnretained(tap).toOpaque(), target, .OBJC_ASSOCIATION_RETAIN)
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }
}

/// Pushed host page with its own header: hides the system nav bar, keeps the edge-swipe back.
open class DemoSubPageController: DemoTabRootController, UIGestureRecognizerDelegate {
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.interactivePopGestureRecognizer?.delegate = self
    }

    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }

    open func backButton() -> UIView {
        let button = UIButton(type: .custom)
        button.setImage(Host.image("demo_hd_back")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = Host.tokens.textColorPrimary
        button.imageView?.contentMode = .scaleAspectFit
        button.imageEdgeInsets = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        button.accessibilityLabel = DemoText.get("demo_back")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)
        return button
    }

    open func toast(_ message: String, kind: SocialToast.Kind = .default) {
        SocialToast.show(message, kind: kind)
    }
}
