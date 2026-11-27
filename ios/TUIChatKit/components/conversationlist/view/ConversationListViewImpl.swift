import AtomicXCore
import Combine
import SnapKit
import UIKit

enum ConversationActionIDs {
    static let delete = "conversation.delete"
    static let mute = "conversation.mute"
    static let pin = "conversation.pin"
    static let markUnread = "conversation.markUnread"
    static let clearHistory = "conversation.clearHistory"
}

final class ConversationListViewImpl: RTCBaseView {
    private static let rowHeight: CGFloat = 72

    private let onConversationClick: (ConversationInfo) -> Void

    private let config: ConversationActionConfigProtocol

    private let viewModel: ConversationListViewModel

    private let emptyText: String?

    private let titleAccessory: ((ConversationInfo) -> UIView?)?

    private var conversations: [ConversationInfo] = []

    /// What the rows show, to tell a real list change from a republish of the same data.
    private var listSignature: String?

    private static func signature(of list: [ConversationInfo]) -> String {
        list.map { item in
            let last = item.lastMessage
            let fields: [String] = [
                item.conversationID, item.title ?? "", item.avatarURL ?? "", item.draft ?? "",
                String(item.unreadCount), String(item.isPinned), String(describing: item.receiveOption),
                item.conversationMarkList.map { String(describing: $0) }.joined(separator: ","),
                item.conversationGroupList.joined(separator: ","),
                last?.msgID ?? "", last.map { String(describing: $0.status) } ?? "",
                last?.timestamp.map(String.init) ?? "", last?.from.nickname ?? "", last?.from.avatarURL ?? "",
                last.map { String(describing: $0.messageType) } ?? "",
            ]
            return fields.joined(separator: "|")
        }.joined(separator: "\n")
    }

    private var cancellables = Set<AnyCancellable>()

    /// iOS 26 draws system swipe buttons as floating round buttons; there the row drives its own swipe
    /// (see `ConversationCell.setSwipeButtons`) so the buttons look the same as on earlier systems.
    private static var usesCustomSwipe: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    private weak var openCell: ConversationCell?

    private weak var dragCell: ConversationCell?

    private var dragStartOffset: CGFloat = 0

    private lazy var swipeGate: SwipePanGate = {
        let gate = SwipePanGate()
        gate.shouldBegin = { [weak self] pan in self?.canBeginSwipe(pan) ?? false }
        return gate
    }()

