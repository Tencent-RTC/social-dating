import Foundation
import AtomicXCore

/// 清未读的统一入口（与 Android `ConversationUnreadClearer` 同一套规则）。
///
/// 一个会话的“未读”有两部分：未读数（unreadCount）和“标记未读”（`ConversationMarkType.unread`）。
/// 只调 `clearConversationUnreadCount` 清不掉标记，列表里仍会显示红点/未读；
/// 只取 `unreadCount > 0` 做筛选，则会漏掉“只有标记、没有未读数”的会话。
///
/// 这里统一成：先去掉“标记未读”，等它完成后再清未读数。顺序不能反：数字先清成 0 而标记还在的话，
/// 角标会先变成一个红点，等标记去掉后才消失。
public enum ConversationUnreadClearer {
    private static let unmarkBatchSize = 100

    /// 清掉这些会话的未读数和“标记未读”。标记只对带标记的会话去掉，没有标记的不发请求。
    public static func clearConversationsUnread(
        store: ConversationListStore,
        conversations: [ConversationInfo],
        completion: CompletionClosure? = nil
    ) {
        clearUnread(
            store: store,
            conversationIDs: conversations.map { $0.conversationID },
            markedConversationIDs: conversations
                .filter { $0.conversationMarkList.contains(.unread) }
                .map { $0.conversationID },
            completion: completion
        )
    }

    /// - Parameter markedConversationIDs: 需要去掉“标记未读”的会话，默认全部；
    ///   去标记失败（例如套餐不支持会话标记）时仍会继续清未读数。
    public static func clearUnread(
        store: ConversationListStore,
        conversationIDs: [String],
        markedConversationIDs: [String]? = nil,
        completion: CompletionClosure? = nil
    ) {
        let ids = unique(conversationIDs)
        guard !ids.isEmpty else {
            completion?(.success(()))
            return
        }
        let marked = unique(markedConversationIDs ?? ids)
        unmark(store: store, ids: marked, from: 0) {
            clearCounts(store: store, ids: ids, completion: completion)
        }
    }

    /// 清空聊天记录，并把这个会话的未读数、“标记未读”一起清掉。
    /// 清空聊天记录本身不会动未读：会话被标为未读后清空记录，未读数/红点会一直留着。
    /// `completion` 反映清空聊天记录的结果；清未读是随后尽力而为，不影响它。
    public static func clearMessages(
        store: ConversationListStore,
        conversationID: String,
        completion: CompletionClosure? = nil
    ) {
        store.clearConversationMessages(conversationID: conversationID) { result in
            completion?(result)
            if case .success = result {
                clearUnread(store: store, conversationIDs: [conversationID])
            }
        }
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func unmark(store: ConversationListStore, ids: [String], from start: Int, done: @escaping () -> Void) {
        guard start < ids.count else {
            done()
            return
        }
        let end = min(start + unmarkBatchSize, ids.count)
        store.markConversation(
            conversationIDList: Array(ids[start..<end]),
            markType: .unread,
            enable: false
        ) { result in
            if case .success = result {
                unmark(store: store, ids: ids, from: end, done: done)
            } else {
                done()
            }
        }
    }

    private static func clearCounts(store: ConversationListStore, ids: [String], completion: CompletionClosure?) {
        let group = DispatchGroup()
        let lock = NSLock()
        var failure: ErrorInfo?
        for id in ids {
            group.enter()
            store.clearConversationUnreadCount(conversationID: id) { result in
                if case .failure(let error) = result {
                    lock.lock()
                    if failure == nil { failure = error }
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if let error = failure {
                completion?(.failure(error))
            } else {
                completion?(.success(()))
            }
        }
    }
}
