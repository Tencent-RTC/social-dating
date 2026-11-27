import UIKit
import SnapKit
import AtomicXCore
import AtomicX

final class MessageInputViewImpl: UIView {
    var onIntrinsicContentSizeInvalidated: (() -> Void)?

    var onAnimateSuperviewLayout: (() -> Void)?

    var bottomSafeAreaInset: CGFloat = 0 {
        didSet {
            guard bottomSafeAreaInset != oldValue else { return }

            if didAttachEmojiPicker {
                emojiPickerView.bottomSafeAreaInset = bottomSafeAreaInset
            }
            if didAttachMorePanel {
                morePanel.bottomSafeAreaInset = bottomSafeAreaInset
            }
            syncBottomAreaHeight()
        }
    }

    override var intrinsicContentSize: CGSize {
        let inputRowHeight = inputRowVerticalPadding + currentInputContainerHeight + inputRowVerticalPadding
        return CGSize(
            width: UIView.noIntrinsicMetric,
            height: Self.topDividerHeight + currentQuoteBarHeight + inputRowHeight + currentAccessoryHeight + currentBottomAreaHeight
        )
    }

    var onPanelChanged: ((MessageInputPanel) -> Void)? {
        didSet {
            lastReportedPanel = nil
            reportPanel()
        }
    }

    var bottomAccessoryView: UIView? {
        didSet {
            guard oldValue !== bottomAccessoryView else { return }
            installBottomAccessory(replacing: oldValue)
        }
    }

    private var lastReportedPanel: MessageInputPanel?

    private let accessoryContainer = UIView()

    private var accessoryHeightConstraint: Constraint?

    private var currentAccessoryHeight: CGFloat = 0

    private var inputTrailingToSendConstraint: Constraint?

    private var inputTrailingToRowConstraint: Constraint?

    private var usesCollapsibleTrailing: Bool {
        !config.isShowMore && !config.isShowEmoji
    }

    private var minimumInputContainerHeight: CGFloat {
        max(Self.defaultInputContainerHeight, config.appearance?.fieldMinHeight ?? 0)
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onIntrinsicContentSizeInvalidated?()
    }

    private let viewModel: MessageInputViewModel

    private let config: MessageInputConfigProtocol

    var onTypingContentChanged: ((Bool) -> Void)?

    var onMessageSent: (() -> Void)? {
        get { viewModel.onMessageSent }
        set { viewModel.onMessageSent = newValue }
    }

    var onSendFailure: ((String) -> Bool)?

    private let topDivider = UIView()

    private let inputRow = UIView()

    private let audioButton = UIButton(type: .system)

    private let inputContainer = UIView()

    private let messageTextView = MessageInputTextView()

    private let voiceLabel = UILabel()

    private let emojiButton = UIButton(type: .system)

    private let moreButton = UIButton(type: .system)

    private let moreButtonRedDot = UIView()

    private let sendButton = SendPillButton(type: .system)

    private let bottomContainer = UIView()

    private let emojiPanelContainer = UIView()

    private let morePanelContainer = UIView()

    private lazy var emojiPickerView: EmojiPickerView = {
        let picker = EmojiPickerView()
        picker.onEmojiSelected = { [weak self] emoji in self?.handleEmojiSelected(emoji) }
        picker.onCustomEmojiSelected = { [weak self] group, emoji in self?.handleCustomEmojiSelected(group: group, emoji: emoji) }
        picker.onDelete = { [weak self] in self?.deleteLastCharacter() }
        picker.onSend = { [weak self] in self?.requestSendText() }
        return picker
    }()

    private var didAttachEmojiPicker = false

    private lazy var morePanel: MessageInputMorePanel = {
        let panel = MessageInputMorePanel(config: viewModel.config)
        panel.delegate = self
        panel.onRedDotDismissed = { [weak self] in
            self?.updateMoreButtonRedDotVisibility()
        }
        return panel
    }()

    private var didAttachMorePanel = false

    private lazy var mediaCoordinator = MessageInputMediaCoordinator(presentingView: self, viewModel: viewModel)

    private let quotePreviewBar = MessageInputQuotePreviewBar()

    private var currentQuotedMessage: MessageInfo?

    private var inputContainerHeightConstraint: Constraint?

    private var bottomAreaHeightConstraint: Constraint?

    private var quotePreviewBarHeightConstraint: Constraint?

    private var currentInputContainerHeight: CGFloat = MessageInputViewImpl.defaultInputContainerHeight

    private var currentEmojiPanelHeight: CGFloat = 0

    private var currentMorePanelHeight: CGFloat = 0

    private var currentKeyboardHeight: CGFloat = 0

    private var currentQuoteBarHeight: CGFloat = 0

    private var mentionList: [MentionInfo] = []

    private var draftSaveWorkItem: DispatchWorkItem?

    private var isLoadingDraft = false

    private var didLoadDraft = false

    private var isEmojiPanelShown = false

    private var isMorePanelShown = false

    private var isLongPressingAudio = false

    private var isTextInputLongPressArmed = false

