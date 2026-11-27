import AtomicXCore
import Combine
import Foundation
import TUIChatKit
import TUIHostBase

// MARK: - Pure group logic

enum DemoLastMessageKind {
    case empty
    case mineSent
    case mineUnsent
    case other
}

enum DemoConversationSlot {
    case greeting
    case recent
    case pending
    case hidden
}

struct DemoGreetingCandidate: Equatable {
    let conversationID: String
    let isC2C: Bool
    let peerID: String
    let marked: Bool
    let last: DemoLastMessageKind
    var stamp: Int64 = 0
}

struct DemoGreetingContext: Equatable {
    var decided: Set<String> = []
    var friends: Set<String>?
    var friendsFailed = false
    var failed: Set<String> = []
    var marking: Set<String> = []
    var disabled = false
}

struct DemoGreetingPlan: Equatable {
    var decide: [String] = []
    var unmark: [String] = []
    var inspect: [String] = []

    var isEmpty: Bool { decide.isEmpty && unmark.isEmpty && inspect.isEmpty }
}

enum DemoConversationGroups {
    static func slot(_ c: DemoGreetingCandidate, _ ctx: DemoGreetingContext) -> DemoConversationSlot {
        if !c.isC2C || c.conversationID.isEmpty { return .hidden }
        if ctx.disabled || isRecent(c, ctx) { return .recent }
        if c.marked || ctx.marking.contains(c.conversationID) { return .greeting }
        if c.last == .empty || c.last == .mineUnsent { return .recent }
        if ctx.failed.contains(c.conversationID) { return .recent }
        if ctx.friends == nil && ctx.friendsFailed { return .recent }
        return .pending
    }

    static func plan(_ candidates: [DemoGreetingCandidate], _ ctx: DemoGreetingContext,
                     busy: Set<String> = []) -> DemoGreetingPlan {
        var plan = DemoGreetingPlan()
        if ctx.disabled { return plan }
        var seen = Set<String>()
        for c in candidates {
            let id = c.conversationID
            guard c.isC2C, !id.isEmpty, seen.insert(id).inserted, !busy.contains(id) else { continue }
            let decided = ctx.decided.contains(id)
            let evidence = isFriend(c, ctx) || c.last == .mineSent
            if c.marked {
                if decided || evidence {
                    if !decided { plan.decide.append(id) }
                    plan.unmark.append(id)
                }
            } else if decided {
                continue
            } else if evidence || c.last == .mineUnsent {
                plan.decide.append(id)
            } else if c.last == .empty || ctx.marking.contains(id) || ctx.failed.contains(id) || ctx.friends == nil {
                continue
            } else {
                plan.inspect.append(id)
            }
        }
        return plan
    }

    static func hasReply(_ history: [DemoLastMessageKind]) -> Bool {
        history.contains { $0 == .mineSent || $0 == .mineUnsent }
    }

    private static func isRecent(_ c: DemoGreetingCandidate, _ ctx: DemoGreetingContext) -> Bool {
        ctx.decided.contains(c.conversationID) || isFriend(c, ctx) || c.last == .mineSent
    }

    private static func isFriend(_ c: DemoGreetingCandidate, _ ctx: DemoGreetingContext) -> Bool {
        ctx.friends?.contains(c.peerID) == true
    }
}

struct DemoGroupResult: Equatable {
    let ok: Bool
    let code: Int
    let desc: String

    static let success = DemoGroupResult(ok: true, code: 0, desc: "")

    static func failed(code: Int, desc: String) -> DemoGroupResult {
        DemoGroupResult(ok: false, code: code, desc: desc)
    }
}

enum DemoGroupDiagnostics {
    static let packageUnsupportedCodes: Set<Int> = [7013, 51013]
    static let didChange = Notification.Name("chat.groupDiagnosticsDidChange")

    static var logger: (String) -> Void = { NSLog("Chat1v1Groups: %@", $0) }
    static var onFailure: (String, DemoGroupResult) -> Void = { _, _ in }
    private(set) static var lastFailure: DemoGroupResult?
    private(set) static var packageUnsupported = false

