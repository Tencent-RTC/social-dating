import AtomicXCore
import UIKit
import SnapKit
import AtomicX

/// S6 spec of the 1:1 chat settings page (prototype `.profilebox / .setgroup / .setcard / .setrow`).
enum ChatSettingSceneSpec {
    private static func s(_ value: CGFloat) -> CGFloat { ScreenAdaptation.scaled(value) }

    static let rowMinHeight: CGFloat = s(52)
    static let labelFontSize: CGFloat = 16
    static let valueFontSize: CGFloat = 12
    static let rowGap: CGFloat = 12
    static let chevronSize: CGFloat = 12
    static let pagePadding: CGFloat = 16
    static let profileAvatar: CGFloat = 72
    static let profileNameFontSize: CGFloat = 18
    static let profileUIDFontSize: CGFloat = 12
    static let profileGap: CGFloat = 6
    static let profileTop: CGFloat = 12
    static let profileBottom: CGFloat = 8
    static let cardRadius: CGFloat = 12
    static let groupGap: CGFloat = 6
    static let dividerInset: CGFloat = 16
    static let footerFontSize: CGFloat = 10
    static let switchWidth: CGFloat = s(44)
    static let switchHeight: CGFloat = s(24)
}

/// Pill switch drawn by the app (round thumb, flat capsule track) so it looks identical on every iOS version and
/// phone size; `UISwitch` changes its look between systems and turns oval when its transform is stretched.
final class ChatSettingSwitch: UIControl {
    private(set) var isOn = false

    private let thumb = UIView()

    private static let thumbInset: CGFloat = 2

    override var intrinsicContentSize: CGSize {
        CGSize(width: ChatSettingSceneSpec.switchWidth, height: ChatSettingSceneSpec.switchHeight)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        thumb.backgroundColor = TUIChatKitTheme.colors.switchColorButton
        thumb.isUserInteractionEnabled = false
        thumb.layer.shadowColor = UIColor.black.cgColor
        thumb.layer.shadowOpacity = 0.25
        thumb.layer.shadowRadius = 1.5
        thumb.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(thumb)
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
        applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layoutThumb()
    }

    func setOn(_ on: Bool, animated: Bool) {
        guard on != isOn else { return }
        isOn = on
        accessibilityValue = on ? "1" : "0"
        let changes = {
            self.applyColors()
            self.layoutThumb()
        }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: changes)
        } else {
            changes()
        }
    }

    private func layoutThumb() {
        let inset = Self.thumbInset
        let d = max(bounds.height - inset * 2, 0)
        let x = isOn ? bounds.width - inset - d : inset
        thumb.frame = CGRect(x: x, y: inset, width: d, height: d)
        thumb.layer.cornerRadius = d / 2
    }

    private func applyColors() {
        let colors = TUIChatKitTheme.colors
        backgroundColor = isOn ? colors.switchColorOn : colors.switchColorOff
    }

    @objc private func handleTap() {
        setOn(!isOn, animated: true)
        sendActions(for: .valueChanged)
    }
}

/// Capsule label with horizontal padding, used for level badges and profile tags.
final class ChatSettingCapsuleLabel: UILabel {
    var insets = UIEdgeInsets(top: 1, left: 6, bottom: 1, right: 6)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layer.masksToBounds = true
    }
}

func chatSettingBlend(_ color: UIColor, with other: UIColor, amount: CGFloat) -> UIColor {
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
    color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
    return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount,
                   blue: b1 + (b2 - b1) * amount, alpha: 1)
}

public class ChatSettingBaseViewController: UIViewController {
    var onBack: (() -> Void)?

    var contentTopItem: ConstraintItem {
        return divider.snp.bottom
    }

    private static let navBarHeight: CGFloat = 56

    private static let navHorizontalInset: CGFloat = CGFloat(SpacingScheme.bubbleSpacing)

    private static let backButtonSize: CGFloat = 28

    private static let backIconPointSize: CGFloat = 18

    private static let titleFontSize: CGFloat = 16

    private static let dividerHeight: CGFloat = 0.5

    private let navigationBar = UIView()

    private let statusBarBackgroundView = UIView()

    private let backButton = ExpandedHitButton(type: .custom)

    private let titleLabel = UILabel()

    private let divider = UIView()

    private var navLeadingView: UIView?

    private var navTrailingView: UIView?