    private lazy var swipePan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSwipePan(_:)))
        pan.delegate = swipeGate
        return pan
    }()

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.separatorStyle = .none
        table.rowHeight = Self.rowHeight
        table.register(ConversationCell.self, forCellReuseIdentifier: ConversationCell.reuseIdentifier)
        return table
    }()

    private static let emptyIllustrationWidth: CGFloat = 88

    private static let emptyIllustrationAspectRatio: CGFloat = 300.0 / 338.0

    private static let emptyTextTopSpacing: CGFloat = 14

    private lazy var emptyView: UIView = {
        let view = UIView()
        view.isHidden = true
        return view
    }()

    private lazy var emptyIllustrationView: UIImageView = {
        let imageView = UIImageView(image: AtomicXChatResources.image(named: "uikit_empty_illustration"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.text = LocalizedChatString("EmptyContent")
        label.font = FontScheme.caption2Regular
        label.textColor = TUIChatKitTheme.colors.textColorTertiary
        label.textAlignment = .center
        return label
    }()

    init(onConversationClick: @escaping (ConversationInfo) -> Void,
         config: ConversationActionConfigProtocol = ChatConversationActionConfig(),
         conversationGroup: String? = nil,
         exclusion: ((ConversationInfo) -> Bool)? = nil,
         emptyText: String? = nil,
         markType: ConversationMarkType? = nil,
         exclusionChanges: AnyPublisher<Void, Never>? = nil,
         titleAccessory: ((ConversationInfo) -> UIView?)? = nil) {
        self.emptyText = emptyText
        self.onConversationClick = onConversationClick
        self.config = config
        self.titleAccessory = titleAccessory
        self.viewModel = ConversationListViewModel(conversationGroup: conversationGroup, exclusion: exclusion,
                                                   markType: markType, exclusionChanges: exclusionChanges)
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func constructViewHierarchy() {
        addSubview(tableView)
        addSubview(emptyView)
        emptyView.addSubview(emptyIllustrationView)
        emptyView.addSubview(emptyLabel)
    }

    public override func activateConstraints() {
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        emptyView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
        }
        emptyIllustrationView.snp.makeConstraints { make in
            make.top.centerX.equalToSuperview()
            make.width.equalTo(Self.emptyIllustrationWidth)
            make.height.equalTo(Self.emptyIllustrationWidth).multipliedBy(Self.emptyIllustrationAspectRatio)
        }
        emptyLabel.snp.makeConstraints { make in
            make.top.equalTo(emptyIllustrationView.snp.bottom).offset(Self.emptyTextTopSpacing)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    public override func bindInteraction() {
        tableView.dataSource = self
        tableView.delegate = self
        if Self.usesCustomSwipe { tableView.addGestureRecognizer(swipePan) }

        viewModel.$conversationList
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                guard let self else { return }
                // The store republishes the list about twice a second even when nothing changed; reloading for
                // those would close an open swipe row at once.
                let signature = Self.signature(of: list)
                guard signature != self.listSignature else { return }
                self.listSignature = signature
                self.closeOpenRow(animated: false)
                self.conversations = list
                self.tableView.reloadData()
                self.refreshEmptyViewVisibility()
            }
            .store(in: &cancellables)

        viewModel.$initialLoadFinished
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshEmptyViewVisibility()
            }
            .store(in: &cancellables)

        viewModel.loadConversations()
    }

    private func refreshEmptyViewVisibility() {
        emptyView.isHidden = !(viewModel.initialLoadFinished && conversations.isEmpty)
    }

    /// Content shown above the first row that scrolls away with the list (scene entry rows).
    func setListHeaderView(_ header: UIView?) {
        guard let header else {
            tableView.tableHeaderView = nil
            return
        }
        header.frame = CGRect(x: 0, y: 0, width: bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width,
                              height: header.systemLayoutSizeFitting(
                                CGSize(width: bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width,
                                       height: UIView.layoutFittingCompressedSize.height),
                                withHorizontalFittingPriority: .required,
                                verticalFittingPriority: .fittingSizeLevel).height)
        tableView.tableHeaderView = header
    }

    public override func setupViewStyle() {
        let listColor = TUIChatKitTheme.colors.bgColorTopBar
        backgroundColor = listColor
        tableView.backgroundColor = listColor
    }

    private func buildActions(for conversation: ConversationInfo) -> [ConversationCustomAction] {
        var defaultActions: [ConversationCustomAction] = []
        if config.isSupportPin {
            let pinned = conversation.isPinned
            let title = pinned ? LocalizedChatString("UnPin") : LocalizedChatString("Pin")
            defaultActions.append(ConversationCustomAction(ID: ConversationActionIDs.pin, title: title) { [weak self] _ in
                self?.viewModel.pinConversation(conversation, pin: !pinned)
            })
        }
        if config.isSupportMute {
            let willMute = conversation.receiveOption == .receive
            let title = willMute ? LocalizedChatString("ConversationMute") : LocalizedChatString("ConversationUnmute")
            defaultActions.append(ConversationCustomAction(ID: ConversationActionIDs.mute, title: title) { [weak self] _ in
                self?.viewModel.muteConversation(conversation, mute: willMute)
            })
        }
        if config.isSupportMarkUnread {
            let isUnread = viewModel.isUnread(conversation)
            let title = isUnread ? LocalizedChatString("MarkAsRead") : LocalizedChatString("MarkAsUnRead")
            defaultActions.append(ConversationCustomAction(ID: ConversationActionIDs.markUnread, title: title) { [weak self] _ in
                if isUnread {
                    self?.viewModel.markAsRead(conversation)
                } else {
                    self?.viewModel.markAsUnread(conversation)
                }
            })
        }
        if config.isSupportClearHistory {
            defaultActions.append(ConversationCustomAction(ID: ConversationActionIDs.clearHistory, title: LocalizedChatString("ConversationClearChatHistory")) { [weak self] _ in
                self?.confirmClearHistory(conversation)
            })
        }
        if config.isSupportDelete {
            defaultActions.append(ConversationCustomAction(ID: ConversationActionIDs.delete, title: LocalizedChatString("Delete"), dangerous: true) { [weak self] _ in
                self?.viewModel.deleteConversation(conversation)
            })
        }
        if let customizer = config.actionCustomizer {
            let editor = CustomEditor(items: defaultActions)
            customizer(editor)
            return editor.build()
        }
        return defaultActions
    }

    private func confirmDeleteConversation(_ conversation: ConversationInfo, action: ConversationCustomAction) {
        let alert = UIAlertController(
            title: LocalizedChatString("ConversationDeleteChatConfirmTitle"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: LocalizedChatString("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: LocalizedChatString("Delete"), style: .destructive) { _ in
            action.action(conversation)
        })
        findViewController()?.present(alert, animated: true)
    }

    private func confirmClearHistory(_ conversation: ConversationInfo) {
        let titleKey = conversation.type == .group ? "ClearGroupHistoryTips" : "ClearContactHistoryTips"
        let alert = UIAlertController(
            title: LocalizedChatString(titleKey),
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: LocalizedChatString("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: LocalizedChatString("Confirm"), style: .destructive) { [weak self] _ in
            self?.viewModel.clearHistory(conversation)
        })
        findViewController()?.present(alert, animated: true)
    }

    private func showMoreActionSheet(actions: [ConversationCustomAction], conversation: ConversationInfo) {
        // iOS 26 shows the system action sheet as a card in the middle of the screen; use a bottom
        // sheet there so it matches earlier systems.
        if Self.usesCustomSwipe {
            let items = actions.map { action in
                ConversationBottomSheetController.Item(title: action.title, dangerous: action.dangerous) {
                    action.action(conversation)
                }
            }
            let sheet = ConversationBottomSheetController(items: items, cancelTitle: LocalizedChatString("Cancel"))
            findViewController()?.present(sheet, animated: false)
            return
        }
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for action in actions {
            let style: UIAlertAction.Style = action.dangerous ? .destructive : .default
            alert.addAction(UIAlertAction(title: action.title, style: style) { _ in
                action.action(conversation)
            })
        }
        alert.addAction(UIAlertAction(title: LocalizedChatString("Cancel"), style: .cancel))
        // The sheet is system chrome: keep it on the theme instead of the default system blue.
        alert.view.tintColor = TUIChatKitTheme.colors.textColorPrimary
        if traitCollection.userInterfaceIdiom == .pad, let popover = alert.popoverPresentationController {
            popover.sourceView = self
            popover.sourceRect = bounds
        }
        findViewController()?.present(alert, animated: true)
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
}

extension ConversationListViewImpl: UITableViewDataSource {

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return conversations.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ConversationCell.reuseIdentifier,
            for: indexPath
        ) as? ConversationCell else {
            return UITableViewCell()
        }
        let conversation = conversations[indexPath.row]
        cell.configure(with: conversation)
        cell.setTitleAccessory(titleAccessory?(conversation))
        let colors = TUIChatKitTheme.colors
        cell.backgroundColor = conversation.isPinned ? colors.bgColorInput : colors.bgColorTopBar
        cell.setSeparatorHidden(indexPath.row == conversations.count - 1)
        return cell
    }
}

extension ConversationListViewImpl: UITableViewDelegate {

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // A tap while a row is open only closes it.
        if openCell != nil {
            closeOpenRow(animated: true)
            return
        }
        let conversation = conversations[indexPath.row]
        onConversationClick(conversation)
    }

    public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= conversations.count - 3 {
            viewModel.loadMoreIfNeeded()
        }
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        closeOpenRow(animated: true)
    }

    /// WeChat style swipe: [mark read / unread] [More] [Delete]. Pin, mute and clear history
    /// live behind "More"; there is no long-press menu on iOS.
    public func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !Self.usesCustomSwipe, indexPath.row < conversations.count else { return nil }
        // UIKit lays the first action out next to the trailing edge: delete, more, mark read / unread.
        let actions: [UIContextualAction] = swipeItems(for: conversations[indexPath.row]).reversed().map { item in
            let contextual = UIContextualAction(style: item.dangerous ? .destructive : .normal, title: item.title) { _, _, completion in
                item.handler()
                completion(true)
            }
            let (background, foreground) = Self.swipeColors(for: item.id)
            contextual.backgroundColor = background
            contextual.image = ConversationMenuSpec.swipeButtonImage(actionID: item.id, title: item.title, color: foreground)
            return contextual
        }
        guard !actions.isEmpty else { return nil }
        let configuration = UISwipeActionsConfiguration(actions: actions)
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}

