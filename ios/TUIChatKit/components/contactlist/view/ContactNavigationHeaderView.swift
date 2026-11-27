import UIKit
import Combine
import SnapKit
import AtomicX

/// Badge pill (min 18 high, text padded by 5) used by the S5 entry rows.
private final class ContactBadgeLabel: UILabel {
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: max(size.width + 10, size.height > 0 ? 18 : 0), height: 18)
    }
}

final class ContactNavigationRowView: UIView {
    enum Style {
        case image(UIImage?)
        case brand
        case danger
    }

    var onTap: (() -> Void)?

    private static let rowHeight: CGFloat = 60

    private static let horizontalPadding: CGFloat = 16

    private static let iconTextSpacing: CGFloat = 12

    private static let titleFontSize: CGFloat = 18

    private static let badgeSize: CGFloat = 18

    private static let badgeMaxCount = 99

    private static let badgeFontSize: CGFloat = 11

    private static let chevronSize: CGFloat = 12

    private static let glyphScale: CGFloat = 0.6

    private let avatarView = ChatAvatarView(size: .m, isRound: false)

    private let chevronView = UIImageView()

    private let titleLabel = UILabel()

    private let badgeLabel = ContactBadgeLabel()

    private let style: Style

    init(title: String, style: Style) {
        self.style = style
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

    func updateBadge(_ count: Int) {
        if count > 0 {
            badgeLabel.text = count > Self.badgeMaxCount ? "\(Self.badgeMaxCount)+" : "\(count)"
            badgeLabel.isHidden = false
        } else {
            badgeLabel.isHidden = true
        }
    }

    private var hasIcon: Bool {
        if case .image(let image) = style { return image != nil }
        return true
    }

    private func constructViewHierarchy() {
        addSubview(avatarView)
        addSubview(titleLabel)
        addSubview(badgeLabel)
        addSubview(chevronView)
    }

    private func activateConstraints() {
        snp.makeConstraints { make in
            make.height.equalTo(Self.rowHeight)
        }
        chevronView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Self.horizontalPadding)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.chevronSize)
        }
        if hasIcon {
            avatarView.snp.makeConstraints { make in
                make.leading.equalToSuperview().offset(Self.horizontalPadding)
                make.centerY.equalToSuperview()
                make.width.height.equalTo(ChatAvatarSize.m.size)
            }
            titleLabel.snp.makeConstraints { make in
                make.leading.equalTo(avatarView.snp.trailing).offset(Self.iconTextSpacing)
                make.centerY.equalToSuperview()
            }
        } else {
            avatarView.isHidden = true
            titleLabel.snp.makeConstraints { make in
                make.leading.equalToSuperview().offset(Self.horizontalPadding)
                make.centerY.equalToSuperview()
            }
        }
        badgeLabel.snp.makeConstraints { make in
            make.trailing.equalTo(chevronView.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
            make.height.equalTo(Self.badgeSize)
        }
    }

    private func bindInteraction() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    private static func lightened(_ color: UIColor, by fraction: CGFloat) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(red: red + (1 - red) * fraction, green: green + (1 - green) * fraction,
                       blue: blue + (1 - blue) * fraction, alpha: alpha)
    }

    private func configureAvatar(colors: TUIChatKitColorScheme) {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        switch style {
        case .image(let image):
            guard let image else { return }
            avatarView.configure(icon: image, tint: nil, glyphScale: 1)
        case .brand:
            guard let image = UIImage(systemName: "person.badge.plus", withConfiguration: symbolConfig) else { return }
            avatarView.configure(icon: image, tint: colors.textColorButton,
                                 gradient: [colors.buttonColorPrimaryDefault, colors.tagColorLevel3], glyphScale: Self.glyphScale)
        case .danger:
            guard let image = UIImage(systemName: "nosign", withConfiguration: symbolConfig) else { return }
            avatarView.configure(icon: image, tint: colors.textColorButton,
                                 gradient: [Self.lightened(colors.textColorError, by: 0.25), colors.textColorError], glyphScale: Self.glyphScale)
        }
    }

    private func setupViewStyle() {
        let colors = TUIChatKitTheme.colors
        backgroundColor = colors.bgColorTopBar
        titleLabel.font = UIFont.adaptiveSystemFont(ofSize: Self.titleFontSize)
        titleLabel.textColor = colors.textColorPrimary
        configureAvatar(colors: colors)
        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        chevronView.image = UIImage(systemName: "chevron.right", withConfiguration: chevronConfig)
        chevronView.tintColor = colors.textColorTertiary
        chevronView.contentMode = .scaleAspectFit
        badgeLabel.font = .adaptiveSystemFont(ofSize: Self.badgeFontSize, weight: .bold)
        badgeLabel.textColor = colors.textColorButton
        badgeLabel.backgroundColor = colors.textColorError
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = Self.badgeSize / 2
        badgeLabel.layer.masksToBounds = true
        badgeLabel.isHidden = true
    }

    @objc private func handleTap() {
        onTap?()
    }
}

final class ContactNavigationHeaderView: UIView {
    private static let dividerHeight: CGFloat = 1

    private static let dividerLeadingInset: CGFloat = 68

    private let stackView = UIStackView()

    private var badgeCancellables = Set<AnyCancellable>()

    init() {
        super.init(frame: .zero)
        constructViewHierarchy()
        activateConstraints()
        setupViewStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setItems(_ items: [ContactCustomItem]) {
        badgeCancellables.removeAll()
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, item) in items.enumerated() {
            let style: ContactNavigationRowView.Style
            switch item.ID {
            case ContactListItemIDs.newContacts: style = .brand
            case ContactListItemIDs.blacklist: style = .danger
            default: style = .image(AtomicXChatResources.image(named: item.iconName))
            }
            let row = ContactNavigationRowView(title: item.title, style: style)
            row.onTap = item.onClick
            if let badgeCount = item.badgeCount {
                badgeCount
                    .receive(on: DispatchQueue.main)
                    .sink { [weak row] count in
                        row?.updateBadge(count)
                    }
                    .store(in: &badgeCancellables)
            }
            stackView.addArrangedSubview(row)
            if index < items.count - 1 {
                stackView.addArrangedSubview(makeDivider())
            }
        }
    }

    private func constructViewHierarchy() {
        stackView.axis = .vertical
        stackView.spacing = 0
        addSubview(stackView)
    }

    private func makeDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = TUIChatKitTheme.colors.strokeColorSecondary
        divider.snp.makeConstraints { make in
            make.height.equalTo(Self.dividerHeight)
        }
        let insetWrapper = UIView()
        insetWrapper.addSubview(divider)
        divider.snp.makeConstraints { make in
            make.top.bottom.trailing.equalToSuperview()
            make.leading.equalToSuperview().offset(Self.dividerLeadingInset)
        }
        return insetWrapper
    }

    private func activateConstraints() {
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func setupViewStyle() {
        backgroundColor = TUIChatKitTheme.colors.bgColorTopBar
    }
}
