import AtomicXCore
import Combine
import SnapKit
import UIKit
import AtomicX

/// Host supplied extras of the 1:1 chat settings scene (S6). Everything here is business content the
/// IM SDK does not own: every row built from it is and never submits a business request.
/// Passing extras switches the page to the scene look (profile box, rounded cards, footer) and order.
public struct C2CSceneExtras {
    public static let rowIntimacy = "intimacy"
    public static let rowNickname = "nickname"
    public static let rowReport = "report"

    public let profileTags: [String]
    /// Host-built badge shown under the user id (replaces `profileTags` when set), e.g. the 实名 tag.
    public let profileTagView: (() -> UIView)?
    public let intimacyLabel: String
    public let intimacyBadge: String?
    public let backgroundLabel: String
    public let nicknameLabel: String
    public let nicknameValue: String?
    public let reportLabel: String
    public let footer: String?
    public let onMockRowClick: (String) -> Void
    /// When set, a host row「加好友」is rendered above the blacklist row; the host passes nil for friends.
    public let addFriendLabel: String?
    public let onAddFriendClick: () -> Void
    /// When set, a danger row「删除好友」is rendered at the bottom (after 清空聊天记录); friends only.
    public let deleteFriendLabel: String?

    public init(profileTags: [String] = [],
                profileTagView: (() -> UIView)? = nil,
                intimacyLabel: String,
                intimacyBadge: String? = nil,
                backgroundLabel: String,
                nicknameLabel: String,
                nicknameValue: String? = nil,
                reportLabel: String,
                footer: String? = nil,
                onMockRowClick: @escaping (String) -> Void = { _ in },
                addFriendLabel: String? = nil,
                onAddFriendClick: @escaping () -> Void = {},
                deleteFriendLabel: String? = nil) {
        self.profileTags = profileTags
        self.profileTagView = profileTagView
        self.intimacyLabel = intimacyLabel
        self.intimacyBadge = intimacyBadge
        self.backgroundLabel = backgroundLabel
        self.nicknameLabel = nicknameLabel
        self.nicknameValue = nicknameValue
        self.reportLabel = reportLabel
        self.footer = footer
        self.onMockRowClick = onMockRowClick
        self.addFriendLabel = addFriendLabel
        self.onAddFriendClick = onAddFriendClick
        self.deleteFriendLabel = deleteFriendLabel
    }
}

public final class C2CChatSettingViewController: ChatSettingBaseViewController {
    private static let headerAvatarSize = ChatAvatarSize.l

    private static let headerSpacing: CGFloat = CGFloat(SpacingScheme.bubbleSpacing)

    private static let headerHorizontalPadding: CGFloat = CGFloat(SpacingScheme.bubbleSpacing)

    private static let headerVerticalPadding: CGFloat = CGFloat(SpacingScheme.iconIconSpacing)

    private static let headerSubFontSize: CGFloat = 13

    private static let headerIDTopSpacing: CGFloat = CGFloat(SpacingScheme.iconTextSpacing)

    private static let headerSignatureTopSpacing: CGFloat = 2

    private static let toastDuration: TimeInterval = 2

    private let userID: String

    private let contactStore: ContactStore

    private let conversationStore: ConversationListStore

    private let onSendMessageClick: (() -> Void)?

    private let onContactDelete: (() -> Void)?

    private let config: C2CChatSettingConfigProtocol

    private let sceneExtras: C2CSceneExtras?

    private let tagsStack = UIStackView()

    private let footerLabel = UILabel()

    private var intimacyRow: ChatSettingRowView?

    private var nicknameRow: ChatSettingRowView?

    private var reportRow: ChatSettingRowView?

    private var clearRow: ChatSettingRowView?

    private var remark: String = ""

    private var nick: String = ""

    private var avatar: String = ""

    private var aboutMe: String = ""

    private var isNotDisturb: Bool = false

    private var isPinned: Bool = false

    private var isInBlacklist: Bool = false

    private var chatBackgroundURI: String?

    private var chatBackgroundPresetName: String? {
        guard let uri = chatBackgroundURI else { return nil }
        return ChatBackgroundPresetProvider.presetItems()
            .first { $0.imageURI == uri }?
            .nameKey.map { LocalizedChatString($0) }
    }