// MARK: - Swipe buttons

extension ConversationListViewImpl {

    fileprivate struct SwipeItem {
        let id: String
        let title: String
        let dangerous: Bool
        let handler: () -> Void
    }

    /// Same pairing as the Android swipe buttons; delete is always white on the red.
    fileprivate static func swipeColors(for id: String) -> (background: UIColor, foreground: UIColor) {
        let colors = TUIChatKitTheme.colors
        switch id {
        case ConversationActionIDs.delete:
            return (colors.buttonColorHangupDefault, .white)
        case ConversationMenuSpec.moreActionID:
            return (colors.bgColorFunction, colors.textColorPrimary)
        default:
            return (colors.buttonColorSecondaryDefault, colors.textColorPrimary)
        }
    }

    /// The swipe buttons from the leading to the trailing side: [mark read / unread] [More] [Delete].
    fileprivate func swipeItems(for conversation: ConversationInfo) -> [SwipeItem] {
        let allActions = buildActions(for: conversation)
        let directActions = ConversationMenuSpec.swipeDirectActions(of: allActions)
        let moreActions = ConversationMenuSpec.swipeMoreActions(of: allActions)
        var items: [SwipeItem] = []
        if let unread = directActions.first(where: { $0.ID == ConversationActionIDs.markUnread }) {
            items.append(SwipeItem(id: unread.ID, title: unread.title, dangerous: false) {
                unread.action(conversation)
            })
        }
        if !moreActions.isEmpty {
            items.append(SwipeItem(id: ConversationMenuSpec.moreActionID, title: LocalizedChatString("More"), dangerous: false) { [weak self] in
                self?.showMoreActionSheet(actions: moreActions, conversation: conversation)
            })
        }
        if let delete = directActions.first(where: { $0.ID == ConversationActionIDs.delete }) {
            items.append(SwipeItem(id: delete.ID, title: delete.title, dangerous: true) { [weak self] in
                self?.confirmDeleteConversation(conversation, action: delete)
            })
        }
        return items
    }

