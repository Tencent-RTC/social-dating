import UIKit
import SnapKit

final class SubPageNavigationBar: UIView {
    /// The touch target stays the same; the chevron is drawn by `backIcon` at the exact size/position of the host's
    /// `demo_hd_back` (ink 14pt tall starting 23pt from the edge), so 新的联系人 / 黑名单 line up with every other page
    /// instead of showing the raw 16pt `contact_info_back` a few points lower and further right.
    private static let closeButtonLeading: CGFloat = CGFloat(SpacingScheme.smallSpacing)

    private static let closeButtonSize: CGFloat = 44

    private static let backIconLeading: CGFloat = 20

    private static let backIconSize: CGFloat = 14

    private static let backSymbolPointSize: CGFloat = 18

    var onClose: (() -> Void)?

    private let closeButton = UIButton(type: .system)

    private let backIcon = UIImageView()

    private let trailingButton = UIButton(type: .system)

    private var onTrailing: (() -> Void)?

    private let titleLabel = UILabel()

    init(title: String) {
        super.init(frame: .zero)
        titleLabel.text = title
        constructViewHierarchy()
        activateConstraints()
        bindInteraction()
        setupViewStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func constructViewHierarchy() {
        addSubview(closeButton)
        addSubview(backIcon)
        addSubview(trailingButton)
        addSubview(titleLabel)
    }

    private func activateConstraints() {
        closeButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.closeButtonLeading)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.closeButtonSize)
        }
        backIcon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.backIconLeading)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.backIconSize)
        }
        trailingButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Self.closeButtonLeading)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.closeButtonSize)
        }
        titleLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    private func bindInteraction() {
        closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
        trailingButton.addTarget(self, action: #selector(handleTrailing), for: .touchUpInside)
    }

    private func setupViewStyle() {
        let colors = TUIChatKitTheme.colors
        backgroundColor = colors.bgColorTopBar
        titleLabel.font = FontScheme.caption1Medium
        titleLabel.textColor = colors.textColorPrimary
        let image = AtomicXChatResources.image(named: "contact_info_back")?
            .withRenderingMode(.alwaysTemplate)
            ?? UIImage(systemName: "chevron.left",
                       withConfiguration: UIImage.SymbolConfiguration(pointSize: Self.backSymbolPointSize, weight: .semibold))
        backIcon.image = image
        backIcon.contentMode = .scaleAspectFit
        backIcon.tintColor = colors.textColorPrimary
        backIcon.isUserInteractionEnabled = false
        closeButton.tintColor = colors.textColorPrimary
        trailingButton.tintColor = colors.textColorPrimary
        trailingButton.isHidden = true
    }

    func setTrailingAction(image: UIImage?, accessibilityLabel: String, handler: @escaping () -> Void) {
        onTrailing = handler
        trailingButton.setImage(image, for: .normal)
        trailingButton.accessibilityLabel = accessibilityLabel
        trailingButton.isHidden = false
    }

    @objc private func handleClose() {
        onClose?()
    }

    @objc private func handleTrailing() {
        onTrailing?()
    }
}