    static func record(_ operation: String, _ result: DemoGroupResult) {
        guard !result.ok else { return }
        lastFailure = result
        logger("\(operation) failed: code=\(result.code) desc=\(result.desc)")
        onFailure(operation, result)
        if packageUnsupportedCodes.contains(result.code), !packageUnsupported {
            packageUnsupported = true
            DispatchQueue.main.async { NotificationCenter.default.post(name: didChange, object: nil) }
        }
    }

    static func emptyText(_ fallback: String) -> String {
        packageUnsupported ? DemoText.get("demo_the_current_sdkappid_plan_does_not_support") : fallback
    }

    static func reset() {
        lastFailure = nil
        packageUnsupported = false
    }
}

protocol DemoGreetingPorts: AnyObject {
    func inspect(_ conversationID: String, done: @escaping (Bool?) -> Void)
    func setGreeting(_ ids: [String], greeting: Bool, done: @escaping (DemoGroupResult) -> Void)
    func loadFriends(_ done: @escaping (Set<String>?) -> Void)
}

protocol DemoDecidedStore: AnyObject {
    func load() -> Set<String>
    func save(_ ids: Set<String>)
}

final class DemoGroupWatch {
    static let batch = 100
    static let inspectTimeoutMs: Int64 = 15_000
    static let friendsRetryFirstMs: Int64 = 2_000
    static let friendsRetryMaxMs: Int64 = 30_000

    var onChange: (DemoGreetingContext) -> Void

    private let ports: DemoGreetingPorts
    private let store: DemoDecidedStore
    private let isDisabled: () -> Bool
    private let schedule: (Int64, @escaping () -> Void) -> Void
    private var decided: Set<String>
    private var friends: Set<String>?
    private var friendsFailed = false
    private var friendsLoading = false
    private var friendsRetryPending = false
    private var friendsRetryDelay = DemoGroupWatch.friendsRetryFirstMs
    private var failed: [String: Int64] = [:]
    private var marking = Set<String>()
    private var busy = Set<String>()
    private var queue: [String] = []
    private var inspecting: String?
    private var token = 0
    private var latestList: [DemoGreetingCandidate] = []
    private var latest: [String: DemoGreetingCandidate] = [:]
    private var seen = Set<String>()

    init(ports: DemoGreetingPorts,
         store: DemoDecidedStore,
         isDisabled: @escaping () -> Bool = { DemoGroupDiagnostics.packageUnsupported },
         schedule: @escaping (Int64, @escaping () -> Void) -> Void = { _, _ in },
         onChange: @escaping (DemoGreetingContext) -> Void = { _ in }) {
        self.ports = ports
        self.store = store
        self.isDisabled = isDisabled
        self.schedule = schedule
        self.onChange = onChange
        decided = store.load()
    }

    var context: DemoGreetingContext {
        DemoGreetingContext(decided: decided, friends: friends, friendsFailed: friendsFailed,
                            failed: Set(failed.keys), marking: marking, disabled: isDisabled())
    }

    func onSnapshot(_ candidates: [DemoGreetingCandidate]) {
        let ids = Set(candidates.map(\.conversationID))
        let gone = seen.subtracting(ids)
        seen = ids
        if !gone.isEmpty {
            gone.forEach { failed.removeValue(forKey: $0) }
            marking.subtract(gone)
        }
        for c in candidates {
            if c.marked { marking.remove(c.conversationID) }
            if let failedAt = failed[c.conversationID], failedAt != c.stamp { failed.removeValue(forKey: c.conversationID) }
        }
        latestList = candidates
        latest = Dictionary(candidates.map { ($0.conversationID, $0) }, uniquingKeysWith: { first, _ in first })
        loadFriendsIfNeeded()
        run()
    }

    func onFriendsChanged(_ ids: Set<String>) {
        guard friends != nil, friends != ids else { return }
        friends = ids
        run()
    }

    func noteReplied(_ conversationID: String) {
        guard !conversationID.isEmpty else { return }
        failed.removeValue(forKey: conversationID)
        if decided.insert(conversationID).inserted { store.save(decided) }
        run()
    }