    private lazy var textInputLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handleTextInputLongPress(_:)))

    private lazy var textInputTap: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTextInputTap(_:)))
        tap.cancelsTouchesInView = false
        return tap
    }()

    private var isVoiceInputMode = false

    private static let emojiPanelHeight: CGFloat = 252

    // Design E4: 2 rows of 56pt tiles + titles + NEW badge rise + page dots.
    private static let morePanelHeight: CGFloat = 244

    private static let quotePreviewBarHeight: CGFloat = 36

    private static let minimumInputRowHeight: CGFloat = 56

    /// Mirrors Android `message_input_toolbar_row` (minHeight 56 + 8 padding): the row keeps the
    /// design's 56pt height and a taller field grows inside it instead of pushing the bar taller.
    /// Unmodified 34pt field still gets the previous 11pt padding.
    private var inputRowVerticalPadding: CGFloat {
        max(0, (Self.minimumInputRowHeight - minimumInputContainerHeight) / 2)
    }

    private static let topDividerHeight: CGFloat = 0.5

    private static let defaultInputContainerHeight: CGFloat = 34

    private static let inputRowHorizontalInset: CGFloat = CGFloat(SpacingScheme.smallSpacing)

    private static let inputRowButtonSize: CGFloat = 28

    private static let redDotSize: CGFloat = 8

    private static let textViewHorizontalInset: CGFloat = CGFloat(SpacingScheme.smallSpacing)

    private static let textViewMaxLines: Int = 6

    private static let voiceLongPressMinimumDuration: TimeInterval = 0.2

    private static let inputContainerCornerRadius: CGFloat = CGFloat(RadiusScheme.tipsRadius)

    private static let sendButtonCornerRadius: CGFloat = 14

    private static let sendButtonIconPointSize: CGFloat = 14

    private static let draftSaveDebounceInterval: TimeInterval = 0.8

    private static let draftKeyboardFocusDelay: TimeInterval = 0.15

    private static let draftLoadingResetDelay: TimeInterval = 0.2

    private static let layoutAnimationDuration: TimeInterval = 0.2

    private var currentBottomAreaHeight: CGFloat {
        if currentKeyboardHeight > 0 {
            return currentKeyboardHeight
        }
        return currentEmojiPanelHeight + currentMorePanelHeight + bottomSafeAreaInset
    }

    // MARK: - Init

    init(conversationID: String, config: MessageInputConfigProtocol = ChatMessageInputConfig()) {
        let viewModel = MessageInputViewModel(conversationID: conversationID, config: config)
        self.viewModel = viewModel
        self.config = viewModel.config
        super.init(frame: .zero)
        viewModel.onSendFailure = { [weak self] reason in
            self?.onSendFailure?(reason) ?? false
        }
        constructViewHierarchy()
        activateConstraints()
        bindInteraction()
        setupViewStyle()
        applyAppearance()
        fetchVideoRecorderSignature()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Four-Step Lifecycle

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Window Lifecycle (对齐声明式 onAppear/onDisappear 草稿逻辑)

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if !didLoadDraft {
                didLoadDraft = true
                loadDraft()
            }
        } else {
            saveDraftImmediately()
        }
    }

    // MARK: - Quote (引用)

    private func constructViewHierarchy() {
        addSubview(topDivider)
        addSubview(quotePreviewBar)
        addSubview(inputRow)
        if config.isShowAudioRecorder {
            inputRow.addSubview(audioButton)
        }
        inputRow.addSubview(inputContainer)
        inputContainer.addSubview(messageTextView)
        inputContainer.addSubview(voiceLabel)
        if config.isShowEmoji {
            inputRow.addSubview(emojiButton)
        }
        if config.isShowMore {
            inputRow.addSubview(moreButton)
            moreButton.addSubview(moreButtonRedDot)
        }
        inputRow.addSubview(sendButton)
        addSubview(accessoryContainer)
        addSubview(bottomContainer)
        bottomContainer.addSubview(emojiPanelContainer)
        bottomContainer.addSubview(morePanelContainer)
    }

    private func activateConstraints() {
        topDivider.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(Self.topDividerHeight)
        }

        quotePreviewBar.snp.makeConstraints { make in
            make.top.equalTo(inputRow.snp.bottom)
            make.leading.trailing.equalToSuperview()
            quotePreviewBarHeightConstraint = make.height.equalTo(0).constraint
        }

        inputRow.snp.makeConstraints { make in
            make.top.equalTo(topDivider.snp.bottom)
            make.leading.trailing.equalToSuperview()
        }

        var leftAnchor = inputRow.snp.leading
        var leftInset: CGFloat = Self.inputRowHorizontalInset
        if config.isShowAudioRecorder {
            let audioButtonSize = config.appearance?.audioButtonSize ?? Self.inputRowButtonSize
            audioButton.snp.makeConstraints { make in
                make.leading.equalTo(leftAnchor).offset(leftInset)
                make.centerY.equalTo(inputContainer)
                make.width.height.equalTo(audioButtonSize)
            }
            leftAnchor = audioButton.snp.trailing
            leftInset = Self.inputRowHorizontalInset
        }

        var rightAnchor = inputRow.snp.trailing
        var rightInset: CGFloat = -Self.inputRowHorizontalInset

        if config.isShowMore {
            moreButton.snp.makeConstraints { make in
                make.trailing.equalTo(rightAnchor).offset(rightInset)
                make.centerY.equalTo(inputContainer)
                make.width.height.equalTo(Self.inputRowButtonSize)
            }
            moreButtonRedDot.snp.makeConstraints { make in
                make.top.trailing.equalToSuperview()
                make.width.height.equalTo(Self.redDotSize)
            }
        }
        sendButton.snp.makeConstraints { make in
            make.trailing.equalTo(rightAnchor).offset(rightInset)
            make.centerY.equalTo(inputContainer)
            if config.appearance?.sendButtonTitle != nil {
                let height = config.appearance?.sendButtonHeight ?? Self.inputRowButtonSize
                make.height.equalTo(height)
                make.width.greaterThanOrEqualTo(height)
            } else {
                make.width.height.equalTo(Self.inputRowButtonSize)
            }
        }
        rightAnchor = config.isShowMore ? moreButton.snp.leading : sendButton.snp.leading
        rightInset = -Self.inputRowHorizontalInset

        if config.isShowEmoji {
            emojiButton.snp.makeConstraints { make in
                make.trailing.equalTo(rightAnchor).offset(rightInset)
                make.centerY.equalTo(inputContainer)
                make.width.height.equalTo(Self.inputRowButtonSize)
            }
            rightAnchor = emojiButton.snp.leading
            rightInset = -Self.inputRowHorizontalInset
        }

        inputContainer.snp.makeConstraints { make in
            make.leading.equalTo(leftAnchor).offset(leftInset)
            if usesCollapsibleTrailing {
                inputTrailingToSendConstraint = make.trailing.equalTo(rightAnchor).offset(rightInset).constraint
                inputTrailingToRowConstraint = make.trailing.equalTo(inputRow.snp.trailing)
                    .offset(-Self.inputRowHorizontalInset).constraint
            } else {
                make.trailing.equalTo(rightAnchor).offset(rightInset)
            }
            make.top.equalToSuperview().offset(inputRowVerticalPadding)
            make.bottom.equalToSuperview().offset(-inputRowVerticalPadding)
            inputContainerHeightConstraint = make.height.equalTo(minimumInputContainerHeight).constraint
        }
        inputTrailingToSendConstraint?.deactivate()

        messageTextView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.textViewHorizontalInset)
            make.trailing.equalToSuperview().offset(-Self.textViewHorizontalInset)
            make.top.bottom.equalToSuperview()
        }

        voiceLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        bottomContainer.snp.makeConstraints { make in
            make.top.equalTo(accessoryContainer.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
            bottomAreaHeightConstraint = make.height.equalTo(0).constraint
        }

        accessoryContainer.snp.makeConstraints { make in
            make.top.equalTo(quotePreviewBar.snp.bottom)
            make.leading.trailing.equalToSuperview()
            accessoryHeightConstraint = make.height.equalTo(0).constraint
        }

        emojiPanelContainer.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        morePanelContainer.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func bindInteraction() {
        messageTextView.isGroupChat = viewModel.isGroupChat
        messageTextView.enableMention = config.enableMention
        messageTextView.maxLines = Self.textViewMaxLines
        messageTextView.placeholderText = LocalizedChatString(config.enableLongPressToTalk ? "SendMessage" : "SendMessageTextOnly")

        messageTextView.onSend = { [weak self] in self?.sendText() }
        messageTextView.onHeightChanged = { [weak self] height in
            guard let self = self else { return }
            let resolved = max(height, self.minimumInputContainerHeight)
            self.inputContainerHeightConstraint?.update(offset: resolved)
            self.currentInputContainerHeight = resolved
            self.invalidateIntrinsicContentSize()
        }
        messageTextView.onContentChanged = { [weak self] _ in
            self?.handleContentChanged()
            self?.updateSendButtonVisibility()
        }
        messageTextView.onUserTextChanged = { [weak self] hasContent in
            self?.onTypingContentChanged?(hasContent)
        }
        messageTextView.onAtTriggered = { [weak self] position in
            guard let self = self, self.viewModel.isGroupChat, self.config.enableMention else { return }
            self.presentMentionPicker(atPosition: position)
        }
        messageTextView.mentionToDeleteAtPosition = { [weak self] position in
            self?.findMentionToDelete(at: position)
        }
        messageTextView.onMentionDeleted = { [weak self] startIndex in
            self?.mentionList.removeAll { $0.startIndex == startIndex }
        }

        moreButton.addTarget(self, action: #selector(handleMoreTapped), for: .touchUpInside)
        emojiButton.addTarget(self, action: #selector(handleEmojiTapped), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(handleSendTapped), for: .touchUpInside)

        audioButton.addTarget(self, action: #selector(handleAudioTapped), for: .touchUpInside)

        let voiceLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handleAudioLongPress(_:)))
        voiceLongPress.minimumPressDuration = Self.voiceLongPressMinimumDuration
        voiceLongPress.isEnabled = config.enableLongPressToTalk
        voiceLabel.addGestureRecognizer(voiceLongPress)
        voiceLabel.isUserInteractionEnabled = true
        let voiceTap = UITapGestureRecognizer(target: self, action: #selector(handleAudioTapped))
        voiceLabel.addGestureRecognizer(voiceTap)

        textInputLongPress.isEnabled = config.enableLongPressToTalk
        textInputLongPress.delegate = self
        messageTextView.addGestureRecognizer(textInputLongPress)
        textInputTap.require(toFail: textInputLongPress)
        textInputTap.delegate = self
        messageTextView.addGestureRecognizer(textInputTap)
        messageTextView.shouldBlockFirstResponder = { [weak self] in
            return self?.isTextInputLongPressArmed == true
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTextViewDidChange),
            name: UITextView.textDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMentionUserNotification(_:)),
            name: NSNotification.Name("mentionUserNotification"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQuoteMessageNotification(_:)),
            name: NSNotification.Name("quoteMessageNotification"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMessageListBlankAreaClick),
            name: MessageListView.blankAreaClickNotification,
            object: nil
        )

        quotePreviewBar.onClose = { [weak self] in
            self?.clearQuote()
        }
    }

    private func setupViewStyle() {
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        let colors = TUIChatKitTheme.colors
        backgroundColor = colors.bgColorOperate
        topDivider.backgroundColor = colors.strokeColorPrimary
        inputRow.backgroundColor = colors.bgColorOperate

        inputContainer.backgroundColor = colors.bgColorInput
        inputContainer.layer.cornerRadius = Self.inputContainerCornerRadius
        inputContainer.layer.masksToBounds = true

        bottomContainer.backgroundColor = colors.bgColorOperate
        bottomContainer.clipsToBounds = true
        emojiPanelContainer.backgroundColor = colors.bgColorOperate
        emojiPanelContainer.clipsToBounds = true
        emojiPanelContainer.isHidden = true
        morePanelContainer.backgroundColor = colors.bgColorOperate
        morePanelContainer.clipsToBounds = true
        morePanelContainer.isHidden = true

        configureIconButton(audioButton, imageName: "input_audio")
        configureIconButton(emojiButton, imageName: "input_emoji")
        configureIconButton(moreButton, imageName: "input_more")
        configureSendButton()

        configureVoiceLabel()
        sendButton.isHidden = true

        moreButtonRedDot.backgroundColor = colors.textColorError
        moreButtonRedDot.layer.cornerRadius = Self.redDotSize / 2
        moreButtonRedDot.isUserInteractionEnabled = false
        moreButtonRedDot.isHidden = true
        if config.isShowMore {
            updateMoreButtonRedDotVisibility()
        }
    }

    /// Mirrors the panel's remaining dots onto the more button. Reading
    /// `morePanel` here also builds its actions up front, which is what lets the
    /// button carry a dot before the panel has ever been opened.
    private func updateMoreButtonRedDotVisibility() {
        moreButtonRedDot.isHidden = !morePanel.hasVisibleRedDot
    }

    private func applyAppearance() {
        currentInputContainerHeight = minimumInputContainerHeight
        guard let appearance = config.appearance else { return }
        if let color = appearance.fieldBackgroundColor {
            inputContainer.backgroundColor = color
        }
        if let radius = appearance.fieldCornerRadius {
            inputContainer.layer.cornerRadius = radius
        }
        if let placeholder = appearance.placeholder {
            messageTextView.placeholderText = placeholder
        }
        if let alignment = appearance.placeholderAlignment {
            messageTextView.placeholderAlignment = alignment
        }
        if let image = appearance.audioButtonImage {
            audioButton.setImage(image.withRenderingMode(audioIconRenderingMode), for: .normal)
        }
        if let tint = appearance.audioButtonTint {
            audioButton.tintColor = tint
        }
        if let title = appearance.sendButtonTitle {
            sendButton.setImage(nil, for: .normal)
            sendButton.setTitle(title, for: .normal)
            sendButton.setTitleColor(TUIChatKitTheme.colors.textColorButton, for: .normal)
            sendButton.titleLabel?.font = appearance.sendButtonFont ?? .adaptiveSystemFont(ofSize: 13, weight: .bold)
            sendButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 13, bottom: 0, right: 13)
            sendButton.setContentHuggingPriority(.required, for: .horizontal)
            sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        if let colors = appearance.sendButtonGradient, colors.count >= 2 {
            sendButton.backgroundColor = .clear
            sendButton.applyGradient(colors.map(\.cgColor))
        }
    }

    private func installBottomAccessory(replacing oldValue: UIView?) {
        oldValue?.removeFromSuperview()
        if let view = bottomAccessoryView {
            accessoryContainer.addSubview(view)
            view.snp.remakeConstraints { make in
                make.top.leading.trailing.equalToSuperview()
            }
            let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
            let size = view.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            currentAccessoryHeight = ceil(size.height)
        } else {
            currentAccessoryHeight = 0
        }
        accessoryHeightConstraint?.update(offset: currentAccessoryHeight)
        invalidateIntrinsicContentSize()
    }

    private func reportPanel() {
        let panel: MessageInputPanel
        if isEmojiPanelShown {
            panel = .emoji
        } else if isMorePanelShown {
            panel = .more
        } else if currentKeyboardHeight > 0 {
            panel = .keyboard
        } else {
            panel = .none
        }
        guard panel != lastReportedPanel else { return }
        lastReportedPanel = panel
        onPanelChanged?(panel)
    }

    func toggleEmojiPanel() {
        handleEmojiTapped()
    }

    func toggleMorePanel() {
        handleMoreTapped()
    }

    func collapsePanels() {
        hideEmojiPanel()
        hideMorePanel()
    }

    /// Opens the album picker and sends the picked image / video, independent of the (customisable) more panel.
    func pickAlbumAndSend() {
        morePanelDidSelectAlbum()
    }

    @discardableResult
    func performMenuAction(id: String) -> Bool {
        return morePanel.performAction(id: id)
    }

    private func configureIconButton(_ button: UIButton, imageName: String) {
        let image = AtomicXChatResources.image(named: imageName)?.withRenderingMode(.alwaysTemplate)
        button.setImage(image, for: .normal)
        button.tintColor = TUIChatKitTheme.colors.textColorSecondary
        button.imageView?.contentMode = .scaleAspectFit
    }

    private func configureSendButton() {
        let colors = TUIChatKitTheme.colors
        sendButton.backgroundColor = colors.buttonColorPrimaryDefault
        sendButton.layer.cornerRadius = Self.sendButtonCornerRadius
        sendButton.layer.masksToBounds = true
        let arrowImage = UIImage(systemName: "arrow.up")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: Self.sendButtonIconPointSize, weight: .bold))
            .withRenderingMode(.alwaysTemplate)
        sendButton.setImage(arrowImage, for: .normal)
        sendButton.tintColor = colors.textColorButton
    }

    private func configureVoiceLabel() {
        let colors = TUIChatKitTheme.colors
        voiceLabel.text = LocalizedChatString("InputHoldToTalk")
        voiceLabel.font = FontScheme.caption1Regular
        voiceLabel.textAlignment = .center
        voiceLabel.textColor = colors.textColorPrimary
        voiceLabel.backgroundColor = .clear
        voiceLabel.isHidden = true
    }

    private func setEmojiPanelContent(_ contentView: UIView?) {
        emojiPanelContainer.subviews.forEach { $0.removeFromSuperview() }
        guard let contentView = contentView else { return }
        emojiPanelContainer.addSubview(contentView)
        contentView.snp.makeConstraints { make in make.edges.equalToSuperview() }
    }

    private func showKeyboard() {
        messageTextView.becomeFirstResponder()
    }

    private func insertEmoji(_ emojiString: NSAttributedString, emojiName: String) {
        messageTextView.insertEmoji(emojiString, emojiName: emojiName)
    }

    private func deleteLastCharacter() {
        messageTextView.deleteLastCharacter()
    }

    private func requestSendText() {
        sendText()
    }

    private func appendMention(userID: String, displayName: String) {
        let displayTextLength = messageTextView.attributedContent?.length ?? 0
        let mentionText = "@\(displayName) "
        let mention = MentionInfo(
            userID: userID,
            displayName: displayName,
            startIndex: displayTextLength,
            length: mentionText.count
        )
        let attributed = EmojiManager.shared.createAttributedStringWithTextAndStyle(
            text: mentionText,
            withFont: FontScheme.caption1Regular,
            textColor: TUIChatKitTheme.colors.textColorPrimary
        )
        mentionList.append(mention)
        messageTextView.appendText(attributed)
        messageTextView.becomeFirstResponder()
    }

    private func insertMentions(_ mentions: [MentionInfo], atPosition: Int) {
        guard !mentions.isEmpty else { return }
        let adjustedPosition = messageTextView.convertDisplayPositionToTextPosition(atPosition)
        var currentText = messageTextView.extractSendText()
        if currentText.isEmpty { currentText = "@" }

        let atIndex = currentText.index(currentText.startIndex, offsetBy: min(adjustedPosition, currentText.count))
        let afterAtIndex = currentText.index(after: atIndex)

        var combinedMentionText = ""
        var newMentions: [MentionInfo] = []
        var currentOffset = adjustedPosition
        for mention in mentions {
            var newMention = mention
            newMention.startIndex = currentOffset
            combinedMentionText += mention.mentionText
            newMentions.append(newMention)
            currentOffset += mention.mentionText.count
        }

        currentText.replaceSubrange(atIndex..<afterAtIndex, with: combinedMentionText)

        let insertedLength = combinedMentionText.count - 1
        for i in 0..<mentionList.count where mentionList[i].startIndex > adjustedPosition {
            mentionList[i].startIndex += insertedLength
        }
        mentionList.append(contentsOf: newMentions)

        let newAttributedString = EmojiManager.shared.createAttributedStringWithTextAndStyle(
            text: currentText,
            withFont: FontScheme.caption1Regular,
            textColor: TUIChatKitTheme.colors.textColorPrimary
        )
        messageTextView.setContent(newAttributedString)
    }

    private func sendText() {
        let text = messageTextView.extractSendText()
        guard !text.isEmpty else { return }

        var convertedMentions: [MentionInfo] = []
        for mention in mentionList {
            let convertedStartIndex = messageTextView.convertDisplayPositionToTextPosition(mention.startIndex)
            convertedMentions.append(MentionInfo(
                userID: mention.userID,
                displayName: mention.displayName,
                startIndex: convertedStartIndex,
                length: mention.length
            ))
        }

        viewModel.sendTextMessage(text, mentionList: convertedMentions, quotedMessage: currentQuotedMessage)
        viewModel.clearDraft()
        mentionList.removeAll()
        clearQuote()
        messageTextView.clear()
        updateSendButtonVisibility()
    }

    private func findMentionToDelete(at position: Int) -> (startIndex: Int, length: Int)? {
        for mention in mentionList where position > mention.startIndex && position < mention.endIndex {
            return (mention.startIndex, mention.length)
        }
        return nil
    }

    private func presentMentionPicker(atPosition: Int) {
        let groupID = viewModel.groupID
        guard viewModel.isGroupChat, !groupID.isEmpty else { return }
        let picker = MentionMemberPickerViewController(
            groupID: groupID,
            atPosition: atPosition
        ) { [weak self] mentions, position in
            self?.insertMentions(mentions, atPosition: position)
            self?.messageTextView.becomeFirstResponder()
        }
        findViewController()?.present(picker, animated: true)
    }

    @objc private func handleMentionUserNotification(_ notification: Notification) {
        guard viewModel.isGroupChat, config.enableMention else { return }
        guard let userInfo = notification.userInfo,
              let userID = userInfo["userID"] as? String,
              let nickname = userInfo["nickname"] as? String else { return }
        appendMention(userID: userID, displayName: nickname)
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let viewController = next as? UIViewController {
                return viewController
            }
            responder = next
        }
        return nil
    }

    private func handleContentChanged() {
        guard !isLoadingDraft else { return }
        saveDraftWithDebounce()
    }

    private func saveDraftWithDebounce() {
        draftSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.saveDraftImmediately() }
        draftSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.draftSaveDebounceInterval, execute: workItem)
    }

    private func saveDraftImmediately() {
        viewModel.saveDraft(messageTextView.extractSendText())
    }

    private func loadDraft() {
        viewModel.loadDraft { [weak self] draft in
            guard let self = self, let draft = draft, !draft.isEmpty else { return }
            self.isLoadingDraft = true
            let attributed = EmojiManager.shared.createAttributedStringFromEmojiCodes(from: draft)
            self.messageTextView.setContent(attributed)
            self.updateSendButtonVisibility()
            self.focusKeyboardAfterTransition()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.draftLoadingResetDelay) {
                self.isLoadingDraft = false
            }
        }
    }

    func fillText(_ text: String) {
        guard !text.isEmpty else { return }
        let attributed = EmojiManager.shared.createAttributedStringFromEmojiCodes(from: text)
        messageTextView.setContent(attributed)
        updateSendButtonVisibility()
        _ = messageTextView.becomeFirstResponder()
    }

    private func focusKeyboardAfterTransition() {
        let focus = { [weak self] in
            _ = self?.messageTextView.becomeFirstResponder()
        }
        guard let coordinator = findViewController()?.transitionCoordinator else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.draftKeyboardFocusDelay, execute: focus)
            return
        }
        coordinator.animate(alongsideTransition: nil, completion: { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.draftKeyboardFocusDelay, execute: focus)
        })
    }

    func showEmojiPanel() {

        if isVoiceInputMode {
            switchToTextMode()
        }
        attachBuiltInEmojiPickerIfNeeded()
        if didAttachEmojiPicker {
            emojiPickerView.reloadRecentEmojis()
        }

        hideMorePanel(silent: true)

        currentKeyboardHeight = 0
        isEmojiPanelShown = true
        currentEmojiPanelHeight = Self.emojiPanelHeight
        emojiPanelContainer.isHidden = false
        syncBottomAreaHeight()
        endEditing(true)
        emojiButton.setImage(
            AtomicXChatResources.image(named: "input_keyboard")?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        syncPlaceholderSuppression()
        postInputInteract()
        animateLayout()
        reportPanel()
    }

    private func hideEmojiPanel(silent: Bool = false) {
        guard isEmojiPanelShown else { return }
        isEmojiPanelShown = false
        currentEmojiPanelHeight = 0
        emojiPanelContainer.isHidden = true
        emojiButton.setImage(
            AtomicXChatResources.image(named: "input_emoji")?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        syncPlaceholderSuppression()
        if !silent {
            syncBottomAreaHeight()
            animateLayout()
            reportPanel()
        }
    }

    private func attachBuiltInEmojiPickerIfNeeded() {
        guard !didAttachEmojiPicker, emojiPanelContainer.subviews.isEmpty else { return }
        didAttachEmojiPicker = true

        emojiPickerView.bottomSafeAreaInset = bottomSafeAreaInset
        setEmojiPanelContent(emojiPickerView)
    }

    func showMorePanel() {

        if isVoiceInputMode {
            switchToTextMode()
        }
        attachMorePanelIfNeeded()

        hideEmojiPanel(silent: true)

        currentKeyboardHeight = 0
        isMorePanelShown = true
        currentMorePanelHeight = Self.morePanelHeight
        morePanelContainer.isHidden = false
        syncBottomAreaHeight()
        endEditing(true)
        syncPlaceholderSuppression()
        postInputInteract()
        animateLayout()
        reportPanel()
    }

    private func hideMorePanel(silent: Bool = false) {
        guard isMorePanelShown else { return }
        isMorePanelShown = false
        currentMorePanelHeight = 0
        morePanelContainer.isHidden = true
        syncPlaceholderSuppression()
        if !silent {
            syncBottomAreaHeight()
            animateLayout()
            reportPanel()
        }
    }

    private func syncPlaceholderSuppression() {
        messageTextView.suppressPlaceholderForPanel = isEmojiPanelShown || isMorePanelShown
    }

    private func syncBottomAreaHeight() {
        bottomAreaHeightConstraint?.update(offset: currentBottomAreaHeight)
        invalidateIntrinsicContentSize()
    }

    private func attachMorePanelIfNeeded() {
        guard !didAttachMorePanel else { return }
        didAttachMorePanel = true

        morePanel.bottomSafeAreaInset = bottomSafeAreaInset
        morePanelContainer.addSubview(morePanel)
        morePanel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func handleEmojiSelected(_ emoji: EmojiData) {
        let attributed = EmojiManager.shared.createAttributedStringFromEmojiData(emoji)
        messageTextView.insertEmoji(attributed, emojiName: emoji.name ?? "")
    }

    private func handleCustomEmojiSelected(group: EmojiGroup, emoji: EmojiData) {
        guard let groupIndex = EmojiConfig.shared.emojiGroups.firstIndex(where: { $0.id == group.id }),
              let key = emoji.name, !key.isEmpty else { return }
        viewModel.sendFaceMessage(groupIndex: groupIndex, faceData: key, quotedMessage: currentQuotedMessage)
        if currentQuotedMessage != nil {
            clearQuote()
        }
    }

    private func animateLayout() {
        UIView.animate(withDuration: Self.layoutAnimationDuration) {
            self.onAnimateSuperviewLayout?()
            self.layoutIfNeeded()
        }
    }

    private func updateSendButtonVisibility() {
        let hasText = !(messageTextView.extractSendText().isEmpty)
        let showSend = hasText && !isVoiceInputMode
        if showSend {
            moreButton.isHidden = true
            sendButton.isHidden = false
        } else {
            sendButton.isHidden = true
            moreButton.isHidden = !config.isShowMore
        }
        guard usesCollapsibleTrailing else { return }
        if showSend {
            inputTrailingToRowConstraint?.deactivate()
            inputTrailingToSendConstraint?.activate()
        } else {
            inputTrailingToSendConstraint?.deactivate()
            inputTrailingToRowConstraint?.activate()
        }
    }

    private func postInputInteract() {
        NotificationCenter.default.post(name: MessageInputView.inputInteractNotification, object: nil)
    }

    @objc private func handleMessageListBlankAreaClick() {
        hideEmojiPanel()
        hideMorePanel()
    }

    @objc private func handleKeyboardWillShow(_ notification: Notification) {

        hideEmojiPanel(silent: true)
        hideMorePanel(silent: true)
        if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            let screenHeight = UIScreen.main.bounds.height

            currentKeyboardHeight = max(screenHeight - frame.origin.y, 0)
        }
        syncBottomAreaHeight()
        animateLayout()
        postInputInteract()
        reportPanel()
    }

    @objc private func handleKeyboardWillHide(_ notification: Notification) {
        guard !isEmojiPanelShown, !isMorePanelShown else { return }
        currentKeyboardHeight = 0
        syncBottomAreaHeight()
        reportPanel()
    }

    @objc private func handleTextViewDidChange() {
        guard !isLoadingDraft else { return }
        postInputInteract()
    }

    @objc private func handleMoreTapped() {
        if isMorePanelShown {
            hideMorePanel()
        } else {
            showMorePanel()
        }
    }

    @objc private func handleEmojiTapped() {
        if isEmojiPanelShown {
            showKeyboard()
        } else {
            showEmojiPanel()
        }
    }

    @objc private func handleSendTapped() {
        sendText()
    }

    @objc private func handleAudioTapped() {
        if isVoiceInputMode {
            switchToTextMode()
        } else {
            switchToVoiceMode()
        }
    }

    private var audioIconRenderingMode: UIImage.RenderingMode {
        config.appearance?.audioButtonKeepsColors == true ? .alwaysOriginal : .alwaysTemplate
    }

    private func switchToVoiceMode() {
        guard config.isShowAudioRecorder else { return }
        isVoiceInputMode = true
        messageTextView.isHidden = true
        voiceLabel.isHidden = false
        audioButton.setImage(
            (config.appearance?.audioButtonActiveImage ?? AtomicXChatResources.image(named: "input_keyboard"))?
                .withRenderingMode(audioIconRenderingMode),
            for: .normal
        )
        endEditing(true)
        hideEmojiPanel()
        hideMorePanel()
        updateSendButtonVisibility()
        postInputInteract()
    }

    private func switchToTextMode() {
        isVoiceInputMode = false
        messageTextView.isHidden = false
        voiceLabel.isHidden = true
        audioButton.setImage(
            (config.appearance?.audioButtonImage ?? AtomicXChatResources.image(named: "input_audio"))?
                .withRenderingMode(audioIconRenderingMode),
            for: .normal
        )
        updateSendButtonVisibility()
        postInputInteract()
    }

    @objc private func handleAudioLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            hideEmojiPanel()
            hideMorePanel()
            messageTextView.resignFirstResponder()
            isLongPressingAudio = true
            postInputInteract()
            mediaCoordinator.beginVoiceRecording()
        case .changed:
            guard isLongPressingAudio else { return }
            mediaCoordinator.updateVoiceRecording(finger: gesture.location(in: gesture.view?.window))
        case .ended, .cancelled, .failed:
            guard isLongPressingAudio else { return }
            isLongPressingAudio = false
            mediaCoordinator.endVoiceRecording(finger: gesture.location(in: gesture.view?.window))
        default:
            break
        }
    }

    @objc private func handleTextInputLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard canArmVoiceRecordingFromTextInput() else { return }
            hideEmojiPanel()
            hideMorePanel()
            messageTextView.resignFirstResponder()
            isLongPressingAudio = true
            postInputInteract()
            mediaCoordinator.beginVoiceRecording()
        case .changed:
            guard isLongPressingAudio else { return }
            mediaCoordinator.updateVoiceRecording(finger: gesture.location(in: gesture.view?.window))
        case .ended, .cancelled:
            isTextInputLongPressArmed = false
            guard isLongPressingAudio else { return }
            isLongPressingAudio = false
            mediaCoordinator.endVoiceRecording(finger: gesture.location(in: gesture.view?.window))
        default:
            break
        }
    }

    @objc private func handleTextInputTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        isTextInputLongPressArmed = false
        guard !isLongPressingAudio, !isVoiceInputMode else { return }
        messageTextView.becomeFirstResponder()
    }

    private func canArmVoiceRecordingFromTextInput() -> Bool {
        return config.isShowAudioRecorder
            && !isVoiceInputMode
            && !isEmojiPanelShown
            && !isMorePanelShown
            && messageTextView.attributedContent == nil
    }

    @objc private func handleQuoteMessageNotification(_ notification: Notification) {
        guard let message = notification.userInfo?["message"] as? MessageInfo else { return }
        setQuoteMessage(message)
    }

    private func setQuoteMessage(_ message: MessageInfo) {
        if isVoiceInputMode {
            switchToTextMode()
        }
        currentQuotedMessage = message
        let senderName = message.from.nickname ?? message.from.userID
        let summary = MessageInputQuoteSummaryFormatter.format(message: message)
        quotePreviewBar.configure(senderName: senderName, summary: summary)
        showQuoteBar()
        messageTextView.becomeFirstResponder()
        postInputInteract()
    }

    private func clearQuote() {
        currentQuotedMessage = nil
        hideQuoteBar()
    }

    private func showQuoteBar() {
        guard currentQuoteBarHeight == 0 else { return }
        quotePreviewBarHeightConstraint?.update(offset: Self.quotePreviewBarHeight)
        currentQuoteBarHeight = Self.quotePreviewBarHeight
        quotePreviewBar.isHidden = false
        invalidateIntrinsicContentSize()
        animateLayout()
    }

    private func hideQuoteBar() {
        guard currentQuoteBarHeight != 0 else { return }
        quotePreviewBarHeightConstraint?.update(offset: 0)
        currentQuoteBarHeight = 0
        quotePreviewBar.isHidden = true
        invalidateIntrinsicContentSize()
        animateLayout()
    }
}

