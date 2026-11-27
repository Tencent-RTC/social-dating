import Foundation
import Combine
import AtomicXCore

/// A store made by `ConversationListStore.create(conversationGroup:)` loads a correctly filtered first
/// page, but afterwards merges every live conversation event into its list without checking the group it
/// is bound to. A group-bound list therefore re-checks membership itself, and reloads when membership
/// changes underneath it (the SDK does not push a conversation change for add/remove-from-group).
public enum ConversationGroupMembership {
    public static let didChange = Notification.Name("chat.conversationGroupMembershipDidChange")

    private static let builtInGroups: Set<String> = ["_c2c_", "_group_", "_hasUnreadCount_", "_hasGroupAtInfo_"]

    public static func notifyChanged() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: didChange, object: nil) }
    }

    /// Built-in filters (C2C / group chats / unread / @me) are not custom groups and carry no membership.
    public static func isCustomGroup(_ group: String?) -> Bool {
        guard let group, !group.isEmpty else { return false }
        return !builtInGroups.contains(group)
    }

    public static func isMember(group: String?, memberships: [String]) -> Bool {
        guard isCustomGroup(group), let group else { return true }
        return memberships.contains(group)
    }
}

final class ConversationListViewModel {
    private static let autoFillCount = 20

    @Published private(set) var conversationList: [ConversationInfo] = []

    @Published private(set) var initialLoadFinished = false

    private let store: ConversationListStore

    private let conversationGroup: String?

    /// Returns true for conversations the host wants hidden from this list.
    private let exclusion: ((ConversationInfo) -> Bool)?

    private let markType: ConversationMarkType?

    private let exclusionChanges: AnyPublisher<Void, Never>?

    private var isLoadingMore = false

    private var lastAutoFillCount = -1

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(store: ConversationListStore = ConversationListStore.create(),
         conversationGroup: String? = nil,
         exclusion: ((ConversationInfo) -> Bool)? = nil,
         markType: ConversationMarkType? = nil,
         exclusionChanges: AnyPublisher<Void, Never>? = nil) {
        self.store = store
        self.conversationGroup = conversationGroup
        self.exclusion = exclusion
        self.markType = markType
        self.exclusionChanges = exclusionChanges
        subscribeState()
        observeMembership()
    }

    /// Group-bound list: each social tab owns its own store instance.
    convenience init(conversationGroup: String?,
                     exclusion: ((ConversationInfo) -> Bool)? = nil,
                     markType: ConversationMarkType? = nil,
                     exclusionChanges: AnyPublisher<Void, Never>? = nil) {
        self.init(store: ConversationListStore.create(conversationGroup: conversationGroup),
                  conversationGroup: conversationGroup, exclusion: exclusion,
                  markType: markType, exclusionChanges: exclusionChanges)
    }

    // MARK: - Business Actions (forwarded to core store)

    func loadConversations(completion: (() -> Void)? = nil) {
        store.loadConversations(option: loadOption()) { _ in
            DispatchQueue.main.async {
                self.initialLoadFinished = true
                self.fillIfShort()
                completion?()
            }
        }
    }

    func loadMoreIfNeeded() {
        guard initialLoadFinished, !isLoadingMore, store.state.value.hasMoreConversations else { return }
        loadMore()
    }

    func deleteConversation(_ conversation: ConversationInfo) {
        store.deleteConversation(conversationID: conversation.conversationID, completion: nil)
    }

    func pinConversation(_ conversation: ConversationInfo, pin: Bool) {
        store.pinConversation(conversationID: conversation.conversationID, pin: pin, completion: nil)
    }

    func clearHistory(_ conversation: ConversationInfo) {
        // 清空聊天记录不会动未读：被标为未读的会话清空后，未读数/红点会一直留着，所以一并清掉。
        ConversationUnreadClearer.clearMessages(store: store, conversationID: conversation.conversationID)
    }

    func clearUnreadCount(_ conversation: ConversationInfo) {
        ConversationUnreadClearer.clearConversationsUnread(store: store, conversations: [conversation])
    }

    func markAsRead(_ conversation: ConversationInfo) {
        clearUnreadCount(conversation)
    }

    func markAsUnread(_ conversation: ConversationInfo) {
        store.markConversation(
            conversationIDList: [conversation.conversationID],
            markType: .unread,
            enable: true,
            completion: nil
        )
    }

    func muteConversation(_ conversation: ConversationInfo, mute: Bool) {
        store.setReceiveMessageOpt(
            conversationID: conversation.conversationID,
            opt: mute ? .notNotify : .receive,
            completion: nil
        )
    }

    // MARK: - Derived Helpers

    func isUnread(_ conversation: ConversationInfo) -> Bool {
        return conversation.unreadCount > 0 || conversation.conversationMarkList.contains(.unread)
    }

    private func loadOption() -> ConversationLoadOption {
        var option = ConversationLoadOption()
        option.markType = markType
        return option
    }

    private func loadMore() {
        isLoadingMore = true
        store.loadMoreConversations { [weak self] _ in
            DispatchQueue.main.async {
                self?.isLoadingMore = false
                self?.fillIfShort()
            }
        }
    }

    private func fillIfShort() {
        guard initialLoadFinished, !isLoadingMore, conversationList.count < Self.autoFillCount,
              store.state.value.hasMoreConversations else { return }
        let loaded = store.state.value.conversationList.count
        guard loaded != lastAutoFillCount else { return }
        lastAutoFillCount = loaded
        loadMore()
    }

    private func subscribeState() {
        let group = conversationGroup
        let hostExclusion = exclusion
        let changes = (exclusionChanges ?? Empty<Void, Never>().eraseToAnyPublisher()).prepend(())
        store.state
            .subscribe(StatePublisherSelector(keyPath: \ConversationListState.conversationList))
            .combineLatest(changes)
            .map { list, _ in Self.sanitize(list, group: group, exclusion: hostExclusion) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                self?.conversationList = list
                self?.fillIfShort()
            }
            .store(in: &cancellables)
    }

    /// Re-reads the group-bound store whenever membership changes.
    private func observeMembership() {
        guard ConversationGroupMembership.isCustomGroup(conversationGroup) else { return }
        NotificationCenter.default.publisher(for: ConversationGroupMembership.didChange)
            .sink { [weak self] _ in
                guard let self else { return }
                self.store.loadConversations(option: self.loadOption(), completion: nil)
            }
            .store(in: &cancellables)
    }

    private static func sanitize(_ list: [ConversationInfo],
                                 group: String?,
                                 exclusion: ((ConversationInfo) -> Bool)?) -> [ConversationInfo] {
        var seenConversationIDs = Set<String>()
        var result: [ConversationInfo] = []
        for conversation in list where !conversation.conversationID.isEmpty {
            guard ConversationGroupMembership.isMember(group: group, memberships: conversation.conversationGroupList) else { continue }
            if exclusion?(conversation) == true { continue }
            if seenConversationIDs.insert(conversation.conversationID).inserted {
                result.append(conversation)
            }
        }
        return result
    }
}