    private func loadFriendsIfNeeded() {
        guard friends == nil, !friendsLoading, !friendsRetryPending else { return }
        friendsLoading = true
        ports.loadFriends { ids in
            self.friendsLoading = false
            if let ids {
                self.friends = ids
                self.friendsFailed = false
                self.friendsRetryDelay = Self.friendsRetryFirstMs
            } else {
                self.friendsFailed = true
                self.friendsRetryPending = true
                let delay = self.friendsRetryDelay
                self.friendsRetryDelay = min(delay * 2, Self.friendsRetryMaxMs)
                self.schedule(delay) {
                    self.friendsRetryPending = false
                    self.loadFriendsIfNeeded()
                }
            }
            self.run()
        }
    }

    private func run() {
        let plan = DemoConversationGroups.plan(latestList, context, busy: busy)
        if !plan.decide.isEmpty {
            let before = decided.count
            decided.formUnion(plan.decide)
            if decided.count != before { store.save(decided) }
        }
        stride(from: 0, to: plan.unmark.count, by: Self.batch).forEach { start in
            unmark(Array(plan.unmark[start..<min(start + Self.batch, plan.unmark.count)]))
        }
        for id in plan.inspect {
            busy.insert(id)
            queue.append(id)
        }
        onChange(context)
        pump()
    }

    private func unmark(_ ids: [String]) {
        busy.formUnion(ids)
        ports.setGreeting(ids, greeting: false) { _ in
            self.busy.subtract(ids)
            self.onChange(self.context)
        }
    }

    private func pump() {
        guard inspecting == nil, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        inspecting = id
        token += 1
        let mine = token
        schedule(Self.inspectTimeoutMs) {
            if self.token == mine { self.finish(id, nil) }
        }
        ports.inspect(id) { verdict in
            if self.token == mine { self.finish(id, verdict) }
        }
    }

    private func finish(_ id: String, _ verdict: Bool?) {
        token += 1
        inspecting = nil
        guard let c = latest[id] else {
            busy.remove(id)
            return run()
        }
        switch verdict {
        case .none:
            busy.remove(id)
            failed[id] = c.stamp
        case .some(true):
            busy.remove(id)
            if decided.insert(id).inserted { store.save(decided) }
        case .some(false):
            if DemoConversationGroups.slot(c, context) != .pending {
                busy.remove(id)
            } else {
                ports.setGreeting([id], greeting: true) { result in
                    self.busy.remove(id)
                    if result.ok {
                        if self.latest[id]?.marked != true { self.marking.insert(id) }
                    } else {
                        self.failed[id] = self.latest[id]?.stamp ?? c.stamp
                    }
                    self.run()
                }
            }
        }
        run()
    }
}

struct DemoBadgeCandidate {
    let conversationID: String
    let slot: DemoConversationSlot
    let unreadCount: Int
    var muted = false
}

/// The numbers on the Messages tab add up the unread messages the lists show (not the number of conversations):
/// recent unread + greeting unread on the 消息 segment, pending applications on the 好友 segment, the bottom tab is the sum.
/// A muted conversation shows only a dot in the list, so it adds nothing. Drafts and failed sends have no number either.
enum DemoBadgeRules {
    static func isValidRecent(_ c: DemoBadgeCandidate) -> Bool {
        !c.conversationID.isEmpty && c.slot == .recent
    }

    static func isValidGreeting(_ c: DemoBadgeCandidate) -> Bool {
        !c.conversationID.isEmpty && c.slot == .greeting
    }

    private static func counted(_ c: DemoBadgeCandidate) -> Int { c.muted ? 0 : max(c.unreadCount, 0) }

    static func recentUnread(_ list: [DemoBadgeCandidate]) -> Int {
        unique(list.filter(isValidRecent)).reduce(0) { $0 + counted($1) }
    }

    static func messagesSegment(recentUnread: Int, greetingUnread: Int) -> Int { max(recentUnread, 0) + max(greetingUnread, 0) }

