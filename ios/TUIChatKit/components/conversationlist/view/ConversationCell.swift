import UIKit
import SnapKit
import Kingfisher
import AtomicXCore
import AtomicX

final class ConversationCell: UITableViewCell {
    static let reuseIdentifier = "ConversationCell"

    private static let avatarSize: CGFloat = 48

    private static let avatarCornerRadius: CGFloat = CGFloat(RadiusScheme.tipsRadius)

    private static let avatarLeadingPadding: CGFloat = CGFloat(SpacingScheme.bubbleSpacing)

    private static let avatarTextSpacing: CGFloat = CGFloat(SpacingScheme.iconIconSpacing)

    private static let minTitleSubtitleSpacing: CGFloat = 2

    private static let textVerticalOffset: CGFloat = 1

    private static let badgeMaxCount = 99

    private static let trailingPadding: CGFloat = CGFloat(SpacingScheme.bubbleSpacing)

    private static let statusIconSize: CGFloat = 14

    private static let sendingIndicatorSlotSize: CGFloat = MessageSendingSpinnerView.size

    private static let muteIconSize: CGFloat = 16

    private static let muteIconTopSpacing: CGFloat = CGFloat(SpacingScheme.iconTextSpacing)

    private static let separatorHeight: CGFloat = 0.5

    private static let titleFontSize: CGFloat = 18

    private static let menuHighlightAlpha: CGFloat = 0.08

    private static let statusSubtitleSpacing: CGFloat = CGFloat(SpacingScheme.iconTextSpacing)

    private let avatarContainer = UIView()

    private let avatarImageView = UIImageView()

    private let avatarTextLabel = UILabel()

    private let avatarBadgeView = ConversationAvatarBadgeView()

    private let titleLabel = UILabel()

    private let subtitleLabel = UILabel()

    private let rightColumnContainer = UIView()

    private let timeLabel = UILabel()

    private let muteImageView = UIImageView()

    private let statusImageView = MessageSendFailBadgeView()

    private let sendingIndicator = MessageSendingSpinnerView()

    private let separatorView = UIView()

    private let menuHighlightOverlay = UIView()

    private var subtitleLeadingConstraint: Constraint?

    private var muteHeightConstraint: Constraint?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        constructViewHierarchy()
        activateConstraints()
        setupViewStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configure

    func setMenuHighlighted(_ highlighted: Bool) {
        menuHighlightOverlay.isHidden = !highlighted
    }

    func setSeparatorHidden(_ hidden: Bool) {
        separatorView.isHidden = hidden
    }

    private var titleAccessoryView: UIView?

    private var titleAccessoryConstraint: Constraint?

