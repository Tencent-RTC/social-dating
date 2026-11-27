import AtomicXCore
import Combine
import SnapKit
import UIKit
import AtomicX

public struct NavigationInfo {
    public let conversation: ConversationInfo
    public let locateMessage: MessageInfo?

    public init(conversation: ConversationInfo, locateMessage: MessageInfo? = nil) {
        self.conversation = conversation
        self.locateMessage = locateMessage
    }
}

public final class ConversationsPage: UIViewController {
    private static let headerVerticalPadding: CGFloat = CGFloat(SpacingScheme.iconIconSpacing)

    private static let horizontalPadding: CGFloat = CGFloat(SpacingScheme.bubbleSpacing)

    private static let addButtonSize: CGFloat = 24

    private static let searchBarHeight: CGFloat = 36

    private static let searchBarVerticalPadding: CGFloat = CGFloat(SpacingScheme.smallSpacing)

    private static let titleFontSize: CGFloat = 17

    private let onConversationClick: ((NavigationInfo) -> Void)?

    private let config: ConversationActionConfigProtocol

    private let conversationGroup: String?

    private let exclusion: ((ConversationInfo) -> Bool)?

    private let emptyText: String?

    /// False when a host screen already draws the page header (the messages tab shell).
    private let showsHeader: Bool

    private let searchPlaceholder: String?

    private let showsSearchBar: Bool

    private let listHeaderView: UIView?

    private let headerView = UIView()

    private let titleLabel = UILabel()

    private let addButton = UIButton(type: .system)

    private lazy var searchEntryBar = SearchEntryBarView(onTapItem: { [weak self] result in
        self?.handleSearchResult(result)
    })

    private lazy var conversationListView = ConversationListView(
        onConversationClick: { [weak self] conversation in
            self?.onConversationClick?(NavigationInfo(conversation: conversation))
        },
        config: config,
        conversationGroup: conversationGroup,
        exclusion: exclusion,
        emptyText: emptyText,
        markType: markType,
        exclusionChanges: exclusionChanges,
        titleAccessory: titleAccessory
    )

    private let markType: ConversationMarkType?

    private let exclusionChanges: AnyPublisher<Void, Never>?

    private let titleAccessory: ((ConversationInfo) -> UIView?)?

    // MARK: - Init

    public init(
        config: ConversationActionConfigProtocol = ChatConversationActionConfig(),
        conversationGroup: String? = nil,
        exclusion: ((ConversationInfo) -> Bool)? = nil,
        emptyText: String? = nil,
        showsHeader: Bool = true,
        searchPlaceholder: String? = nil,
        showsSearchBar: Bool = true,
        listHeaderView: UIView? = nil,
        markType: ConversationMarkType? = nil,
        exclusionChanges: AnyPublisher<Void, Never>? = nil,
        titleAccessory: ((ConversationInfo) -> UIView?)? = nil,
        onConversationClick: ((NavigationInfo) -> Void)? = nil
    ) {
        self.showsHeader = showsHeader
        self.searchPlaceholder = searchPlaceholder
        self.showsSearchBar = showsSearchBar
        self.listHeaderView = listHeaderView
        self.config = config
        self.conversationGroup = conversationGroup
        self.exclusion = exclusion
        self.emptyText = emptyText
        self.markType = markType
        self.exclusionChanges = exclusionChanges
        self.titleAccessory = titleAccessory
        self.onConversationClick = onConversationClick
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        TUIChatKitLayoutDirection.install()
        constructViewHierarchy()
        activateConstraints()
        bindInteraction()
        setupViewStyle()
        ContactStore.shared.loadFriends(completion: nil)
    }

    // MARK: - Search Result Handling

    private func constructViewHierarchy() {
        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(addButton)
        view.addSubview(conversationListView)
    }

    private func activateConstraints() {
        if showsHeader {
            headerView.snp.makeConstraints { make in
                make.top.equalTo(view.safeAreaLayoutGuide)
                make.leading.trailing.equalToSuperview()
            }
        } else {
            headerView.isHidden = true
        }
        if showsHeader {
            titleLabel.snp.makeConstraints { make in
                make.centerX.equalToSuperview()
                make.leading.greaterThanOrEqualToSuperview().offset(Self.horizontalPadding + Self.addButtonSize)
                make.trailing.lessThanOrEqualTo(addButton.snp.leading).offset(-Self.horizontalPadding)
                make.top.equalToSuperview().offset(Self.headerVerticalPadding)
                make.bottom.equalToSuperview().offset(-Self.headerVerticalPadding)
            }
            addButton.snp.makeConstraints { make in
                make.trailing.equalToSuperview().offset(-Self.horizontalPadding)
                make.centerY.equalTo(titleLabel)
                make.width.height.equalTo(Self.addButtonSize)
            }
        }
        conversationListView.snp.makeConstraints { make in
            if showsHeader {
                make.top.equalTo(headerView.snp.bottom)
            } else {
                make.top.equalToSuperview()
            }
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    /// Search bar and the host's entry rows are the list's header, so they scroll away with the rows and come back at the
    /// top (spec 02 S1: 入口 / 搜索 / 分组随滚，页头 / Tab 固定).
    private func makeListHeader() -> UIView? {
        guard showsSearchBar else { return listHeaderView }
        let searchWrap = UIView()
        searchWrap.addSubview(searchEntryBar)
        searchEntryBar.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Self.searchBarVerticalPadding)
            make.bottom.equalToSuperview().offset(-Self.searchBarVerticalPadding)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(Self.searchBarHeight)
        }
        var parts: [UIView] = [searchWrap]
        if let listHeaderView { parts.append(listHeaderView) }
        let stack = UIStackView(arrangedSubviews: parts)
        stack.axis = .vertical
        return stack
    }

