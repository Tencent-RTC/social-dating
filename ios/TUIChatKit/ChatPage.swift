import AtomicXCore
import Combine
import SnapKit
import UIKit
import AtomicX

/// A chip under the chat title; the host decides the text and the fill colour.
public struct ChatHeaderChip {
    public let text: String
    public let color: UIColor
    /// Defaults to the chip's white text; the neutral 「未知」 pill passes `textColorSecondary` instead.
    public let textColor: UIColor?

    public init(text: String, color: UIColor, textColor: UIColor? = nil) {
        self.text = text
        self.color = color
        self.textColor = textColor
    }
}

public final class ChatPage: UIViewController {    private static let navBarHeight: CGFloat = 48

    private static let navHorizontalInset: CGFloat = CGFloat(SpacingScheme.bubbleSpacing)
    private static let headerTapInset: CGFloat = 56

    private static let backButtonSize: CGFloat = 28

    private static let moreButtonSize: CGFloat = 24

    private static let failureBarSideInset: CGFloat = CGFloat(SpacingScheme.bubbleSpacing)

    private static let failureBarBottomSpacing: CGFloat = CGFloat(SpacingScheme.smallSpacing)

    private static let failureBarHorizontalPadding: CGFloat = CGFloat(SpacingScheme.bubbleSpacing)

    private static let failureBarVerticalPadding: CGFloat = CGFloat(SpacingScheme.smallSpacing)

    private static let failureBarMinHeight: CGFloat = 40

    private static let failureBarIconSize: CGFloat = 16

    private static let failureBarIconTextGap: CGFloat = CGFloat(SpacingScheme.iconTextSpacing)

    private static let failureBarMaxTextWidth: CGFloat = 340

    private static let failureBarDisplayDuration: TimeInterval = 3

    private static let failureBarFadeDuration: TimeInterval = 0.25

    private static let dividerHeight: CGFloat = 0.5

    private static let titleCenterXPriority = UILayoutPriority(rawValue: 750)

    private static let failureBarCornerRadius: CGFloat = 6

    private static let failureBarMaxLineCount: Int = 3

    private static let backIconFallbackPointSize: CGFloat = 18

    private static let titleFontSize: CGFloat = 17

    private static let moreIconPointSize: CGFloat = 20

    private let conversation: ConversationInfo

    public var conversationID: String { conversation.conversationID }

    private let locateMessage: MessageInfo?

    private let onBack: (() -> Void)?


    private let onMessageSent: (() -> Void)?

    private let onUserClick: ((String) -> Void)?

    private let onMoreClick: (() -> Void)?

    private let isShowMoreButton: Bool

    private let navigationBar = UIView()
    private let headerTapArea = UIControl()

    private let backButton = ExpandedHitButton(type: .system)

    private let titleLabel = UILabel()

    private let moreButton = UIButton(type: .system)

    private let callButton = UIButton(type: .system)

    private let subtitleLabel = UILabel()

    private let chipsRow = UIStackView()

    private let cancelMultiSelectButton = UIButton(type: .system)

    private let divider = UIView()

    private let sendFailureBar = UIView()

    private let sendFailureIconView = UIImageView()

    private let sendFailureLabel = UILabel()

    private var sendFailureHideWorkItem: DispatchWorkItem?

    private var isInMultiSelectMode = false

    private let messageInputConfig: MessageInputConfigProtocol

    private let messageListConfig: MessageListConfigProtocol & MessageActionConfigProtocol

    private var typingCancellable: AnyCancellable?

    private lazy var messageListView: MessageListView = {
        let view = MessageListView(
            conversationID: conversation.id,

            config: messageListConfig,
            locateMessage: locateMessage,
            onUserClick: { [weak self] userID in
                self?.onUserClick?(userID)
            }
        )
        view.onMultiSelectModeChange = { [weak self] isMultiSelect in
            self?.updateInputVisibility(multiSelect: isMultiSelect)
        }
        return view
    }()

