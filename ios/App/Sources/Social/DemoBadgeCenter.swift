import Foundation
import Combine
import AtomicXCore
import TUIChatKit

final class DemoBadgeCenter {
    static let shared = DemoBadgeCenter()

    let messagesSegment = CurrentValueSubject<Int, Never>(0)
    let friendsSegment = CurrentValueSubject<Int, Never>(0)
    let total = CurrentValueSubject<Int, Never>(0)

    private var account: String?
    private var recent = 0
    private var greeting = 0
    private var friends = 0
    private var cancellables = Set<AnyCancellable>()

    func ensureStarted(accountId: String) {
        if account == accountId, !cancellables.isEmpty { return }
        stop()
        account = accountId
        let contacts = ContactStore.shared
        contacts.loadFriendApplications(completion: nil)

        let watcher = DemoGroupWatcher.shared
        watcher.state
            .map { view -> (Int, Int) in
                let candidates = watcher.badgeCandidates(view)
                return (DemoBadgeRules.recentUnread(candidates), DemoBadgeRules.greetingUnread(candidates))
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] counts in
                self?.recent = counts.0
                self?.greeting = counts.1
                self?.publish()
            }
            .store(in: &cancellables)
        contacts.state
            .subscribe(StatePublisherSelector(keyPath: \ContactState.friendApplicationUnreadCount))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.friends = max(count, 0)
                self?.publish()
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        account = nil
        recent = 0
        greeting = 0
        friends = 0
        publish()
    }

    private func publish() {
        let segment = DemoBadgeRules.messagesSegment(recentUnread: recent, greetingUnread: greeting)
        if messagesSegment.value != segment { messagesSegment.send(segment) }
        if friendsSegment.value != friends { friendsSegment.send(friends) }
        let sum = DemoBadgeRules.mainTab(messagesSegment: segment, friendsSegment: friends)
        if total.value != sum { total.send(sum) }
    }
}