    // MARK: Custom swipe (iOS 26)

    private func swipeCell(at point: CGPoint) -> ConversationCell? {
        guard let indexPath = tableView.indexPathForRow(at: point), indexPath.row < conversations.count else { return nil }
        return tableView.cellForRow(at: indexPath) as? ConversationCell
    }

    fileprivate func closeOpenRow(animated: Bool) {
        guard let cell = openCell else { return }
        openCell = nil
        settle(cell, open: false, animated: animated)
    }

    private func settle(_ cell: ConversationCell, open: Bool, animated: Bool) {
        let target = open ? cell.swipePanelWidth : 0
        guard animated else {
            cell.setSwipeOffset(target)
            return
        }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
            cell.setSwipeOffset(target)
        }
    }

    fileprivate func canBeginSwipe(_ pan: UIPanGestureRecognizer) -> Bool {
        // Asked once the finger has moved, so the translation already says where it is heading.
        let move = pan.translation(in: tableView)
        guard abs(move.x) > abs(move.y),
              let cell = swipeCell(at: pan.location(in: tableView)) else { return false }
        // A closed row only opens on a left swipe; an open one may be dragged both ways.
        return cell.swipeOffset > 0 || move.x < 0
    }

    @objc fileprivate func handleSwipePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            guard let cell = swipeCell(at: pan.location(in: tableView)),
                  let indexPath = tableView.indexPath(for: cell) else { return }
            if let open = openCell, open !== cell { closeOpenRow(animated: true) }
            if cell.swipeOffset == 0 {
                let buttons = swipeItems(for: conversations[indexPath.row]).map { item -> ConversationCell.SwipeButton in
                    let (background, foreground) = Self.swipeColors(for: item.id)
                    return ConversationCell.SwipeButton(
                        title: item.title,
                        image: ConversationMenuSpec.swipeButtonImage(actionID: item.id, title: item.title, color: foreground),
                        background: background) { [weak self] in
                            self?.closeOpenRow(animated: true)
                            item.handler()
                        }
                }
                cell.setSwipeButtons(buttons)
            }
            dragCell = cell
            dragStartOffset = cell.swipeOffset
        case .changed:
            guard let cell = dragCell else { return }
            let width = cell.swipePanelWidth
            let raw = dragStartOffset - pan.translation(in: tableView).x
            // Past the buttons the row resists, like the system rubber band.
            cell.setSwipeOffset(raw > width ? width + (raw - width) * 0.25 : raw)
        case .ended, .cancelled, .failed:
            guard let cell = dragCell else { return }
            dragCell = nil
            let velocity = pan.state == .ended ? pan.velocity(in: tableView).x : 0
            // Eager like the system swipe: a short pull is enough to open a closed row, and an open row closes
            // after a short pull back.
            let slack = min(cell.swipePanelWidth * 0.25, 28)
            let threshold = dragStartOffset > 0 ? cell.swipePanelWidth - slack : slack
            let open = velocity < -300 ? true : (velocity > 300 ? false : cell.swipeOffset > threshold)
            openCell = open ? cell : nil
            settle(cell, open: open, animated: true)
        default:
            break
        }
    }
}

/// Decides whether the row swipe pan may start (UIView already owns `gestureRecognizerShouldBegin`, so the
/// list view cannot be the delegate itself).
private final class SwipePanGate: NSObject, UIGestureRecognizerDelegate {
    var shouldBegin: ((UIPanGestureRecognizer) -> Bool)?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        return shouldBegin?(pan) ?? true
    }
}