    private lazy var messageInputView: MessageInputView = {
        let view = MessageInputView(
            conversationID: conversation.id,
            config: messageInputConfig
        )
        view.onSendFailure = { [weak self] reason in
            self?.showSendFailure(reason) ?? false
        }
        view.onMessageSent = { [weak self] in
            self?.onMessageSent?()
        }
        return view
    }()

    private var inputCollapseConstraint: NSLayoutConstraint?

    public var topBannerView: UIView? {
        didSet {
            guard oldValue !== topBannerView else { return }
            oldValue?.removeFromSuperview()
            updateTopBannerLayout()
        }
    }

    /// Host view pinned between the message list and the input bar (e.g. quick chips).
    /// Mirrors Android `ChatPageView.setMessageListFooterOverlay`.
    public var footerAccessoryView: UIView? {
        didSet {
            guard oldValue !== footerAccessoryView else { return }
            oldValue?.removeFromSuperview()
            updateTopBannerLayout()
        }
    }

    /// Host view shown before the earliest message once all older messages are loaded (the first item of the chat).
    /// It is not an IM message: no unread count, no conversation summary, no long-press menu. Mirrors Android
    /// `ChatPageView.setMessageListHeader`.
    public func setMessageListHeader(_ view: UIView?, heightFraction: CGFloat = 1.0 / 3.0, minHeight: CGFloat = 0) {
        messageListView.setConversationHeader(view, heightFraction: heightFraction, minHeight: minHeight)
    }

    /// Optional second header line under the title (host supplied; may be demo data).
    public var headerSubtitle: String? {
        didSet { applyHeaderSubtitle() }
    }

    /// Chips under the title; when not empty they replace `headerSubtitle`.
    public var headerChips: [ChatHeaderChip] = [] {
        didSet { applyHeaderChips() }
    }

    /// Text shown in the title while the peer is typing; the subtitle fades out meanwhile and the nickname comes back afterwards.
    public var typingTitleText: String?

    /// When set, the centre of the header (title and subtitle) is tappable; the host decides what to open.
    public var onHeaderClick: (() -> Void)? {
        didSet { headerTapArea.isHidden = onHeaderClick == nil }
    }

    public var headerAccessibilityLabel: String? {
        didSet { headerTapArea.accessibilityLabel = headerAccessibilityLabel }
    }

    /// When set, a call button is shown next to "more"; the host decides what to start.
    public var onCallClick: (() -> Void)? {
        didSet { callButton.isHidden = onCallClick == nil }
    }

    // MARK: - Init

    public init(
        conversation: ConversationInfo,
        locateMessage: MessageInfo? = nil,
        messageListConfig: (MessageListConfigProtocol & MessageActionConfigProtocol) = ChatMessageListConfig(isShowRightAvatar: true),
        messageInputConfig: MessageInputConfigProtocol = ChatMessageInputConfig(),
        isShowMoreButton: Bool = true,
        onBack: (() -> Void)? = nil,
        onUserClick: ((String) -> Void)? = nil,
        onMoreClick: (() -> Void)? = nil,
        onMessageSent: (() -> Void)? = nil
    ) {
        self.conversation = conversation
        self.locateMessage = locateMessage
        if var listConfig = messageListConfig as? ChatMessageListConfig {
            listConfig.excludeCustomMessagesByBusinessID(MessageInputView.typingMessageBusinessID)
            self.messageListConfig = listConfig
        } else {
            self.messageListConfig = messageListConfig
        }
        self.messageInputConfig = messageInputConfig
        self.onBack = onBack
        self.onUserClick = onUserClick
        self.onMoreClick = onMoreClick
        self.onMessageSent = onMessageSent
        self.isShowMoreButton = isShowMoreButton
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        sendFailureHideWorkItem?.cancel()
        typingCancellable?.cancel()
        messageInputView.invalidateTypingIndicator()
        NotificationCenter.default.removeObserver(self, name: ChatBackgroundStore.didChangeNotification, object: nil)
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        TUIChatKitLayoutDirection.install()
        constructViewHierarchy()
        activateConstraints()
        bindInteraction()
        setupViewStyle()
        bindChatBackground()
        updateTopBannerLayout()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        messageInputView.bottomSafeAreaInset = view.safeAreaInsets.bottom
    }

