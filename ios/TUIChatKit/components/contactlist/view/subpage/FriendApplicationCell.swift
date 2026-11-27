import UIKit
import SnapKit
import AtomicXCore
import AtomicX

final class FriendApplicationCell: UITableViewCell {
    static let reuseIdentifier = "FriendApplicationCell"

    // S5b: prototype `.reqrow` 72 high, 48 avatar, 28 high pill buttons r14.
    static let rowHeight: CGFloat = 72

    private static let avatarSize: CGFloat = 48

    private static let horizontalPadding: CGFloat = 16

    private static let avatarTextSpacing: CGFloat = 12

    private static let buttonHeight: CGFloat = 28

    private static let buttonRadius: CGFloat = 14

    private static let buttonPadding: CGFloat = 14

    private static let buttonSpacing: CGFloat = 8

    private static let refuseBorderWidth: CGFloat = 1

    private var onAccept: (() -> Void)?

    private var onRefuse: (() -> Void)?

    private let avatarView = ChatAvatarView(size: .l, isRound: false)

    private let textColumn = UIStackView()

    private let nameRow = UIStackView()

    private let tagsSlot = UIView()

    private let nameLabel = UILabel()

    private let wordingLabel = UILabel()

    private let acceptButton = UIButton(type: .custom)

    private let refuseButton = UIButton(type: .custom)

    private let addedLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        constructViewHierarchy()
        activateConstraints()
        bindInteraction()
        setupViewStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with application: FriendApplicationInfo,
                   accepted: Bool,
                   onAccept: @escaping () -> Void,
                   onRefuse: @escaping () -> Void) {
        self.onAccept = onAccept
        self.onRefuse = onRefuse
        let displayName = ContactDisplayNameFormatter.name(for: application)
        nameLabel.text = displayName
        wordingLabel.text = application.addWording ?? ""
        avatarView.configure(avatarURL: application.avatarURL, fallbackName: displayName)
        acceptButton.isHidden = accepted
        refuseButton.isHidden = accepted
        addedLabel.isHidden = !accepted
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        wordingLabel.text = nil
        setTags(nil)
        onAccept = nil
        onRefuse = nil
    }

    private func constructViewHierarchy() {
        selectionStyle = .none
        // Age / city pills ride right after the nickname, like the conversation list.
        nameRow.axis = .horizontal
        nameRow.alignment = .center
        nameRow.spacing = 6
        tagsSlot.isHidden = true
        nameRow.addArrangedSubview(nameLabel)
        nameRow.addArrangedSubview(tagsSlot)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textColumn.axis = .vertical
        textColumn.spacing = 0
        textColumn.addArrangedSubview(nameRow)
        textColumn.addArrangedSubview(wordingLabel)
        contentView.addSubview(avatarView)
        contentView.addSubview(textColumn)
        contentView.addSubview(acceptButton)
        contentView.addSubview(refuseButton)
        contentView.addSubview(addedLabel)
    }

    /// Host-supplied pills shown after the nickname; `nil` hides the slot.
    func setTags(_ view: UIView?) {
        tagsSlot.subviews.forEach { $0.removeFromSuperview() }
        guard let view else {
            tagsSlot.isHidden = true
            return
        }
        tagsSlot.addSubview(view)
        view.snp.makeConstraints { make in make.edges.equalToSuperview() }
        tagsSlot.isHidden = false
    }

    private func activateConstraints() {
        avatarView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.horizontalPadding)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.avatarSize)
        }
        textColumn.snp.makeConstraints { make in
            make.leading.equalTo(avatarView.snp.trailing).offset(Self.avatarTextSpacing)
            make.centerY.equalTo(avatarView)
            make.trailing.lessThanOrEqualTo(acceptButton.snp.leading).offset(-Self.buttonSpacing)
        }
        acceptButton.snp.makeConstraints { make in
            make.trailing.equalTo(refuseButton.snp.leading).offset(-Self.buttonSpacing)
            make.centerY.equalTo(avatarView)
            make.height.equalTo(Self.buttonHeight)
        }
        addedLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Self.horizontalPadding)
            make.centerY.equalTo(avatarView)
        }
        refuseButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Self.horizontalPadding)
            make.centerY.equalTo(avatarView)
            make.height.equalTo(Self.buttonHeight)
        }
    }

    private func bindInteraction() {
        acceptButton.addTarget(self, action: #selector(handleAccept), for: .touchUpInside)
        refuseButton.addTarget(self, action: #selector(handleRefuse), for: .touchUpInside)
        acceptButton.isAccessibilityElement = true
        acceptButton.accessibilityLabel = LocalizedChatString("Agree")
        acceptButton.accessibilityIdentifier = "friend_application_accept"
        refuseButton.isAccessibilityElement = true
        refuseButton.accessibilityLabel = LocalizedChatString("Decline")
        refuseButton.accessibilityIdentifier = "friend_application_decline"
    }

    private func setupViewStyle() {
        let colors = TUIChatKitTheme.colors
        backgroundColor = colors.bgColorTopBar
        contentView.backgroundColor = colors.bgColorTopBar
        nameLabel.font = UIFont.adaptiveSystemFont(ofSize: 16, weight: .bold)
        nameLabel.textColor = colors.textColorPrimary
        textColumn.spacing = 2
        wordingLabel.font = UIFont.adaptiveSystemFont(ofSize: 13)
        wordingLabel.textColor = colors.textColorSecondary
        addedLabel.text = LocalizedChatString("ContactsAdded")
        addedLabel.font = UIFont.adaptiveSystemFont(ofSize: 13)
        addedLabel.textColor = colors.textColorTertiary
        addedLabel.isHidden = true
        styleActionButton(
            acceptButton,
            title: LocalizedChatString("Agree"),
            titleColor: colors.textColorButton,
            backgroundColor: colors.buttonColorPrimaryDefault,
            borderColor: nil
        )
        styleActionButton(
            refuseButton,
            title: LocalizedChatString("Decline"),
            titleColor: colors.textColorSecondary,
            backgroundColor: .clear,
            borderColor: colors.strokeColorSecondary
        )
    }

    private func styleActionButton(_ button: UIButton,
                                   title: String,
                                   titleColor: UIColor,
                                   backgroundColor: UIColor,
                                   borderColor: UIColor?) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(titleColor, for: .normal)
        button.titleLabel?.font = UIFont.adaptiveSystemFont(ofSize: 12, weight: .bold)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: Self.buttonPadding, bottom: 0, right: Self.buttonPadding)
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = Self.buttonRadius
        button.layer.masksToBounds = true
        if let borderColor = borderColor {
            button.layer.borderWidth = Self.refuseBorderWidth
            button.layer.borderColor = borderColor.cgColor
        }
    }

    @objc private func handleAccept() {
        onAccept?()
    }

    @objc private func handleRefuse() {
        onRefuse?()
    }
}