    static func mainTab(messagesSegment: Int, friendsSegment: Int) -> Int { max(messagesSegment, 0) + max(friendsSegment, 0) }

    static func greetingUnread(_ list: [DemoBadgeCandidate]) -> Int {
        unique(list.filter(isValidGreeting)).reduce(0) { $0 + counted($1) }
    }

    private static func unique(_ list: [DemoBadgeCandidate]) -> [DemoBadgeCandidate] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.conversationID).inserted }
    }
}

/// A conversation list the SDK hands out one page at a time.
protocol DemoPagedConversations: AnyObject {
    var hasMore: Bool { get }
    func reload(_ done: @escaping (Bool) -> Void)
    func loadMore(_ done: @escaping (Bool) -> Void)
}

/// Badges and bulk operations must see every member, not the first 100: this walks the pages until the SDK
/// reports the end. A page cap keeps a misbehaving list from looping forever, and `shouldContinue` lets a
/// newer load supersede an older chain.
enum DemoConversationPaging {
    static let maxPages = 50

    static func loadAll(_ source: DemoPagedConversations,
                        shouldContinue: @escaping () -> Bool = { true },
                        done: @escaping (Bool) -> Void = { _ in }) {
        source.reload { ok in
            if ok {
                loadRest(source, loaded: 1, shouldContinue: shouldContinue, done: done)
            } else {
                done(false)
            }
        }
    }

    private static func loadRest(_ source: DemoPagedConversations, loaded: Int,
                                 shouldContinue: @escaping () -> Bool, done: @escaping (Bool) -> Void) {
        if !source.hasMore { return done(true) }
        if loaded >= maxPages || !shouldContinue() { return done(false) }
        source.loadMore { ok in
            if ok {
                loadRest(source, loaded: loaded + 1, shouldContinue: shouldContinue, done: done)
            } else {
                done(false)
            }
        }
    }
}

/// One live paging chain per list: a newer `load` supersedes the chain in flight, so pages of two
/// overlapping loads are never requested interleaved from the same store. The chain keeps the loader
/// alive until it ends, so a temporary instance still finishes its load.
final class DemoPagedConversationLoader {
    private let source: DemoPagedConversations
    private var generation = 0

    init(source: DemoPagedConversations) {
        self.source = source
    }

    func load(done: @escaping (Bool) -> Void = { _ in }) {
        generation += 1
        let mine = generation
        DemoConversationPaging.loadAll(source, shouldContinue: { self.generation == mine }, done: done)
    }
}

// MARK: - SDK bindings

enum DemoConversationClassifier {
    static let greetingMark: ConversationMarkType = .fold

    static func kind(of message: MessageInfo?) -> DemoLastMessageKind {
        guard let message else { return .empty }
        if message.messageType == .tips
            || ConversationBannerSummary.isTypingMessage(message)
            || ConversationBannerSummary.isCallMessage(message) {
            return .other
        }
        guard message.isSentBySelf else { return .other }
        return message.status == .sendSuccess ? .mineSent : .mineUnsent
    }

    static func isGreetingMarked(_ info: ConversationInfo) -> Bool {
        info.conversationMarkList.contains { $0.contains(greetingMark) }
    }

    static func candidate(of info: ConversationInfo) -> DemoGreetingCandidate {
        let id = info.conversationID
        return DemoGreetingCandidate(
            conversationID: id,
            isC2C: info.type == .c2c,
            peerID: id.hasPrefix("c2c_") ? String(id.dropFirst(4)) : id,
            marked: isGreetingMarked(info),
            last: kind(of: info.lastMessage),
            stamp: info.lastMessage?.timestamp ?? 0
        )
    }
}

extension ConversationInfo {
    var demoGreetingCandidate: DemoGreetingCandidate { DemoConversationClassifier.candidate(of: self) }

    func demoBadgeCandidate(_ context: DemoGreetingContext) -> DemoBadgeCandidate {
        DemoBadgeCandidate(
            conversationID: conversationID,
            slot: DemoConversationGroups.slot(demoGreetingCandidate, context),
            unreadCount: unreadCount,
            muted: receiveOption != .receive
        )
    }
}