    /// ChatPage draws its own header; hide every ancestor system navigation bar while
    /// visible and restore the previous state when leaving.
    public var hidesHostNavigationBars = true

    private var restoredNavigationBars: [(UINavigationController, Bool)] = []

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        messageListView.hostVisibilityDidChange(true)
        guard hidesHostNavigationBars else { return }
        restoredNavigationBars.removeAll()
        var node: UIViewController? = self
        while let navigation = node?.navigationController {
            restoredNavigationBars.append((navigation, navigation.isNavigationBarHidden))
            navigation.setNavigationBarHidden(true, animated: animated)
            node = navigation
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        messageListView.hostVisibilityDidChange(false)
        // Pop or push-over: hand the bars back; viewWillAppear hides them again on return.
        for (navigation, wasHidden) in restoredNavigationBars {
            navigation.setNavigationBarHidden(wasHidden, animated: animated)
        }
    }

    /// Opens the input's emoji panel, as if the built-in emoji button was tapped.
    public func showEmojiPanel() {
        loadViewIfNeeded()
        messageInputView.openEmojiPanel()
    }

    /// Opens the input's "more" panel (design E4), as if the built-in "+" button was tapped.
    public func showMorePanel() {
        loadViewIfNeeded()
        messageInputView.openMorePanel()
    }

    public var inputBottomAccessoryView: UIView? {
        didSet { messageInputView.bottomAccessoryView = inputBottomAccessoryView }
    }

    public var onInputPanelChanged: ((MessageInputPanel) -> Void)? {
        didSet { messageInputView.onPanelChanged = onInputPanelChanged }
    }

    public func toggleEmojiPanel() {
        loadViewIfNeeded()
        messageInputView.toggleEmojiPanel()
    }

    public func toggleMorePanel() {
        loadViewIfNeeded()
        messageInputView.toggleMorePanel()
    }

    public func collapseInputPanels() {
        loadViewIfNeeded()
        messageInputView.collapsePanels()
    }

    public func pickAlbumAndSend() {
        loadViewIfNeeded()
        messageInputView.pickAlbumAndSend()
    }

    @discardableResult
    public func performInputAction(_ id: String) -> Bool {
        loadViewIfNeeded()
        return messageInputView.performMenuAction(id: id)
    }

    @objc private func handleCallTapped() {
        onCallClick?()
    }

    @objc private func handleHeaderTapped() {
        onHeaderClick?()
    }

    // MARK: - Actions

    private func constructViewHierarchy() {
        view.addSubview(navigationBar)
        headerTapArea.isHidden = onHeaderClick == nil
        headerTapArea.isAccessibilityElement = true
        headerTapArea.accessibilityTraits = .button
        headerTapArea.accessibilityLabel = headerAccessibilityLabel
        navigationBar.addSubview(headerTapArea)
        navigationBar.addSubview(backButton)
        navigationBar.addSubview(titleLabel)
        navigationBar.addSubview(moreButton)
        navigationBar.addSubview(callButton)
        navigationBar.addSubview(subtitleLabel)
        chipsRow.axis = .horizontal
        chipsRow.spacing = 4
        chipsRow.alignment = .center
        chipsRow.isHidden = true
        navigationBar.addSubview(chipsRow)
        navigationBar.addSubview(cancelMultiSelectButton)
        view.addSubview(divider)
        view.addSubview(messageListView)
        view.addSubview(messageInputView)
        view.addSubview(sendFailureBar)
        sendFailureBar.addSubview(sendFailureIconView)
        sendFailureBar.addSubview(sendFailureLabel)
    }

