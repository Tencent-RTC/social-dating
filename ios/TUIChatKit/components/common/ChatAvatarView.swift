import UIKit
import SnapKit
import Kingfisher
import AtomicX

public enum ChatAvatarSize {
    case xxs, xs, s, m, l, xl, xxl

    public var size: CGFloat {
        switch self {
        case .xxs: return 16
        case .xs: return 24
        case .s: return 32
        case .m: return 40
        case .l: return 48
        case .xl: return 64
        case .xxl: return 96
        }
    }

    public var placeholderFontSize: CGFloat {
        switch self {
        case .xxs: return 10
        case .xs: return 12
        case .s: return 14
        case .m: return 16
        case .l: return 18
        case .xl: return 28
        case .xxl: return 36
        }
    }

    public var roundedRectCornerRadius: CGFloat {
        switch self {
        case .xxs, .xs, .s, .m: return 4
        case .l, .xl, .xxl: return 8
        }
    }
}

public final class ChatAvatarView: UIView {
    /// Corner radius honouring the global avatar shape (design: chat avatars are circles).
    static func shapedCornerRadius(diameter: CGFloat, rounded: CGFloat) -> CGFloat {
        switch AppBuilderConfig.shared.avatarShape {
        case .circular: return diameter / 2
        case .rounded: return rounded
        case .square: return 0
        }
    }

    private let imageView = UIImageView()

    private let textLabel = UILabel()

    private let iconView = UIImageView()

    private var fillGradientLayer: CAGradientLayer?

    // MARK: - Init

    public convenience init(size: ChatAvatarSize, isRound: Bool) {
        let radius = isRound ? size.size / 2
            : Self.shapedCornerRadius(diameter: size.size, rounded: size.roundedRectCornerRadius)
        self.init(cornerRadius: radius, fontSize: size.placeholderFontSize)
    }

    public init(cornerRadius: CGFloat = 4, fontSize: CGFloat = 16) {
        super.init(frame: .zero)
        backgroundColor = TUIChatKitTheme.colors.bgColorAvatar
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.isHidden = true
        textLabel.font = .adaptiveSystemFont(ofSize: fontSize, weight: .medium)
        textLabel.textColor = TUIChatKitTheme.colors.textColorPrimary
        textLabel.textAlignment = .center

        addSubview(imageView)
        addSubview(textLabel)
        iconView.contentMode = .scaleAspectFit
        iconView.isHidden = true
        addSubview(iconView)
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        textLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configure

    public func configure(avatarURL: String?, fallbackName: String) {
        imageView.kf.cancelDownloadTask()
        let urlString = avatarURL ?? ""
        if urlString.isEmpty {
            showTextAvatar(name: fallbackName)
        } else {
            loadImageAvatar(urlString: urlString, fallbackName: fallbackName)
        }
    }

    public func configure(icon: UIImage, tint: UIColor?, gradient: [UIColor]? = nil, glyphScale: CGFloat = 0.6) {
        imageView.kf.cancelDownloadTask()
        imageView.isHidden = true
        textLabel.isHidden = true
        iconView.image = icon.withRenderingMode(tint == nil ? .alwaysOriginal : .alwaysTemplate)
        iconView.tintColor = tint
        iconView.isHidden = false
        iconView.snp.remakeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalToSuperview().multipliedBy(glyphScale)
        }
        fillGradientLayer?.removeFromSuperlayer()
        fillGradientLayer = nil
        if let gradient {
            let layer = CAGradientLayer()
            layer.colors = gradient.map { $0.cgColor }
            layer.startPoint = CGPoint(x: 0, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 0.5)
            self.layer.insertSublayer(layer, at: 0)
            fillGradientLayer = layer
        }
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        fillGradientLayer?.frame = bounds
    }

    func reset() {
        iconView.isHidden = true
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        imageView.isHidden = true
        textLabel.text = nil
        textLabel.isHidden = false
    }

    // MARK: - Private

    private func showTextAvatar(name: String) {
        iconView.isHidden = true
        imageView.isHidden = true
        imageView.image = nil
        textLabel.isHidden = false
        textLabel.text = name.first.map { String($0).uppercased() } ?? ""
    }

    private func loadImageAvatar(urlString: String, fallbackName: String) {
        iconView.isHidden = true
        textLabel.isHidden = true
        imageView.isHidden = false
        imageView.kf.setImage(with: URL(string: urlString)) { [weak self] result in
            guard let self else { return }
            if case .failure = result {
                self.showTextAvatar(name: fallbackName)
            }
        }
    }
}