    private var cancellables = Set<AnyCancellable>()

    private let scrollView = UIScrollView()

    private let stackView = UIStackView()

    private let headerView = UIView()

    private let avatarView = ChatAvatarView(size: .l, isRound: false)

    private let nameLabel = UILabel()

    private let userIDLabel = UILabel()

    private let signatureLabel = UILabel()

    private let headerTextStack = UIStackView()

    private lazy var remarkRow = ChatSettingRowView(title: LocalizedChatString("ProfileAlia"), accessory: .arrow)

    private lazy var doNotDisturbRow = ChatSettingToggleRowView(title: LocalizedChatString("ProfileMessageDoNotDisturb"))

    private lazy var pinRow = ChatSettingToggleRowView(title: LocalizedChatString("ProfileStickyonTop"))

    private lazy var backgroundRow = ChatSettingRowView(title: LocalizedChatString("ChatBackgroundSetting"), accessory: .arrow)

    private lazy var blacklistRow = ChatSettingToggleRowView(title: LocalizedChatString("ProfileBlocked"))

    private var conversationID: String {
        return ChatUtil.getC2CConversationID(userID)
    }

    private var displayName: String {
        return nick.isEmpty ? userID : nick
    }

    public init(
        userID: String,
        config: C2CChatSettingConfigProtocol = C2CChatSettingConfig(),
        onSendMessageClick: (() -> Void)? = nil,
        onContactDelete: (() -> Void)? = nil,
        sceneExtras: C2CSceneExtras? = nil
    ) {
        self.sceneExtras = sceneExtras
        self.userID = userID
        self.contactStore = ContactStore.shared
        self.conversationStore = ConversationListStore.create()
        self.config = config
        self.onSendMessageClick = onSendMessageClick
        self.onContactDelete = onContactDelete
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setNavTitle(LocalizedChatString("ProfileContactInfo"))
        if sceneExtras != nil {
            // S6 title comes from the host copy via `title` once set; fall back to the SDK string.
            if let title = title, !title.isEmpty { setNavTitle(title) }
        }
        constructViewHierarchy()
        applyCustomItems()
        activateConstraints()
        setupViewStyle()
        bindInteraction()
        subscribeStores()
        fetchInitialInfo()
        chatBackgroundURI = ChatBackgroundStore.shared.imageURI(forConversationID: conversationID)
        refreshUI()
    }

    // MARK: - Actions

    private func constructViewHierarchy() {
        if let scene = sceneExtras {
            constructSceneHierarchy(scene)
            return
        }
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        headerView.addSubview(avatarView)
        headerTextStack.addArrangedSubview(nameLabel)
        headerTextStack.addArrangedSubview(userIDLabel)
        headerTextStack.addArrangedSubview(signatureLabel)
        headerView.addSubview(headerTextStack)

        var sections: [(UIView, Bool)] = [
            (headerView, config.isShowHeader),
            (remarkRow, config.isShowRemark),
        ]
        if let switchSection = makeSwitchSection() {
            sections.append((switchSection, true))
        }
        sections.append((backgroundRow, config.isShowChatBackground))
        sections.append((blacklistRow, config.isShowBlacklist))
        if let actionSection = makeActionSection() {
            sections.append((actionSection, true))
        }

        var isFirstVisible = true
        for (sectionView, isVisible) in sections where isVisible {
            if !isFirstVisible {
                stackView.addArrangedSubview(makeChatSettingSectionSpacer())
            }
            stackView.addArrangedSubview(sectionView)
            isFirstVisible = false
        }
    }

    // MARK: - Scene layout (S6)