    func setTitleAccessory(_ view: UIView?) {
        titleAccessoryConstraint?.deactivate()
        titleAccessoryConstraint = nil
        titleAccessoryView?.removeFromSuperview()
        titleAccessoryView = view
        guard let view else { return }
        contentView.addSubview(view)
        view.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel.snp.trailing).offset(6)
            make.centerY.equalTo(titleLabel)
            make.trailing.lessThanOrEqualTo(rightColumnContainer.snp.leading).offset(-Self.trailingPadding)
        }
        titleLabel.snp.makeConstraints { make in
            titleAccessoryConstraint = make.trailing.lessThanOrEqualTo(view.snp.leading).offset(-6).constraint
        }
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    func configure(with conversation: ConversationInfo) {
        titleLabel.text = conversation.title ?? ""
        subtitleLabel.attributedText = ConversationCellFormatter.subtitleAttributedText(for: conversation)
        timeLabel.text = ConversationCellFormatter.timeText(for: conversation)

        configureAvatar(with: conversation)
        configureStatus(with: conversation)
        configureUnreadIndicators(with: conversation)
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        setTitleAccessory(nil)
        titleLabel.text = nil
        subtitleLabel.attributedText = nil
        timeLabel.text = nil
        muteImageView.isHidden = true
        statusImageView.isHidden = true
        separatorView.isHidden = false
        sendingIndicator.stopAnimating()
        avatarImageView.kf.cancelDownloadTask()
        avatarImageView.image = nil
        avatarBadgeView.setMode(.none)
        resetSwipe()
    }

    private func constructViewHierarchy() {
        selectionStyle = .none
        contentView.clipsToBounds = false
        clipsToBounds = false
        contentView.addSubview(avatarContainer)
        avatarContainer.addSubview(avatarImageView)
        avatarContainer.addSubview(avatarTextLabel)
        contentView.addSubview(avatarBadgeView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(rightColumnContainer)
        rightColumnContainer.addSubview(timeLabel)
        rightColumnContainer.addSubview(muteImageView)
        contentView.addSubview(statusImageView)
        contentView.addSubview(sendingIndicator)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(separatorView)
        menuHighlightOverlay.isUserInteractionEnabled = false
        contentView.addSubview(menuHighlightOverlay)
    }

    private func activateConstraints() {
        avatarContainer.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.avatarLeadingPadding)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.avatarSize)
        }
        avatarImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        avatarTextLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        avatarBadgeView.snp.makeConstraints { make in
            make.centerX.equalTo(avatarContainer.snp.trailing)
            make.centerY.equalTo(avatarContainer.snp.top)
        }
        rightColumnContainer.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Self.trailingPadding)
            make.centerY.equalToSuperview()
        }
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        muteImageView.snp.makeConstraints { make in
            make.top.equalTo(timeLabel.snp.bottom).offset(Self.muteIconTopSpacing)
            make.trailing.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview()
            make.width.equalTo(Self.muteIconSize)
            muteHeightConstraint = make.height.equalTo(0).constraint
            make.bottom.equalToSuperview()
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(avatarContainer.snp.trailing).offset(Self.avatarTextSpacing)
            make.top.equalTo(avatarContainer).offset(Self.textVerticalOffset)
            make.trailing.lessThanOrEqualTo(rightColumnContainer.snp.leading).offset(-Self.trailingPadding)
        }
        statusImageView.snp.makeConstraints { make in
            make.leading.equalTo(avatarContainer.snp.trailing).offset(Self.avatarTextSpacing)
            make.centerY.equalTo(subtitleLabel)
            make.width.height.equalTo(Self.statusIconSize)
        }
        sendingIndicator.snp.makeConstraints { make in
            make.center.equalTo(statusImageView)
        }
        subtitleLabel.snp.makeConstraints { make in
            make.top.greaterThanOrEqualTo(titleLabel.snp.bottom).offset(Self.minTitleSubtitleSpacing)
            make.bottom.equalTo(avatarContainer).offset(-Self.textVerticalOffset)
            subtitleLeadingConstraint = make.leading.equalTo(statusImageView.snp.trailing).offset(0).constraint
            make.trailing.lessThanOrEqualTo(rightColumnContainer.snp.leading).offset(-Self.trailingPadding)
        }
        separatorView.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel)
            make.trailing.bottom.equalToSuperview()
            make.height.equalTo(Self.separatorHeight)
        }
        menuHighlightOverlay.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func setupViewStyle() {
        let colors = TUIChatKitTheme.colors

        avatarContainer.backgroundColor = colors.bgColorAvatar
        avatarContainer.layer.cornerRadius = ChatAvatarView.shapedCornerRadius(diameter: Self.avatarSize, rounded: Self.avatarCornerRadius)
        avatarContainer.layer.masksToBounds = true

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.isHidden = true

        avatarTextLabel.font = FontScheme.caption1Medium
        avatarTextLabel.textColor = colors.textColorPrimary
        avatarTextLabel.textAlignment = .center

        titleLabel.font = .adaptiveSystemFont(ofSize: Self.titleFontSize, weight: .regular)
        titleLabel.textColor = colors.textColorPrimary
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = FontScheme.caption2Regular
        subtitleLabel.textColor = colors.textColorSecondary
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail

        timeLabel.font = FontScheme.caption3Regular
        timeLabel.textColor = colors.textColorSecondary
        timeLabel.textAlignment = LanguageHelper.isRTL ? .left : .right
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        muteImageView.image = UIImage(systemName: "bell.slash.fill")
        muteImageView.tintColor = colors.textColorSecondary
        muteImageView.contentMode = .scaleAspectFit

        statusImageView.applyTheme()

        separatorView.backgroundColor = colors.strokeColorSecondary

        menuHighlightOverlay.backgroundColor = UIColor.black.withAlphaComponent(Self.menuHighlightAlpha)
        menuHighlightOverlay.isHidden = true
    }

    // MARK: - Swipe actions (iOS 26+)
    //
    // iOS 26 draws UIContextualAction as floating round buttons, which does not match the full-height
    // rectangular buttons of the earlier systems and Android. On iOS 26 the list therefore drives the swipe
    // itself: the row content slides left and this panel slides in from the trailing edge underneath it.

    struct SwipeButton {
        let title: String
        let image: UIImage?
        let background: UIColor
        let handler: () -> Void
    }

    /// How far the content has moved to the left (0 = closed, `swipePanelWidth` = fully open).
    private(set) var swipeOffset: CGFloat = 0

    private(set) var swipePanelWidth: CGFloat = 0

    private var swipePanel: UIView?

    /// Buttons are given from the leading to the trailing side, e.g. [unread] [more] [delete].
    func setSwipeButtons(_ buttons: [SwipeButton]) {
        swipePanel?.removeFromSuperview()
        let panel = UIView()
        panel.clipsToBounds = true
        var x: CGFloat = 0
        for item in buttons {
            let button = SwipeActionButton(type: .custom)
            button.backgroundColor = item.background
            button.setImage(item.image, for: .normal)
            button.accessibilityLabel = item.title
            button.imageView?.contentMode = .center
            let handler = item.handler
            button.addAction(UIAction { _ in handler() }, for: .touchUpInside)
            let width = max(item.image?.size.width ?? 0, 72)
            button.frame = CGRect(x: x, y: 0, width: width, height: 0)
            panel.addSubview(button)
            x += width
        }
        swipePanelWidth = x
        panel.frame = CGRect(x: bounds.width, y: 0, width: x, height: bounds.height)
        insertSubview(panel, at: 0)
        swipePanel = panel
        setSwipeOffset(swipeOffset)
    }

    func setSwipeOffset(_ offset: CGFloat) {
        swipeOffset = max(0, offset)
        // The content has to cover the panel until it moves, so it takes the row colour while it is displaced.
        contentView.backgroundColor = swipeOffset > 0 ? (backgroundColor ?? .clear) : .clear
        contentView.transform = CGAffineTransform(translationX: -swipeOffset, y: 0)
        layoutSwipePanel()
    }

    private func layoutSwipePanel() {
        guard let panel = swipePanel else { return }
        panel.frame = CGRect(x: bounds.width - swipeOffset, y: 0, width: max(swipePanelWidth, swipeOffset), height: bounds.height)
        for button in panel.subviews { button.frame.size.height = bounds.height }
    }

    private func resetSwipe() {
        swipeOffset = 0
        contentView.transform = .identity
        contentView.backgroundColor = .clear
        swipePanel?.removeFromSuperview()
        swipePanel = nil
        swipePanelWidth = 0
    }

    override func layoutSubviews() {
        // UITableViewCell sets the content view's frame; with a transform on it that frame setter cancels the
        // displacement and the row snaps shut, so the transform is lifted for the system layout pass.
        let displacement = contentView.transform
        contentView.transform = .identity
        super.layoutSubviews()
        contentView.transform = displacement
        layoutSwipePanel()
    }

    private func configureAvatar(with conversation: ConversationInfo) {
        let urlString = conversation.avatarURL ?? ""
        let displayName = conversation.title ?? conversation.conversationID
        if urlString.isEmpty {
            showTextAvatar(name: displayName)
        } else {
            loadImageAvatar(urlString: urlString, fallbackName: displayName)
        }
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

    private func configureStatus(with conversation: ConversationInfo) {
        switch ConversationCellFormatter.sendStatus(for: conversation) {
        case .error:
            statusImageView.applyTheme()
            statusImageView.isHidden = false
            sendingIndicator.stopAnimating()
            statusImageView.snp.updateConstraints { $0.width.height.equalTo(Self.statusIconSize) }
            subtitleLeadingConstraint?.update(offset: Self.statusSubtitleSpacing)
        case .sending:
            statusImageView.isHidden = true
            sendingIndicator.startAnimating()
            statusImageView.snp.updateConstraints { $0.width.height.equalTo(Self.sendingIndicatorSlotSize) }
            subtitleLeadingConstraint?.update(offset: Self.statusSubtitleSpacing)
        case .none:
            statusImageView.isHidden = true
            sendingIndicator.stopAnimating()
            statusImageView.snp.updateConstraints { $0.width.height.equalTo(0) }
            subtitleLeadingConstraint?.update(offset: 0)
        }
    }

    private func configureUnreadIndicators(with conversation: ConversationInfo) {
        let isUnread = conversation.unreadCount > 0 || conversation.conversationMarkList.contains(.unread)

        if conversation.shouldShowDoNotDisturbIndicator {
            muteImageView.isHidden = false
            muteHeightConstraint?.update(offset: Self.muteIconSize)
            avatarBadgeView.setMode(isUnread ? .dot : .none)
        } else {
            muteImageView.isHidden = true
            muteHeightConstraint?.update(offset: 0)
            if isUnread {
                let count = conversation.unreadCount
                let text = count > Self.badgeMaxCount ? "\(Self.badgeMaxCount)+" : "\(max(count, 1))"
                avatarBadgeView.setMode(.text(text))
            } else {
                avatarBadgeView.setMode(.none)
            }
        }
    }
}