final class DemoUserDefaultsDecidedStore: DemoDecidedStore {
    private let key: String

    init(account: String) {
        key = "demo.greeting.recent.\(account)"
    }

    func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func save(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}

final class DemoSdkGreetingPorts: DemoGreetingPorts {
    private static let page = 20
    private static let maxPages = 3

    private let marks: ConversationListStore

    init(marks: ConversationListStore) {
        self.marks = marks
    }

    func inspect(_ conversationID: String, done: @escaping (Bool?) -> Void) {
        let history = MessageListStore.create(conversationID: conversationID)
        func finish(_ verdict: Bool?) {
            DispatchQueue.main.async { done(verdict) }
        }
        func replied() -> Bool {
            DemoConversationGroups.hasReply(history.state.value.messageList.map { DemoConversationClassifier.kind(of: $0) })
        }
        func next(_ page: Int) {
            if replied() { return finish(true) }
            if !history.state.value.hasOlderMessages || page >= Self.maxPages { return finish(false) }
            history.loadOlderMessages { result in
                DispatchQueue.main.async {
                    if case .failure(let error) = result {
                        DemoGroupDiagnostics.record("inspectOlder", .failed(code: error.code, desc: error.message))
                        return finish(nil)
                    }
                    next(page + 1)
                }
            }
        }
        var option = MessageLoadOption()
        option.pageCount = Self.page
        history.loadMessages(option: option) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    next(1)
                case .failure(let error):
                    DemoGroupDiagnostics.record("inspect", .failed(code: error.code, desc: error.message))
                    finish(nil)
                }
            }
        }
    }

    func setGreeting(_ ids: [String], greeting: Bool, done: @escaping (DemoGroupResult) -> Void) {
        let operation = greeting ? "markGreeting" : "unmarkGreeting"
        marks.markConversation(conversationIDList: ids, markType: DemoConversationClassifier.greetingMark,
                               enable: greeting) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    done(.success)
                case .failure(let error):
                    let failed = DemoGroupResult.failed(code: error.code, desc: error.message)
                    DemoGroupDiagnostics.record(operation, failed)
                    done(failed)
                }
            }
        }
    }

    func loadFriends(_ done: @escaping (Set<String>?) -> Void) {
        let contacts = ContactStore.shared
        contacts.loadFriends { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    done(Set(contacts.state.value.friendList.map(\.userID)))
                case .failure(let error):
                    DemoGroupDiagnostics.record("loadFriends", .failed(code: error.code, desc: error.message))
                    done(nil)
                }
            }
        }
    }
}

/// Real paging over a `ConversationListStore`; failures are recorded instead of swallowed.
final class DemoSdkPagedConversations: DemoPagedConversations {
    private let store: ConversationListStore
    private let markType: ConversationMarkType?

    init(store: ConversationListStore, markType: ConversationMarkType? = nil) {
        self.store = store
        self.markType = markType
    }

    var hasMore: Bool { store.state.value.hasMoreConversations }

    func reload(_ done: @escaping (Bool) -> Void) {
        var option = ConversationLoadOption()
        option.markType = markType
        store.loadConversations(option: option) { Self.finish("loadConversations", $0, done) }
    }

    func loadMore(_ done: @escaping (Bool) -> Void) {
        store.loadMoreConversations { Self.finish("loadMoreConversations", $0, done) }
    }

    private static func finish(_ operation: String, _ result: Result<Void, ErrorInfo>, _ done: (Bool) -> Void) {
        switch result {
        case .success:
            done(true)
        case .failure(let error):
            DemoGroupDiagnostics.record(operation, .failed(code: error.code, desc: error.message))
            done(false)
        }
    }
}

struct DemoGreetingView {
    var conversations: [ConversationInfo] = []
    var context = DemoGreetingContext()
}

final class DemoGroupWatcher {
    static let shared = DemoGroupWatcher()

    private static let settle: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(300)

    let state = CurrentValueSubject<DemoGreetingView, Never>(DemoGreetingView())