// MARK: - MessageInputMorePanelDelegate

extension MessageInputViewImpl: MessageInputMorePanelDelegate {
    private static let c2cConversationPrefix = "c2c_"

    func morePanelDidSelectAlbum() {
        hideMorePanel()
        AlbumPickerMediaSendCoordinator.shared.showAlbumPicker(conversationID: viewModel.conversationID)
    }

    func morePanelDidSelectCamera() {
        hideMorePanel()
        mediaCoordinator.showCamera(recordMode: .photoOnly)
    }

    func morePanelDidSelectVideo() {
        hideMorePanel()
        mediaCoordinator.showCamera(recordMode: .videoPhotoMix)
    }

    func morePanelDidSelectFile() {
        hideMorePanel()
        mediaCoordinator.showFilePicker()
    }

    func morePanelDidSelectVideoCall() {
        hideMorePanel()
        startCall(mediaType: .video)
    }

    func morePanelDidSelectAudioCall() {
        hideMorePanel()
        startCall(mediaType: .audio)
    }

    private func startCall(mediaType: ChatCallEventPublisher.MediaType) {
        if !viewModel.isGroupChat, let targetUserID = c2cTargetUserID() {
            DataReport.reportInteractionMetrics(.chatInvokeCall)
            ChatCallEventPublisher.publishStartCall(participantIDs: [targetUserID], mediaType: mediaType)
            return
        }
        presentGroupCallMemberPicker(mediaType: mediaType)
    }