    private func bindInteraction() {
        addButton.addTarget(self, action: #selector(handleAddTapped), for: .touchUpInside)
    }

    private func setupViewStyle() {
        let colors = TUIChatKitTheme.colors
        // Header, search bar and rows share the list surface (design S1/S2).
        view.backgroundColor = colors.bgColorTopBar
        if let searchPlaceholder { searchEntryBar.placeholderText = searchPlaceholder }
        conversationListView.setListHeaderView(makeListHeader())

        titleLabel.text = LocalizedChatString("TabChats")
        titleLabel.font = .adaptiveSystemFont(ofSize: Self.titleFontSize, weight: .bold)
        titleLabel.textColor = colors.textColorPrimary
        titleLabel.textAlignment = .center

        addButton.setImage(AtomicXChatResources.image(named: "contact_add_circle"), for: .normal)
        addButton.tintColor = colors.textColorPrimary
        addButton.isHidden = !AppBuilderConfig.shared.enableCreateConversation
    }

    @objc private func handleAddTapped() {
        let menu = BubbleMenuViewController(
            anchorView: addButton,
            items: [
                BubbleMenuViewController.Item(
                    icon: AtomicXChatResources.image(named: "contact_add_friend"),
                    title: LocalizedChatString("ChatsNewChatText"),
                    action: { [weak self] in self?.presentStartConversation() }
                ),
                BubbleMenuViewController.Item(
                    icon: AtomicXChatResources.image(named: "contact_add_group"),
                    title: LocalizedChatString("ChatsNewGroupText"),
                    action: { [weak self] in self?.presentUserPicker() }
                ),
            ]
        )
        present(menu, animated: false)
    }

    private func presentStartConversation() {
        let picker = CreateC2CConversationViewController(onUserSelected: { [weak self] user in
            guard let self = self else { return }
            let conversation = self.makeConversation(fromUser: user)
            self.openChatRemovingIntermediatePages(NavigationInfo(conversation: conversation))
        })
        picker.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(picker, animated: true)
    }

    private func presentUserPicker() {
        let picker = CreateGroupConversationViewController(onComplete: { [weak self] createdGroupID, groupName, conversationId in
            guard let self = self,
                  let groupID = createdGroupID,
                  let name = groupName,
                  let convId = conversationId else { return }
            let conversation = self.makeConversation(groupID: groupID, groupName: name, conversationId: convId)
            self.openChatRemovingIntermediatePages(NavigationInfo(conversation: conversation))
        })
        picker.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(picker, animated: true)
    }

    private func openChatRemovingIntermediatePages(_ info: NavigationInfo) {
        onConversationClick?(info)
        guard let navigationController = navigationController else { return }
        let stack = navigationController.viewControllers.filter {
            !($0 is CreateC2CConversationViewController)
                && !($0 is CreateGroupConversationViewController)
        }
        if stack.count != navigationController.viewControllers.count {
            navigationController.setViewControllers(stack, animated: false)
        }
    }

    private func makeConversation(fromUser user: AZOrderedListItem) -> ConversationInfo {
        var conversation = ConversationInfo(conversationID: ChatUtil.getC2CConversationID(user.userID))
        conversation.type = .c2c
        conversation.title = user.title ?? user.userID
        conversation.avatarURL = user.avatarURL
        return conversation
    }

    private func makeConversation(groupID: String, groupName: String, conversationId: String) -> ConversationInfo {
        var conversation = ConversationInfo(conversationID: conversationId)
        conversation.type = .group
        conversation.title = groupName
        conversation.avatarURL = nil
        return conversation
    }

    private func handleSearchResult(_ result: Any) {
        if let friendInfo = result as? FriendSearchInfo {
            navigateToFriend(friendInfo)
        } else if let groupInfo = result as? GroupSearchInfo {
            navigateToGroup(groupInfo)
        } else if let dict = result as? [String: Any] {
            navigateFromDictionary(dict)
        }
    }

    private func navigateToFriend(_ friendInfo: FriendSearchInfo) {
        let conversationID = ChatUtil.getC2CConversationID(friendInfo.userID)
        var conversation = ConversationInfo(conversationID: conversationID)
        conversation.type = .c2c
        conversation.title = friendInfo.friendRemark ?? friendInfo.userInfo?.nickname ?? friendInfo.userID
        conversation.avatarURL = friendInfo.userInfo?.avatarURL
        onConversationClick?(NavigationInfo(conversation: conversation))
    }

    private func navigateToGroup(_ groupInfo: GroupSearchInfo) {
        let conversationID = ChatUtil.getGroupConversationID(groupInfo.groupID)
        var conversation = ConversationInfo(conversationID: conversationID)
        conversation.type = .group
        conversation.title = groupInfo.groupName
        conversation.avatarURL = groupInfo.groupAvatarURL
        onConversationClick?(NavigationInfo(conversation: conversation))
    }

    private func navigateFromDictionary(_ dict: [String: Any]) {
        guard let conversationID = dict["conversationID"] as? String else { return }
        var conversation = ConversationInfo(conversationID: conversationID)
        conversation.type = conversationID.hasPrefix("c2c_") ? .c2c : .group
        conversation.title = dict["conversationName"] as? String
        conversation.avatarURL = dict["conversationAvatar"] as? String
        if let messageInfo = dict["message"] as? MessageInfo {
            onConversationClick?(NavigationInfo(conversation: conversation, locateMessage: messageInfo))
        } else {
            onConversationClick?(NavigationInfo(conversation: conversation))
        }
    }
}