    private func constructSceneHierarchy(_ scene: C2CSceneExtras) {
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        // Profile box: centred 72 avatar, name, uid, host tags (prototype `.profilebox`).
        let box = UIStackView()
        box.axis = .vertical
        box.alignment = .center
        box.spacing = ChatSettingSceneSpec.profileGap
        box.addArrangedSubview(avatarView)
        box.addArrangedSubview(nameLabel)
        box.addArrangedSubview(userIDLabel)
        tagsStack.axis = .horizontal
        tagsStack.spacing = ChatSettingSceneSpec.profileGap
        for text in scene.profileTagView == nil ? scene.profileTags : [] {
            let tag = ChatSettingCapsuleLabel()
            tag.text = text
            tag.font = UIFont.adaptiveSystemFont(ofSize: 11)
            tag.insets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
            tag.textColor = TUIChatKitTheme.colors.tagColorLevel3
            tag.backgroundColor = TUIChatKitTheme.colors.tagColorLevel3.withAlphaComponent(0.18)
            tagsStack.addArrangedSubview(tag)
        }
        if let makeTag = scene.profileTagView {
            tagsStack.addArrangedSubview(makeTag())
            box.addArrangedSubview(tagsStack)
        } else if !scene.profileTags.isEmpty {
            box.addArrangedSubview(tagsStack)
        }
        headerView.addSubview(box)
        avatarView.snp.makeConstraints { make in
            make.width.height.equalTo(ChatSettingSceneSpec.profileAvatar)
        }
        box.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(ChatSettingSceneSpec.profileTop)
            make.bottom.equalToSuperview().offset(-ChatSettingSceneSpec.profileBottom)
            make.leading.greaterThanOrEqualToSuperview().offset(ChatSettingSceneSpec.pagePadding)
            make.trailing.lessThanOrEqualToSuperview().offset(-ChatSettingSceneSpec.pagePadding)
            make.centerX.equalToSuperview()
        }
        stackView.addArrangedSubview(headerView)

        // rows: intimacy / nickname / report only call back to the host.
        func mockRow(_ id: String, _ title: String, badge: String? = nil, value: String = "") -> ChatSettingRowView {
            let row = ChatSettingRowView(title: title, value: value, accessory: .arrow)
            row.setBadge(badge)
            row.addAction(UIAction { _ in scene.onMockRowClick(id) }, for: .touchUpInside)
            return row
        }
        let intimacy = mockRow(C2CSceneExtras.rowIntimacy, scene.intimacyLabel, badge: scene.intimacyBadge)
        let nickname = mockRow(C2CSceneExtras.rowNickname, scene.nicknameLabel, value: scene.nicknameValue ?? "")
        let report = mockRow(C2CSceneExtras.rowReport, scene.reportLabel)
        report.setDanger(true)
        let clear = ChatSettingRowView(title: LocalizedChatString("ClearAllChatHistory"), accessory: .arrow)
        clear.setDanger(true)
        clear.addTarget(self, action: #selector(handleClearHistoryTapped), for: .touchUpInside)
        intimacyRow = intimacy
        nicknameRow = nickname
        reportRow = report
        clearRow = clear

        var safetyRows: [UIView] = [blacklistRow]
        if let label = scene.addFriendLabel, !label.isEmpty {
            let addFriend = ChatSettingRowView(title: label, accessory: .arrow)
            addFriend.addAction(UIAction { _ in scene.onAddFriendClick() }, for: .touchUpInside)
            safetyRows.insert(addFriend, at: 0)
        }
        safetyRows.append(contentsOf: [report, clear])
        if let label = scene.deleteFriendLabel, !label.isEmpty {
            let deleteFriend = ChatSettingRowView(title: label, accessory: .arrow)
            deleteFriend.setDanger(true)
            deleteFriend.addTarget(self, action: #selector(handleDeleteFriendTapped), for: .touchUpInside)
            safetyRows.append(deleteFriend)
        }

        stackView.addArrangedSubview(makeSceneCard([doNotDisturbRow, pinRow]))
        stackView.addArrangedSubview(makeSceneCard([intimacy, backgroundRow, nickname]))
        stackView.addArrangedSubview(makeSceneCard(safetyRows))

        if let footer = scene.footer, !footer.isEmpty {
            footerLabel.text = footer
            footerLabel.numberOfLines = 0
            let holder = UIView()
            holder.addSubview(footerLabel)
            footerLabel.snp.makeConstraints { make in
                make.top.equalToSuperview().offset(8)
                make.bottom.equalToSuperview().offset(-24)
                make.leading.trailing.equalToSuperview().inset(ChatSettingSceneSpec.pagePadding)
            }
            stackView.addArrangedSubview(holder)
        }
    }

    /// Rounded card (prototype `.setcard`) inset 16 with a 6 gap below (`.setgroup`).
    private func makeSceneCard(_ rows: [UIView]) -> UIView {
        let colors = TUIChatKitTheme.colors
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 0
        card.backgroundColor = colors.bgColorOperate
        card.layer.cornerRadius = ChatSettingSceneSpec.cardRadius
        card.layer.masksToBounds = true
        for (index, row) in rows.enumerated() {
            if index > 0 { card.addArrangedSubview(makeSceneDivider()) }
            card.addArrangedSubview(row)
        }
        let holder = UIView()
        holder.addSubview(card)
        card.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(ChatSettingSceneSpec.groupGap)
            make.leading.trailing.equalToSuperview().inset(ChatSettingSceneSpec.pagePadding)
            make.bottom.equalToSuperview()
        }
        return holder
    }