    private func c2cTargetUserID() -> String? {
        let conversationID = viewModel.conversationID
        guard conversationID.hasPrefix(Self.c2cConversationPrefix) else { return nil }
        let target = String(conversationID.dropFirst(Self.c2cConversationPrefix.count))
        return target.isEmpty ? nil : target
    }

    private func presentGroupCallMemberPicker(mediaType: ChatCallEventPublisher.MediaType) {
        let groupID = viewModel.groupID
        guard !groupID.isEmpty, let presenter = findViewController() else { return }
        let title = mediaType == .video ? LocalizedChatString("MoreVideoCall") : LocalizedChatString("MoreVoiceCall")
        let picker = GroupCallMemberPickerViewController(groupID: groupID, title: title) { userIDs in
            DataReport.reportInteractionMetrics(.chatInvokeCall)
            ChatCallEventPublisher.publishStartCall(participantIDs: userIDs, mediaType: mediaType, chatGroupID: groupID)
        }
        let navigationController = UINavigationController(rootViewController: picker)
        navigationController.isNavigationBarHidden = true
        navigationController.modalPresentationStyle = .fullScreen
        presenter.present(navigationController, animated: true)
    }
}

extension MessageInputViewImpl: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer == textInputLongPress || gestureRecognizer == textInputTap
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer == textInputLongPress, canArmVoiceRecordingFromTextInput() {
            isTextInputLongPressArmed = true
        }
        return true
    }
}

/// The 发送 pill. It sizes its own brand gradient because the pill is laid out inside the input row, after the
/// input view's own layout pass, so a parent-driven frame would still be 0x0 the first time it is shown.
final class SendPillButton: UIButton {
    private let fillGradientLayer = CAGradientLayer()

    func applyGradient(_ colors: [CGColor]) {
        backgroundColor = .clear
        fillGradientLayer.colors = colors
        fillGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fillGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.insertSublayer(fillGradientLayer, at: 0)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard fillGradientLayer.superlayer != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillGradientLayer.frame = bounds
        fillGradientLayer.cornerRadius = bounds.height / 2
        layer.cornerRadius = bounds.height / 2
        CATransaction.commit()
    }
}