    var contextChanges: AnyPublisher<Void, Never> {
        state.map(\.context).removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher()
    }

    private var account: String?
    private var store: ConversationListStore?
    private var loader: DemoPagedConversationLoader?
    private var watch: DemoGroupWatch?
    private var conversations: [ConversationInfo] = []
    private var cancellables = Set<AnyCancellable>()

    func ensureStarted(accountId: String) {
        if store != nil, account == accountId { return }
        stop()
        account = accountId
        let store = ConversationListStore.create()
        let watch = DemoGroupWatch(
            ports: DemoSdkGreetingPorts(marks: store),
            store: DemoUserDefaultsDecidedStore(account: accountId),
            schedule: { delay, action in
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(delay)), execute: action)
            })
        watch.onChange = { [weak self, weak watch] context in
            guard let self, let watch, self.watch === watch else { return }
            self.publish(context)
        }
        let loader = DemoPagedConversationLoader(source: DemoSdkPagedConversations(store: store))
        self.store = store
        self.loader = loader
        self.watch = watch
        publish(watch.context)
        loader.load()
        let list = store.state.subscribe(StatePublisherSelector(keyPath: \ConversationListState.conversationList))
        list.receive(on: DispatchQueue.main)
            .sink { [weak self] conversations in
                self?.conversations = conversations
                self?.publish(watch.context)
            }
            .store(in: &cancellables)
        list.debounce(for: Self.settle, scheduler: DispatchQueue.main)
            .sink { conversations in watch.onSnapshot(conversations.map(\.demoGreetingCandidate)) }
            .store(in: &cancellables)
        ContactStore.shared.state
            .subscribe(StatePublisherSelector(keyPath: \ContactState.friendList))
            .receive(on: DispatchQueue.main)
            .sink { friends in watch.onFriendsChanged(Set(friends.map(\.userID))) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: DemoGroupDiagnostics.didChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.publish(watch.context) }
            .store(in: &cancellables)
    }

    func noteReplied(_ conversationID: String) {
        watch?.noteReplied(conversationID)
    }

    func slot(of info: ConversationInfo, context: DemoGreetingContext? = nil) -> DemoConversationSlot {
        DemoConversationGroups.slot(info.demoGreetingCandidate, context ?? state.value.context)
    }

    func greetingMembers(_ view: DemoGreetingView? = nil) -> [ConversationInfo] {
        let view = view ?? state.value
        var seen = Set<String>()
        return view.conversations.filter {
            slot(of: $0, context: view.context) == .greeting && seen.insert($0.conversationID).inserted
        }
    }

    func badgeCandidates(_ view: DemoGreetingView) -> [DemoBadgeCandidate] {
        view.conversations.map { $0.demoBadgeCandidate(view.context) }
    }

    func stop() {
        cancellables.removeAll()
        store = nil
        loader = nil
        watch = nil
        account = nil
        conversations = []
        state.send(DemoGreetingView())
    }

    private func publish(_ context: DemoGreetingContext) {
        state.send(DemoGreetingView(conversations: conversations, context: context))
    }
}

final class DemoCallPromoter {
    static let shared = DemoCallPromoter()

    private static let startCallEventName = Notification.Name("tuicallkit.startCall")
    private static let keyParticipantIDs = "participantIds"
    private static let keyChatGroupID = "chatGroupId"

    private var subscribed = false

    private init() {}

    func ensureStarted() {
        guard !subscribed else { return }
        subscribed = true
        NotificationCenter.default.addObserver(self, selector: #selector(handleStartCall(_:)),
                                               name: Self.startCallEventName, object: nil)
    }

    func stop() {
        guard subscribed else { return }
        subscribed = false
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleStartCall(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        if let groupID = userInfo[Self.keyChatGroupID] as? String, !groupID.isEmpty { return }
        guard let participants = userInfo[Self.keyParticipantIDs] as? [String],
              participants.count == 1,
              let peer = participants.first, !peer.isEmpty else { return }
        DemoGroupWatcher.shared.noteReplied("c2c_\(peer)")
    }
}