    public override func viewDidLoad() {
        super.viewDidLoad()
        constructNavigationBar()
        activateNavigationBarConstraints()
        setupNavigationBarStyle()
        backButton.addTarget(self, action: #selector(handleBackTapped), for: .touchUpInside)
    }

    /// The page draws its own 56pt nav bar (like Android), so a system bar pushed by the host would show a second one.
    private var restoreSystemNavBarHidden: Bool?

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let navigationController = navigationController else { return }
        if restoreSystemNavBarHidden == nil { restoreSystemNavBarHidden = navigationController.isNavigationBarHidden }
        navigationController.setNavigationBarHidden(true, animated: animated)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let navigationController = navigationController, let wasHidden = restoreSystemNavBarHidden else { return }
        // Pushing another self-drawn page keeps the system bar hidden; anything else gets the host's state back.
        if navigationController.topViewController is ChatSettingBaseViewController, navigationController.topViewController !== self { return }
        navigationController.setNavigationBarHidden(wasHidden, animated: animated)
        restoreSystemNavBarHidden = nil
    }

    func setNavTitle(_ text: String) {
        titleLabel.text = text
    }

    /// Android's add-contact flow draws the back chevron in the secondary text color; pages that mirror it opt in here.
    func setNavBackTint(_ color: UIColor) {
        backButton.tintColor = color
    }

    func setNavBackHidden(_ hidden: Bool) {
        backButton.isHidden = hidden
    }