    private func makeSceneDivider() -> UIView {
        let wrapper = UIView()
        let line = UIView()
        line.backgroundColor = TUIChatKitTheme.colors.strokeColorSecondary
        wrapper.addSubview(line)
        line.snp.makeConstraints { make in
            make.top.bottom.trailing.equalToSuperview()
            make.leading.equalToSuperview().offset(ChatSettingSceneSpec.dividerInset)
            make.height.equalTo(1)
        }
        return wrapper
    }

    private func makeSwitchSection() -> UIStackView? {
        var rows: [UIView] = []
        if config.isShowDoNotDisturb {
            rows.append(doNotDisturbRow)
        }
        if config.isShowPin {
            rows.append(pinRow)
        }
        guard !rows.isEmpty else { return nil }
        var arranged: [UIView] = []
        for (index, row) in rows.enumerated() {
            if index > 0 {
                arranged.append(makeChatSettingRowDivider())
            }
            arranged.append(row)
        }
        return makeSectionContainer(arrangedSubviews: arranged)
    }

    private func makeSectionContainer(arrangedSubviews: [UIView]) -> UIStackView {
        let section = UIStackView(arrangedSubviews: arrangedSubviews)
        section.axis = .vertical
        section.spacing = 0
        section.backgroundColor = TUIChatKitTheme.colors.bgColorOperate
        return section
    }

    private func makeActionRow(titleKey: String, textColor: UIColor, action: Selector) -> ChatSettingActionRowView {
        let row = ChatSettingActionRowView(title: LocalizedChatString(titleKey), textColor: textColor)
        row.addTarget(self, action: action, for: .touchUpInside)
        return row
    }