// MARK: - SwipeActionButton

/// One button of the iOS 26 swipe panel: the icon and label come as a single image, the press only dims it.
private final class SwipeActionButton: UIButton {
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }
}

// MARK: - ConversationAvatarBadgeView

private final class ConversationAvatarBadgeView: UIView {
    enum Mode {
        case none
        case dot
        case text(String)
    }

    override var intrinsicContentSize: CGSize {
        switch mode {
        case .none:
            return .zero
        case .dot:
            return CGSize(width: Self.dotSize, height: Self.dotSize)
        case .text(let text):
            let textWidth = (text as NSString).size(withAttributes: [.font: Self.textFont]).width
            return CGSize(
                width: ceil(textWidth) + Self.textHorizontalPadding * 2,
                height: Self.textHeight
            )
        }
    }

    private static let textHeight: CGFloat = 16

    private static let textHorizontalPadding: CGFloat = 5

    private static let dotSize: CGFloat = 8

    private static let textFont = FontScheme.caption3Bold

    private let textLabel = UILabel()

    private var mode: Mode = .none

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = TUIChatKitTheme.colors.textColorError
        textLabel.font = Self.textFont
        textLabel.textColor = TUIChatKitTheme.colors.textColorButton
        textLabel.textAlignment = .center
        addSubview(textLabel)
        textLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(
                top: 0,
                left: Self.textHorizontalPadding,
                bottom: 0,
                right: Self.textHorizontalPadding
            )).priority(.high)
        }
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMode(_ mode: Mode) {
        self.mode = mode
        switch mode {
        case .none:
            isHidden = true
        case .dot:
            isHidden = false
            textLabel.text = nil
            layer.cornerRadius = Self.dotSize / 2
        case .text(let text):
            isHidden = false
            textLabel.text = text
            layer.cornerRadius = Self.textHeight / 2
        }
        layer.masksToBounds = true
        invalidateIntrinsicContentSize()
    }
}