    func setNavLeadingView(_ leadingView: UIView) {
        navLeadingView?.removeFromSuperview()
        navLeadingView = leadingView
        navigationBar.addSubview(leadingView)
        leadingView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.navHorizontalInset)
            make.centerY.equalToSuperview()
        }
        updateTitleConstraints()
    }

    func setNavTrailingView(_ trailingView: UIView) {
        navTrailingView?.removeFromSuperview()
        navTrailingView = trailingView
        navigationBar.addSubview(trailingView)
        trailingView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Self.navHorizontalInset)
            make.centerY.equalToSuperview()
        }
        updateTitleConstraints()
    }

    func pushOrPresent(_ viewController: UIViewController) {
        if let navigationController = navigationController {
            navigationController.pushViewController(viewController, animated: true)
        } else {
            present(viewController, animated: true)
        }
    }

    private func updateTitleConstraints() {
        titleLabel.snp.remakeConstraints { make in
            make.center.equalToSuperview()
            if let navLeadingView = navLeadingView {
                make.leading.greaterThanOrEqualTo(navLeadingView.snp.trailing).offset(Self.navHorizontalInset)
            } else {
                make.leading.greaterThanOrEqualTo(backButton.snp.trailing).offset(Self.navHorizontalInset)
            }
            if let navTrailingView = navTrailingView {
                make.trailing.lessThanOrEqualTo(navTrailingView.snp.leading).offset(-Self.navHorizontalInset)
            } else {
                make.trailing.lessThanOrEqualToSuperview().offset(-Self.navHorizontalInset)
            }
        }
    }

    private func constructNavigationBar() {
        view.addSubview(statusBarBackgroundView)
        view.addSubview(navigationBar)
        navigationBar.addSubview(backButton)
        navigationBar.addSubview(titleLabel)
        view.addSubview(divider)
    }

    private func activateNavigationBarConstraints() {

        statusBarBackgroundView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(navigationBar.snp.top)
        }
        navigationBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(Self.navBarHeight)
        }
        backButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.navHorizontalInset)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.backButtonSize)
        }
        titleLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualTo(backButton.snp.trailing).offset(Self.navHorizontalInset)
            make.trailing.lessThanOrEqualToSuperview().offset(-Self.navHorizontalInset)
        }
        divider.snp.makeConstraints { make in
            make.top.equalTo(navigationBar.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(Self.dividerHeight)
        }
    }

    private func setupNavigationBarStyle() {
        let colors = TUIChatKitTheme.colors
        statusBarBackgroundView.backgroundColor = colors.bgColorTopBar
        navigationBar.backgroundColor = colors.bgColorTopBar
        divider.backgroundColor = colors.strokeColorSecondary
        if let backImage = AtomicXChatResources.image(named: "contact_info_back") {
            backButton.setImage(backImage.withRenderingMode(.alwaysTemplate), for: .normal)
        } else {
            backButton.setImage(
                UIImage(systemName: "chevron.left")?
                    .withConfiguration(UIImage.SymbolConfiguration(pointSize: Self.backIconPointSize, weight: .semibold)),
                for: .normal
            )
        }
        backButton.tintColor = colors.textColorPrimary
        backButton.contentHorizontalAlignment = .leading
        titleLabel.font = .adaptiveSystemFont(ofSize: Self.titleFontSize, weight: .semibold)
        titleLabel.textColor = colors.textColorPrimary
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
    }

    @objc private func handleBackTapped() {
        if let onBack = onBack {
            onBack()
        } else if let navigationController = navigationController {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}

// MARK: - Row Views（规格对齐 Android SettingRowNavigate / SettingRowToggle / ActionItem 行）

final class ChatSettingRowView: UIControl {
    enum Accessory {
        case none
        case arrow
        case edit
    }

    override var isEnabled: Bool {
        didSet { isUserInteractionEnabled = isEnabled }
    }

    private static let horizontalPadding: CGFloat = 14

    private static let verticalPadding: CGFloat = 12

    private static let rowMinHeight: CGFloat = ChatSettingSceneSpec.rowMinHeight

    private static let accessorySize: CGFloat = ChatSettingSceneSpec.chevronSize

    private static let accessoryLeadingGap: CGFloat = CGFloat(SpacingScheme.smallSpacing)

    private static let titleTrailingGap: CGFloat = CGFloat(SpacingScheme.bubbleSpacing)

    private let titleLabel = UILabel()

    private let valueLabel = UILabel()

    private let badgeLabel = ChatSettingCapsuleLabel()

    private var isDanger = false

    private let accessoryImageView = UIImageView()

    private var valueTrailingToAccessory: Constraint?

    private var valueTrailingToSuperview: Constraint?

    init(title: String, value: String = "", accessory: Accessory = .arrow) {
        super.init(frame: .zero)
        constructViewHierarchy()
        activateConstraints()
        setupViewStyle()
        titleLabel.text = title
        update(value: value, accessory: accessory)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitle(_ title: String) {
        titleLabel.text = title
    }

    /// Level capsule on the right (prototype `.tag--level`), e.g. "Lv.3".
    func setBadge(_ text: String?) {
        badgeLabel.text = text
        badgeLabel.isHidden = (text ?? "").isEmpty
        updateRightGroupConstraints()
    }

    /// Danger style (prototype `.setrow--danger`): error label, 60% chevron.
    func setDanger(_ danger: Bool) {
        isDanger = danger
        let colors = TUIChatKitTheme.colors
        titleLabel.textColor = danger ? colors.textColorError : colors.textColorPrimary
        accessoryImageView.tintColor = danger ? colors.textColorError.withAlphaComponent(0.6) : colors.textColorTertiary
    }

    func update(value: String, accessory: Accessory) {
        valueLabel.text = value
        valueLabel.isHidden = value.isEmpty
        if accessory == .none {
            valueTrailingToAccessory?.deactivate()
            valueTrailingToSuperview?.activate()
        } else {
            valueTrailingToSuperview?.deactivate()
            valueTrailingToAccessory?.activate()
        }
        switch accessory {
        case .none:
            accessoryImageView.isHidden = true
        case .arrow:
            accessoryImageView.isHidden = false
            accessoryImageView.image = AtomicXChatResources.image(named: "contact_info_arrow_right")?
                .withRenderingMode(.alwaysTemplate)
        case .edit:
            accessoryImageView.isHidden = false
            accessoryImageView.image = AtomicXChatResources.image(named: "group_setting_edit_icon")?
                .withRenderingMode(.alwaysTemplate)
        }
        updateRightGroupConstraints()
    }

    private func updateRightGroupConstraints() {
        let gap = ChatSettingSceneSpec.rowGap
        badgeLabel.snp.remakeConstraints { make in
            make.centerY.equalToSuperview()
            if !valueLabel.isHidden {
                make.trailing.equalTo(valueLabel.snp.leading).offset(-gap)
            } else if !accessoryImageView.isHidden {
                make.trailing.equalTo(accessoryImageView.snp.leading).offset(-gap)
            } else {
                make.trailing.equalToSuperview().offset(-Self.horizontalPadding)
            }
        }
    }

    private func constructViewHierarchy() {
        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(badgeLabel)
        addSubview(accessoryImageView)
    }

    private func activateConstraints() {
        snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(Self.rowMinHeight)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.horizontalPadding)
            make.top.equalToSuperview().offset(Self.verticalPadding)
            make.bottom.equalToSuperview().offset(-Self.verticalPadding)
            make.centerY.equalToSuperview()
        }
        accessoryImageView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Self.horizontalPadding)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.accessorySize)
        }
        // Right group (prototype `.setrow__right`): badge, value, chevron.
        updateRightGroupConstraints()
        valueLabel.snp.makeConstraints { make in
            make.leading.greaterThanOrEqualTo(titleLabel.snp.trailing).offset(Self.titleTrailingGap)
            valueTrailingToAccessory = make.trailing.equalTo(accessoryImageView.snp.leading).offset(-Self.accessoryLeadingGap).constraint
            valueTrailingToSuperview = make.trailing.equalToSuperview().offset(-Self.horizontalPadding).constraint
            make.centerY.equalToSuperview()
        }
        valueTrailingToSuperview?.deactivate()
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func setupViewStyle() {
        let colors = TUIChatKitTheme.colors
        backgroundColor = colors.bgColorOperate
        titleLabel.font = UIFont.adaptiveSystemFont(ofSize: ChatSettingSceneSpec.labelFontSize)
        titleLabel.textColor = colors.textColorPrimary
        valueLabel.font = UIFont.adaptiveSystemFont(ofSize: ChatSettingSceneSpec.valueFontSize)
        valueLabel.textColor = colors.textColorSecondary
        badgeLabel.font = UIFont.adaptiveSystemFont(ofSize: 11)
        badgeLabel.textColor = colors.tagColorLevel4
        badgeLabel.backgroundColor = colors.tagColorLevel4.withAlphaComponent(0.18)
        badgeLabel.isHidden = true
        valueLabel.textAlignment = LanguageHelper.isRTL ? .left : .right
        valueLabel.lineBreakMode = .byTruncatingTail
        accessoryImageView.tintColor = colors.textColorTertiary
        accessoryImageView.contentMode = .scaleAspectFit
    }
}

