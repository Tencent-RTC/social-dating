import UIKit
import SnapKit
import Kingfisher
import AtomicX

final class AZOrderedListCell: UITableViewCell {
    static let reuseIdentifier = "AZOrderedListCell"

    var titleFontSize: CGFloat = 14 {
        didSet { titleLabel.font = .adaptiveSystemFont(ofSize: titleFontSize) }
    }

    private static let horizontalPadding: CGFloat = CGFloat(SpacingScheme.bubbleSpacing)

    private static let avatarSize: CGFloat = 40

    private static let avatarCornerRadius: CGFloat = CGFloat(RadiusScheme.tipsRadius)

    private static let avatarTextSpacing: CGFloat = 12

    private static let dividerHeight: CGFloat = 1

    /// Trailing room for the A-Z index bar (prototype `.contact` padding-right 40).
    private static let rowEndInset: CGFloat = 40

    private static let dividerLeadingInset: CGFloat = 68

    private let avatarContainer = UIView()

    private let avatarImageView = UIImageView()

    private let avatarTextLabel = UILabel()

    private let titleLabel = UILabel()

    private let titleRow = UIStackView()

    private let titleAccessorySlot = UIView()

    private let subtitleSlot = UIView()

    private var textStack: UIStackView?

    private let dividerView = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        constructViewHierarchy()
        activateConstraints()
        setupViewStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with item: AZOrderedListItem, showsDivider: Bool = false) {
        let displayName = item.title ?? item.userID
        titleLabel.text = displayName
        titleLabel.font = .adaptiveSystemFont(ofSize: titleFontSize)
        dividerView.isHidden = !showsDivider
        subtitleSlot.subviews.forEach { $0.removeFromSuperview() }
        if let accessory = item.subtitleProvider?() {
            subtitleSlot.addSubview(accessory)
            accessory.snp.makeConstraints { make in make.edges.equalToSuperview() }
            subtitleSlot.isHidden = false
        } else {
            subtitleSlot.isHidden = true
        }
        titleAccessorySlot.subviews.forEach { $0.removeFromSuperview() }
        if let accessory = item.titleAccessoryProvider?() {
            titleAccessorySlot.addSubview(accessory)
            accessory.snp.makeConstraints { make in make.edges.equalToSuperview() }
            titleAccessorySlot.isHidden = false
        } else {
            titleAccessorySlot.isHidden = true
        }
        let urlString = item.avatarURL ?? ""
        if urlString.isEmpty {
            showTextAvatar(name: displayName)
        } else {
            loadImageAvatar(urlString: urlString, fallbackName: displayName)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageView.kf.cancelDownloadTask()
        avatarImageView.image = nil
        titleLabel.text = nil
        subtitleSlot.subviews.forEach { $0.removeFromSuperview() }
        subtitleSlot.isHidden = true
        titleAccessorySlot.subviews.forEach { $0.removeFromSuperview() }
        titleAccessorySlot.isHidden = true
        dividerView.isHidden = true
    }

    private func constructViewHierarchy() {
        selectionStyle = .none
        contentView.addSubview(avatarContainer)
        avatarContainer.addSubview(avatarImageView)
        avatarContainer.addSubview(avatarTextLabel)
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 6
        titleAccessorySlot.isHidden = true
        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(titleAccessorySlot)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [titleRow, subtitleSlot])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        textStack = stack
        contentView.addSubview(stack)
        contentView.addSubview(dividerView)
    }

    private func activateConstraints() {
        avatarContainer.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.horizontalPadding)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.avatarSize)
        }
        avatarImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        avatarTextLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        textStack?.snp.makeConstraints { make in
            make.leading.equalTo(avatarContainer.snp.trailing).offset(Self.avatarTextSpacing)
            make.trailing.lessThanOrEqualToSuperview().offset(-Self.rowEndInset)
            make.centerY.equalToSuperview()
        }
        dividerView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.dividerLeadingInset)
            make.trailing.bottom.equalToSuperview()
            make.height.equalTo(Self.dividerHeight)
        }
    }

    private func setupViewStyle() {
        let colors = TUIChatKitTheme.colors
        backgroundColor = colors.bgColorTopBar
        contentView.backgroundColor = colors.bgColorTopBar

        avatarContainer.backgroundColor = colors.bgColorAvatar
        avatarContainer.layer.cornerRadius = ChatAvatarView.shapedCornerRadius(diameter: Self.avatarSize, rounded: Self.avatarCornerRadius)
        avatarContainer.layer.masksToBounds = true

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.isHidden = true

        avatarTextLabel.font = FontScheme.caption1Medium
        avatarTextLabel.textColor = colors.textColorPrimary
        avatarTextLabel.textAlignment = .center

        titleLabel.font = .adaptiveSystemFont(ofSize: titleFontSize)
        titleLabel.textColor = colors.textColorPrimary
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        dividerView.backgroundColor = colors.strokeColorSecondary
        dividerView.isHidden = true
    }

    private func showTextAvatar(name: String) {
        avatarImageView.isHidden = true
        avatarImageView.image = nil
        avatarTextLabel.isHidden = false
        avatarTextLabel.text = name.first.map { String($0).uppercased() } ?? ""
    }

    private func loadImageAvatar(urlString: String, fallbackName: String) {
        avatarTextLabel.isHidden = true
        avatarImageView.isHidden = false
        avatarImageView.kf.setImage(with: URL(string: urlString)) { [weak self] result in
            guard let self else { return }
            if case .failure = result {
                self.showTextAvatar(name: fallbackName)
            }
        }
    }
}