    private func makeActionSection() -> UIStackView? {
        let colors = TUIChatKitTheme.colors
        var rows: [UIView] = []
        if config.isShowSendMessage {
            rows.append(makeActionRow(titleKey: "ProfileSendMessages", textColor: colors.textColorLink, action: #selector(handleSendMessageTapped)))
        }
        if config.isShowVoiceCall {
            rows.append(makeActionRow(titleKey: "MoreVoiceCall", textColor: colors.textColorLink, action: #selector(handleVoiceCallTapped)))
        }
        if config.isShowVideoCall {
            rows.append(makeActionRow(titleKey: "MoreVideoCall", textColor: colors.textColorLink, action: #selector(handleVideoCallTapped)))
        }
        if config.isShowClearHistory {
            rows.append(makeActionRow(titleKey: "ClearAllChatHistory", textColor: colors.textColorError, action: #selector(handleClearHistoryTapped)))
        }
        if config.isShowDeleteFriend {
            rows.append(makeActionRow(titleKey: "ProfileDeleteFirend", textColor: colors.textColorError, action: #selector(handleDeleteFriendTapped)))
        }
        guard !rows.isEmpty else { return nil }
        var arranged: [UIView] = []
        for (index, row) in rows.enumerated() {
            if index > 0 {
                arranged.append(makeChatSettingRowDivider())
            }
            arranged.append(row)
        }
        return makeSectionContainer(arrangedSubviews: arranged)
    }

    private func applyCustomItems() {
        guard sceneExtras == nil, let customizer = config.itemCustomizer else { return }
        let editor = ChatSettingItemEditor<C2CChatSettingSection>()
        customizer(editor)
        var lastInsertedByAnchor: [UIView] = []
        for (section, row) in editor.customRows {
            guard let anchor = anchorView(for: section) else {
                stackView.addArrangedSubview(row)
                continue
            }
            let base = lastInsertedByAnchor.first(where: { $0 === anchor }) ?? anchor
            if let index = stackView.arrangedSubviews.firstIndex(of: base) {
                stackView.insertArrangedSubview(row, at: index + 1)
            } else {
                stackView.addArrangedSubview(row)
            }
            lastInsertedByAnchor.removeAll { $0 === anchor }
            lastInsertedByAnchor.append(row)
        }
    }

    private func anchorView(for section: C2CChatSettingSection) -> UIView? {
        switch section {
        case .header: return config.isShowHeader ? headerView : nil
        case .remark: return config.isShowRemark ? remarkRow : nil
        case .switches: return stackView.arrangedSubviews.first { $0 is UIStackView && ($0 as? UIStackView)?.arrangedSubviews.contains(where: { $0 === doNotDisturbRow || $0 === pinRow }) == true }
        case .background: return config.isShowChatBackground ? backgroundRow : nil
        case .blacklist: return config.isShowBlacklist ? blacklistRow : nil
        case .actions: return stackView.arrangedSubviews.last
        case .end: return nil
        }
    }

    private func activateConstraints() {
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(contentTopItem)
            make.leading.trailing.bottom.equalToSuperview()
        }
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalToSuperview()
        }
        if sceneExtras != nil { return }
        avatarView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.headerHorizontalPadding)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.headerAvatarSize.size)
        }
        headerTextStack.snp.makeConstraints { make in
            make.leading.equalTo(avatarView.snp.trailing).offset(Self.headerSpacing)
            make.trailing.lessThanOrEqualToSuperview().offset(-Self.headerHorizontalPadding)
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().offset(Self.headerVerticalPadding)
            make.bottom.lessThanOrEqualToSuperview().offset(-Self.headerVerticalPadding)
        }
    }

    private func setupViewStyle() {
        let colors = TUIChatKitTheme.colors
        view.backgroundColor = colors.bgColorTopBar
        scrollView.backgroundColor = colors.bgColorTopBar
        stackView.axis = .vertical
        stackView.spacing = 0
        headerView.backgroundColor = colors.bgColorTopBar
        footerLabel.font = UIFont.adaptiveSystemFont(ofSize: ChatSettingSceneSpec.footerFontSize)
        footerLabel.textColor = colors.textColorTertiary
        if sceneExtras != nil {
            nameLabel.font = UIFont.adaptiveSystemFont(ofSize: ChatSettingSceneSpec.profileNameFontSize, weight: .bold)
            userIDLabel.font = UIFont.adaptiveSystemFont(ofSize: ChatSettingSceneSpec.profileUIDFontSize)
            userIDLabel.textColor = colors.textColorSecondary
        }
        headerTextStack.axis = .vertical
        headerTextStack.spacing = 0
        if sceneExtras == nil {
            nameLabel.font = FontScheme.body4Regular
            userIDLabel.font = .adaptiveSystemFont(ofSize: Self.headerSubFontSize)
            userIDLabel.textColor = colors.textColorTertiary
        }
        nameLabel.textColor = colors.textColorPrimary
        nameLabel.lineBreakMode = .byTruncatingTail
        userIDLabel.lineBreakMode = .byTruncatingTail
        signatureLabel.font = .adaptiveSystemFont(ofSize: Self.headerSubFontSize)
        signatureLabel.textColor = colors.textColorTertiary
        signatureLabel.lineBreakMode = .byTruncatingTail
        headerTextStack.setCustomSpacing(Self.headerIDTopSpacing, after: nameLabel)
        headerTextStack.setCustomSpacing(Self.headerSignatureTopSpacing, after: userIDLabel)
    }

    private func bindInteraction() {
        remarkRow.addTarget(self, action: #selector(handleRemarkTapped), for: .touchUpInside)
        backgroundRow.addTarget(self, action: #selector(handleBackgroundTapped), for: .touchUpInside)
        doNotDisturbRow.onToggle = { [weak self] value in self?.setDoNotDisturb(value) }
        pinRow.onToggle = { [weak self] value in self?.setPinned(value) }
        blacklistRow.onToggle = { [weak self] value in self?.setBlacklist(value) }
    }

    private func subscribeStores() {
        contactStore.state
            .subscribe(StatePublisherSelector(keyPath: \ContactState.friendList))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] friendList in
                guard let self = self else { return }
                if let contactInfo = friendList.first(where: { $0.userID == self.userID }) {
                    self.applyContactInfo(contactInfo)
                }
            }
            .store(in: &cancellables)
        contactStore.state
            .subscribe(StatePublisherSelector(keyPath: \ContactState.blackList))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] blackList in
                guard let self = self else { return }
                self.isInBlacklist = blackList.contains(where: { $0.userID == self.userID })
                self.blacklistRow.setOn(self.isInBlacklist)
            }
            .store(in: &cancellables)
        conversationStore.state
            .subscribe(StatePublisherSelector(keyPath: \ConversationListState.conversationList))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversationList in
                guard let self = self else { return }
                if let conversationInfo = conversationList.first(where: { $0.conversationID == self.conversationID }) {
                    self.applyConversationInfo(conversationInfo)
                }
            }
            .store(in: &cancellables)
    }

    private func fetchInitialInfo() {
        contactStore.loadFriends(completion: nil)
        contactStore.loadBlackList(completion: nil)
        contactStore.getContactInfo(
            userIDList: [userID],
            completion: C2CSettingContactInfoHandler(
                onSuccess: { [weak self] contactInfoList in
                    DispatchQueue.main.async {
                        if let contactInfo = contactInfoList.first {
                            self?.applyContactInfo(contactInfo)
                        }
                    }
                },
                onFailure: { _, _ in }
            )
        )
        conversationStore.getConversationInfo(
            conversationID: conversationID,
            completion: C2CSettingConversationInfoHandler(
                onSuccess: { [weak self] conversationInfo in
                    DispatchQueue.main.async {
                        self?.applyConversationInfo(conversationInfo)
                    }
                },
                onFailure: { _, _ in }
            )
        )
    }

    private func applyContactInfo(_ contactInfo: ContactInfo) {
        if let friendRemark = contactInfo.friendRemark {
            remark = friendRemark
        }
        if let nickname = contactInfo.nickname {
            nick = nickname
        }
        if let avatarURL = contactInfo.avatarURL {
            avatar = avatarURL
        }
        if let signature = contactInfo.aboutMe {
            aboutMe = signature
        }
        refreshUI()
    }

    private func applyConversationInfo(_ conversationInfo: ConversationInfo) {
        isNotDisturb = conversationInfo.receiveOption != .receive
        isPinned = conversationInfo.isPinned
        refreshUI()
    }

    private func refreshUI() {
        avatarView.configure(avatarURL: avatar, fallbackName: displayName)
        nameLabel.text = displayName
        userIDLabel.text = "\(LocalizedChatString("ProfileUserID")): \(userID)"
        signatureLabel.text = aboutMe.isEmpty ? nil : LocalizedChatString("ProfileSignaturePrefix") + aboutMe
        signatureLabel.isHidden = aboutMe.isEmpty
        remarkRow.update(value: remark.isEmpty ? displayName : remark, accessory: .arrow)
        doNotDisturbRow.setOn(isNotDisturb)
        pinRow.setOn(isPinned)
        blacklistRow.setOn(isInBlacklist)
        if let scene = sceneExtras {
            backgroundRow.setTitle(scene.backgroundLabel)
            backgroundRow.update(value: chatBackgroundPresetName ?? "", accessory: .arrow)
        } else {
            backgroundRow.update(
                value: chatBackgroundURI == nil
                    ? LocalizedChatString("ChatBackgroundDefault")
                    : (chatBackgroundPresetName ?? LocalizedChatString("ChatBackgroundCustom")),
                accessory: .arrow
            )
        }
    }

    @objc private func handleRemarkTapped() {
        let dialog = TextInputDialogViewController(
            title: LocalizedChatString("ProfileEditAlia"),
            initialText: remark
        ) { [weak self] text in
            self?.saveRemark(text)
        }
        present(dialog, animated: true)
    }

    @objc private func handleBackgroundTapped() {
        let picker = ChatBackgroundPickerViewController(conversationID: conversationID) { [weak self] uri in
            guard let self = self else { return }
            ChatBackgroundStore.shared.setImageURI(uri, forConversationID: self.conversationID)
            self.chatBackgroundURI = uri
            self.refreshUI()
        }
        present(picker, animated: true)
    }

    @objc private func handleSendMessageTapped() {
        onSendMessageClick?()
    }

    @objc private func handleVoiceCallTapped() {
        startCall(mediaType: .audio)
    }

    @objc private func handleVideoCallTapped() {
        startCall(mediaType: .video)
    }

    @objc private func handleClearHistoryTapped() {
        let alert = UIAlertController(
            title: LocalizedChatString("ClearContactHistoryTips"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: LocalizedChatString("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: LocalizedChatString("Confirm"), style: .destructive) { [weak self] _ in
            self?.clearHistory()
        })
        present(alert, animated: true)
    }

    @objc private func handleDeleteFriendTapped() {
        let alert = UIAlertController(
            title: LocalizedChatString("DeleteFriendConfirmTips"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: LocalizedChatString("AlertConfirm"), style: .destructive) { [weak self] _ in
            self?.deleteFriend()
        })
        alert.addAction(UIAlertAction(title: LocalizedChatString("Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func startCall(mediaType: ChatCallEventPublisher.MediaType) {
        DataReport.reportInteractionMetrics(.chatInvokeCall)
        ChatCallEventPublisher.publishStartCall(participantIDs: [userID], mediaType: mediaType)
    }

    private func setDoNotDisturb(_ value: Bool) {
        let opt: ReceiveMessageOption = value ? .notNotify : .receive
        conversationStore.setReceiveMessageOpt(conversationID: conversationID, opt: opt, completion: nil)
    }

    private func setPinned(_ value: Bool) {
        conversationStore.pinConversation(conversationID: conversationID, pin: value, completion: nil)
    }

    private func setBlacklist(_ value: Bool) {
        if value {
            contactStore.addToBlacklist(userID: userID) { [weak self] result in
                if case .success = result {
                    self?.contactStore.loadBlackList(completion: nil)
                }
            }
        } else {
            contactStore.removeFromBlacklist(userID: userID) { [weak self] result in
                if case .success = result {
                    self?.contactStore.loadBlackList(completion: nil)
                }
            }
        }
    }

    private func saveRemark(_ text: String) {
        contactStore.setFriendRemark(userID: userID, remark: text, completion: nil)
    }

    private func deleteFriend() {
        contactStore.deleteFriend(userID: userID) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if case .success = result {
                    self.conversationStore.deleteConversation(conversationID: self.conversationID, completion: nil)
                }
                if let onContactDelete = self.onContactDelete {
                    onContactDelete()
                } else if let navigationController = self.navigationController {
                    navigationController.popViewController(animated: true)
                } else {
                    self.dismiss(animated: true)
                }
            }
        }
    }

    private func clearHistory() {
        // 清空聊天记录不会动未读，被标为未读的会话要一并清掉未读数和标记。
        ConversationUnreadClearer.clearMessages(store: conversationStore, conversationID: conversationID) { result in
            if case .success = result {
                DispatchQueue.main.async {
                    WindowToastManager.shared.show(LocalizedChatString("ClearAllChatHistory"), type: .success, duration: Self.toastDuration)
                }
            }
        }
    }
}

private final class C2CSettingContactInfoHandler: GetContactInfoCompletionHandler {
    private let onSuccessBlock: ([ContactInfo]) -> Void

    private let onFailureBlock: (Int, String) -> Void

    init(onSuccess: @escaping ([ContactInfo]) -> Void, onFailure: @escaping (Int, String) -> Void) {
        self.onSuccessBlock = onSuccess
        self.onFailureBlock = onFailure
    }

    func onSuccess(contactInfoList: [ContactInfo]) {
        onSuccessBlock(contactInfoList)
    }

    func onFailure(code: Int, desc: String) {
        onFailureBlock(code, desc)
    }
}

private final class C2CSettingConversationInfoHandler: GetConversationInfoCompletionHandler {
    private let onSuccessBlock: (ConversationInfo) -> Void

    private let onFailureBlock: (Int, String) -> Void

    init(onSuccess: @escaping (ConversationInfo) -> Void, onFailure: @escaping (Int, String) -> Void) {
        self.onSuccessBlock = onSuccess
        self.onFailureBlock = onFailure
    }

    func onSuccess(conversationInfo: ConversationInfo) {
        onSuccessBlock(conversationInfo)
    }

    func onFailure(code: Int, desc: String) {
        onFailureBlock(code, desc)
    }
}