    private func activateConstraints() {
        navigationBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(Self.navBarHeight)
        }
        headerTapArea.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.equalToSuperview().offset(Self.headerTapInset)
            make.trailing.equalToSuperview().offset(-Self.headerTapInset)
        }
        backButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.navHorizontalInset)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.backButtonSize)
        }
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview().priority(Self.titleCenterXPriority)
            make.centerY.equalToSuperview().offset(0)
            make.leading.greaterThanOrEqualTo(backButton.snp.trailing).offset(Self.navHorizontalInset)
            make.trailing.lessThanOrEqualTo(callButton.snp.leading).offset(-Self.navHorizontalInset)
        }
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(1)
            make.centerX.equalTo(titleLabel)
            make.width.lessThanOrEqualTo(navigationBar).multipliedBy(0.6)
        }
        chipsRow.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(1)
            make.centerX.equalTo(titleLabel)
            make.width.lessThanOrEqualTo(navigationBar).multipliedBy(0.6)
        }
        moreButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Self.navHorizontalInset)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.moreButtonSize)
        }
        callButton.snp.makeConstraints { make in
            make.trailing.equalTo(moreButton.snp.leading).offset(-Self.navHorizontalInset)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.moreButtonSize)
        }
        cancelMultiSelectButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.navHorizontalInset)
            make.centerY.equalToSuperview()
            make.height.equalTo(Self.backButtonSize)
        }
        divider.snp.makeConstraints { make in
            make.top.equalTo(navigationBar.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(Self.dividerHeight)
        }
        messageListView.snp.makeConstraints { make in
            make.top.equalTo(divider.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(messageInputView.snp.top)
        }

        messageInputView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }
        inputCollapseConstraint = messageInputView.heightAnchor.constraint(equalToConstant: 0)

        sendFailureBar.snp.makeConstraints { make in
            make.bottom.equalTo(messageInputView.snp.top).offset(-Self.failureBarBottomSpacing)
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(Self.failureBarSideInset)
            make.trailing.lessThanOrEqualToSuperview().offset(-Self.failureBarSideInset)
            make.height.greaterThanOrEqualTo(Self.failureBarMinHeight)
        }
        sendFailureIconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.failureBarHorizontalPadding)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.failureBarIconSize)
        }
        sendFailureLabel.snp.makeConstraints { make in
            make.leading.equalTo(sendFailureIconView.snp.trailing).offset(Self.failureBarIconTextGap)
            make.trailing.equalToSuperview().offset(-Self.failureBarHorizontalPadding)
            make.top.equalToSuperview().offset(Self.failureBarVerticalPadding)
            make.bottom.equalToSuperview().offset(-Self.failureBarVerticalPadding)
            make.width.lessThanOrEqualTo(Self.failureBarMaxTextWidth)
        }
    }

    private func bindInteraction() {
        backButton.addTarget(self, action: #selector(handleBackTapped), for: .touchUpInside)
        cancelMultiSelectButton.addTarget(self, action: #selector(handleCancelMultiSelectTapped), for: .touchUpInside)
        moreButton.addTarget(self, action: #selector(handleMoreTapped), for: .touchUpInside)
        callButton.addTarget(self, action: #selector(handleCallTapped), for: .touchUpInside)
        headerTapArea.addTarget(self, action: #selector(handleHeaderTapped), for: .touchUpInside)
        bindTypingIndicator()
    }

    private func updateTopBannerLayout() {
        guard isViewLoaded else { return }
        if let banner = topBannerView {
            view.insertSubview(banner, belowSubview: sendFailureBar)
            banner.snp.remakeConstraints { make in
                make.top.equalTo(divider.snp.bottom)
                make.leading.trailing.equalToSuperview()
            }
        }
        if let footer = footerAccessoryView {
            view.insertSubview(footer, belowSubview: sendFailureBar)
            footer.snp.remakeConstraints { make in
                make.leading.trailing.equalToSuperview()
                make.bottom.equalTo(messageInputView.snp.top)
            }
        }
        messageListView.snp.remakeConstraints { make in
            make.top.equalTo(topBannerView?.snp.bottom ?? divider.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(footerAccessoryView?.snp.top ?? messageInputView.snp.top)
        }
    }

    private func applyHeaderSubtitle() {
        guard isViewLoaded else { return }
        let text = headerSubtitle ?? ""
        subtitleLabel.text = text
        subtitleLabel.isHidden = text.isEmpty || !headerChips.isEmpty
        chipsRow.isHidden = headerChips.isEmpty
        titleLabel.snp.updateConstraints { make in
            make.centerY.equalToSuperview().offset(hasHeaderSubtitle ? -7 : 0)
        }
    }

    private var hasHeaderSubtitle: Bool {
        !(headerSubtitle ?? "").isEmpty || !headerChips.isEmpty
    }

    private func applyHeaderChips() {
        guard isViewLoaded else { return }
        chipsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for chip in headerChips {
            chipsRow.addArrangedSubview(makeChip(chip))
        }
        applyHeaderSubtitle()
    }

    private func makeChip(_ chip: ChatHeaderChip) -> UILabel {
        let label = ChatHeaderChipLabel()
        label.text = chip.text
        label.font = .adaptiveSystemFont(ofSize: 10)
        label.textColor = chip.textColor ?? TUIChatKitTheme.colors.textColorButton
        label.textAlignment = .center
        label.backgroundColor = chip.color
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return label
    }

    private var isPeerTypingShown = false

    private func applyPeerTyping(_ isTyping: Bool) {
        guard isTyping != isPeerTypingShown else { return }
        isPeerTypingShown = isTyping
        let colors = TUIChatKitTheme.colors
        let text = isTyping
            ? (typingTitleText ?? LocalizedChatString("Typing"))
            : (conversation.title ?? conversation.conversationID)
        UIView.transition(with: titleLabel, duration: 0.16, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.titleLabel.text = text
            self.titleLabel.textColor = isTyping ? colors.textColorLink : colors.textColorPrimary
        }
        UIView.animate(withDuration: 0.16) {
            self.subtitleLabel.alpha = isTyping ? 0 : 1
            self.chipsRow.alpha = isTyping ? 0 : 1
        }
    }

    public func fillInputText(_ text: String) {
        messageInputView.fillText(text)
    }

    private func bindTypingIndicator() {
        guard let typingPublisher = messageInputView.typingPublisher else { return }
        messageInputView.onTypingContentChanged = { [weak self] hasContent in
            self?.messageInputView.sendTypingStatus(hasContent: hasContent)
        }
        typingCancellable = typingPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTyping in
                self?.applyPeerTyping(isTyping)
            }
    }

    private func bindChatBackground() {
        applyChatBackground()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChatBackgroundChanged(_:)),
            name: ChatBackgroundStore.didChangeNotification,
            object: nil
        )
    }

    private func applyChatBackground() {
        let uri = ChatBackgroundStore.shared.imageURI(forConversationID: conversation.id)
        messageListView.applyChatBackgroundImage(uri: uri)
    }

    @objc private func handleChatBackgroundChanged(_ notification: Notification) {
        guard let changedID = notification.userInfo?[ChatBackgroundStore.conversationIDUserInfoKey] as? String,
              changedID == conversation.id else { return }
        applyChatBackground()
    }

    private func setupViewStyle() {
        let colors = TUIChatKitTheme.colors
        view.backgroundColor = colors.bgColorOperate

        sendFailureBar.backgroundColor = colors.bgColorOperate
        sendFailureBar.layer.cornerRadius = Self.failureBarCornerRadius
        sendFailureBar.layer.masksToBounds = true
        sendFailureBar.alpha = 0
        sendFailureBar.isHidden = true
        sendFailureBar.isUserInteractionEnabled = false

        sendFailureIconView.image = AtomicXChatResources.image(named: "message_toast_error")
        sendFailureIconView.contentMode = .scaleAspectFit

        sendFailureLabel.font = FontScheme.caption2Regular
        sendFailureLabel.textColor = colors.textColorPrimary
        sendFailureLabel.numberOfLines = Self.failureBarMaxLineCount
        sendFailureLabel.textAlignment = .natural

        if let backImage = AtomicXChatResources.image(named: "contact_info_back") {
            backButton.setImage(backImage.withRenderingMode(.alwaysTemplate), for: .normal)
        } else {
            backButton.setImage(
                UIImage(systemName: "chevron.left")?
                    .withConfiguration(UIImage.SymbolConfiguration(pointSize: Self.backIconFallbackPointSize, weight: .semibold)),
                for: .normal
            )
        }
        backButton.tintColor = colors.textColorPrimary
        backButton.contentHorizontalAlignment = .leading

        titleLabel.text = conversation.title ?? conversation.conversationID
        titleLabel.font = .adaptiveSystemFont(ofSize: Self.titleFontSize, weight: .bold)
        titleLabel.textColor = colors.textColorPrimary
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textAlignment = .center

        moreButton.setImage(
            UIImage(systemName: "ellipsis")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: Self.moreIconPointSize, weight: .semibold)),
            for: .normal
        )
        moreButton.tintColor = colors.textColorSecondary
        moreButton.isHidden = !isShowMoreButton

        callButton.setImage(
            UIImage(systemName: "phone")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: Self.moreIconPointSize - 2, weight: .regular)),
            for: .normal
        )
        callButton.tintColor = colors.textColorPrimary
        callButton.isHidden = onCallClick == nil

        subtitleLabel.font = .adaptiveSystemFont(ofSize: 10)
        subtitleLabel.textColor = colors.textColorSecondary
        subtitleLabel.textAlignment = .center
        applyHeaderChips()

        cancelMultiSelectButton.setTitle(LocalizedChatString("Cancel"), for: .normal)
        cancelMultiSelectButton.setTitleColor(colors.textColorLink, for: .normal)
        cancelMultiSelectButton.titleLabel?.font = FontScheme.caption1Regular
        cancelMultiSelectButton.contentHorizontalAlignment = .leading
        cancelMultiSelectButton.isHidden = true

        divider.backgroundColor = colors.strokeColorPrimary
        messageInputView.backgroundColor = colors.bgColorOperate
    }

    private func showSendFailure(_ reason: String) -> Bool {
        guard !reason.isEmpty else { return true }
        guard isViewLoaded, view.window != nil else { return false }
        sendFailureHideWorkItem?.cancel()
        sendFailureLabel.text = reason
        sendFailureBar.isHidden = false
        UIView.animate(withDuration: Self.failureBarFadeDuration) {
            self.sendFailureBar.alpha = 1
        }

        let hideWorkItem = DispatchWorkItem { [weak self] in
            self?.hideSendFailure()
        }
        sendFailureHideWorkItem = hideWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.failureBarDisplayDuration,
            execute: hideWorkItem
        )
        return true
    }

    private func hideSendFailure() {
        UIView.animate(
            withDuration: Self.failureBarFadeDuration,
            animations: { self.sendFailureBar.alpha = 0 },
            completion: { [weak self] _ in
                guard self?.sendFailureBar.alpha == 0 else { return }
                self?.sendFailureBar.isHidden = true
                self?.sendFailureLabel.text = nil
            }
        )
    }

    private func updateInputVisibility(multiSelect: Bool) {
        isInMultiSelectMode = multiSelect
        if multiSelect {
            messageInputView.endEditing(true)
        }
        messageInputView.isHidden = multiSelect
        inputCollapseConstraint?.isActive = multiSelect
        backButton.isHidden = multiSelect
        moreButton.isHidden = multiSelect || !isShowMoreButton
        callButton.isHidden = multiSelect || onCallClick == nil
        footerAccessoryView?.isHidden = multiSelect
        cancelMultiSelectButton.isHidden = !multiSelect
    }

    @objc private func handleBackTapped() {
        onBack?()
    }

    @objc private func handleCancelMultiSelectTapped() {
        messageListView.exitMultiSelectMode()
    }

    @objc private func handleMoreTapped() {
        onMoreClick?()
    }
}

private final class ChatHeaderChipLabel: UILabel {
    private let insets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 7)

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }
}