final class ChatSettingToggleRowView: UIView {
    var onToggle: ((Bool) -> Void)?

    private static let horizontalPadding: CGFloat = CGFloat(SpacingScheme.bubbleSpacing)

    private static let verticalPadding: CGFloat = 8

    private let titleLabel = UILabel()

    private let toggle = ChatSettingSwitch()

    init(title: String, isOn: Bool = false) {
        super.init(frame: .zero)
        constructViewHierarchy()
        activateConstraints()
        setupViewStyle()
        titleLabel.text = title
        toggle.setOn(isOn, animated: false)
        toggle.addTarget(self, action: #selector(handleToggleChanged), for: .valueChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setOn(_ isOn: Bool) {
        toggle.setOn(isOn, animated: false)
    }

    private func constructViewHierarchy() {
        addSubview(titleLabel)
        addSubview(toggle)
    }

    private func activateConstraints() {
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.horizontalPadding)
            make.top.equalToSuperview().offset(Self.verticalPadding)
            make.bottom.equalToSuperview().offset(-Self.verticalPadding)
            make.centerY.equalToSuperview()
        }
        toggle.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Self.horizontalPadding)
            make.centerY.equalToSuperview()
            make.width.equalTo(ChatSettingSceneSpec.switchWidth)
            make.height.equalTo(ChatSettingSceneSpec.switchHeight)
            make.leading.greaterThanOrEqualTo(titleLabel.snp.trailing).offset(Self.horizontalPadding)
        }
        snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(ChatSettingSceneSpec.rowMinHeight)
        }
    }

    private func setupViewStyle() {
        let colors = TUIChatKitTheme.colors
        backgroundColor = colors.bgColorOperate
        titleLabel.font = UIFont.adaptiveSystemFont(ofSize: ChatSettingSceneSpec.labelFontSize)
        titleLabel.textColor = colors.textColorPrimary
    }

    @objc private func handleToggleChanged() {
        onToggle?(toggle.isOn)
    }
}

final class ChatSettingActionRowView: UIControl {
    private static let verticalPadding: CGFloat = 15

    private static let rowMinHeight: CGFloat = 56

    private static let fontSize: CGFloat = 17

    private let titleLabel = UILabel()

    init(title: String, textColor: UIColor) {
        super.init(frame: .zero)
        addSubview(titleLabel)
        snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(Self.rowMinHeight)
        }
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(Self.verticalPadding)
            make.bottom.equalToSuperview().offset(-Self.verticalPadding)
        }
        backgroundColor = TUIChatKitTheme.colors.bgColorOperate
        titleLabel.font = .adaptiveSystemFont(ofSize: Self.fontSize)
        titleLabel.textColor = textColor
        titleLabel.text = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Section Helpers

private let chatSettingSectionSpacerHeight: CGFloat = 10

private let chatSettingRowDividerHeight: CGFloat = 0.5

func makeChatSettingSectionSpacer() -> UIView {
    let spacer = UIView()
    spacer.backgroundColor = TUIChatKitTheme.colors.bgColorTopBar
    spacer.snp.makeConstraints { make in
        make.height.equalTo(chatSettingSectionSpacerHeight)
    }
    return spacer
}

func makeChatSettingRowDivider() -> UIView {
    let divider = UIView()
    divider.backgroundColor = TUIChatKitTheme.colors.strokeColorPrimary
    divider.snp.makeConstraints { make in
        make.height.equalTo(chatSettingRowDividerHeight)
    }
    return divider
}

func chatSettingMemberDisplayName(_ member: GroupMember) -> String {
    if let nameCard = member.nameCard, !nameCard.isEmpty {
        return nameCard
    } else if let friendRemark = member.friendRemark, !friendRemark.isEmpty {
        return friendRemark
    } else if let nickname = member.nickname, !nickname.isEmpty {
        return nickname
    } else {
        return member.userID
    }
}

func chatSettingContactDisplayName(_ contact: ContactInfo) -> String {
    if let friendRemark = contact.friendRemark, !friendRemark.isEmpty {
        return friendRemark
    } else if let nickname = contact.nickname, !nickname.isEmpty {
        return nickname
    } else {
        return contact.userID
    }
}
