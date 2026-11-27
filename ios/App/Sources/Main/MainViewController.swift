import UIKit
import Combine
import AtomicXCore
import AtomicX
import ImSDK_Plus
import TUIChatKit
import TUICallKit
import TUIHomeKit
import TUIMineKit
import TUIHostBase
import SDWebImage

extension MainViewController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController,
                          animationControllerForTransitionFrom fromVC: UIViewController,
                          to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard Motion.enabled, fromVC !== toVC else { return nil }
        return HostTabFadeAnimator()
    }
}

/// V2 host shell: exactly three primary tabs. Home and Mine are the TUIHomeKit / TUIMineKit modules;
/// Messages binds the real IM conversation list. No business backend, no HTTP fixtures.
final class MainViewController: UITabBarController {
    private let accountId: String
    private let preview: Bool
    private var cancellables = Set<AnyCancellable>()
    private var shownBadgeCount = 0
    private var settlePending = false
    private var settleAttempts = 0
    private var previewIdentity: MineIdentity? {
        preview ? MineIdentity(nickname: DemoText.get("demo_ye"), idText: DemoText.get("demo_id_7271_76_shenzhen"), avatar: "demo_avatar_me") : nil
    }
    init(accountId: String, preview: Bool = false) {
        self.accountId = accountId
        self.preview = preview
        DemoHostSession.accountId = accountId
        DemoHostSession.preview = preview
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        settleFloatingTabBar()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        settleFloatingTabBar()
    }

    /// iOS 26.x floating glass tab bar (UIKit bug; iOS 18 and iOS 27 are fine): the bar's first layout pass runs while
    /// its platter is still 0×0, and every tab button caches the label size it measured then. Giving the bar its real
    /// size does not invalidate that cache — only selecting the tab or changing its item does — so all labels stay
    /// squeezed (≈8pt high) and pushed down, clipped by the capsule, until each tab is visited.
    /// Fix: once the bar has been laid out at its real size (next run loop turn), re-assign every item's title, which
    /// makes UIKit re-measure all three buttons; nothing is drawn in between. The old "select another tab and come
    /// back" trick only re-measured two of the three tabs (sel 0 → 2 → 0 left "消息" squeezed), hence the regressions.
    /// The bar is checked on every layout / appearance / activation and re-checked after each repair.
    private func settleFloatingTabBar() {
        guard #available(iOS 26.0, *), !settlePending, settleAttempts < 8, tabBarLabelsSqueezed() else { return }
        settlePending = true
        settleAttempts += 1
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.settlePending = false
            guard self.tabBarLabelsSqueezed() else { return }
            UIView.performWithoutAnimation {
                for item in (self.viewControllers ?? []).compactMap({ $0.tabBarItem }) {
                    let title = item.title
                    item.title = (title ?? "") + " "
                    item.title = title
                }
                self.tabBar.layoutIfNeeded()
            }
            // A repair that ran before the platter got its size is caught here and retried (bounded by settleAttempts).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.settleFloatingTabBar() }
        }
    }

    private func tabBarLabelsSqueezed() -> Bool {
        guard isViewLoaded, tabBar.window != nil else { return false }
        var squeezed = false
        func scan(_ view: UIView) {
            if let label = view as? UILabel, let text = label.text, !text.isEmpty, let font = label.font,
               label.bounds.height > 0, label.bounds.height < font.lineHeight - 1 {
                squeezed = true
            }
            view.subviews.forEach(scan)
        }
        scan(tabBar)
        return squeezed
    }

    @objc private func appDidBecomeActive() {
        settleAttempts = 0
        settleFloatingTabBar()
        for delay in [0.15, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.settleFloatingTabBar() }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The three-tab host is a root screen; the baseline navigation bar is not part of V2.
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // Keep edge-swipe back to the baseline screen working while the bar is hidden.
        navigationController?.interactivePopGestureRecognizer?.delegate = nil
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent { navigationController?.setNavigationBarHidden(false, animated: animated) }
    }

    /// Tab bar (design "图标/Tab", `.tabbar`): bgColorBottomBar with a 1px top stroke, 10pt labels
    /// (selected = textColorLink, bold), template glyphs in textColorTertiary, selected glyphs filled
    /// with the palette gradient, count badge in Host.unreadAccent (textColorError).
    private func applyChrome() {
        let tokens = Host.tokens
        view.backgroundColor = Palette.bg
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = tokens.bgColorBottomBar
        appearance.shadowColor = tokens.strokeColorPrimary
        var badgeShift: CGFloat = 4
        if #available(iOS 26.0, *) { badgeShift += (HostMetrics.floatingTabGlyphWidth - HostMetrics.tabIcon) / 2 }
        let normalFont = UIFont.adaptiveSystemFont(ofSize: HostMetrics.tabLabelSize)
        let selectedFont = UIFont.adaptiveSystemFont(ofSize: HostMetrics.tabLabelSize, weight: .bold)
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = tokens.textColorTertiary
            item.normal.titleTextAttributes = [.foregroundColor: tokens.textColorTertiary, .font: normalFont]
            item.selected.iconColor = tokens.textColorLink
            item.selected.titleTextAttributes = [.foregroundColor: tokens.textColorLink, .font: selectedFont]
            item.normal.badgeBackgroundColor = Host.unreadAccent
            item.normal.badgeTextAttributes = [.foregroundColor: tokens.textColorButton, .font: UIFont.adaptiveSystemFont(ofSize: 10, weight: .bold)]
            item.normal.badgePositionAdjustment = UIOffset(horizontal: badgeShift, vertical: -2)
        }
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) { tabBar.scrollEdgeAppearance = appearance }
        tabBar.barTintColor = tokens.bgColorBottomBar
        tabBar.tintColor = tokens.textColorLink
        tabBar.unselectedItemTintColor = tokens.textColorTertiary
        applyTabImages()
    }

    private func applyTabImages() {
        let names = [("home", DemoText.get("demo_home")), ("chat", DemoText.get("demo_messages")), ("mine", DemoText.get("demo_me"))]
        for (index, entry) in names.enumerated() {
            guard let item = viewControllers?[safe: index]?.tabBarItem else { continue }
            item.image = Host.templateTabImage("demo_tab_\(entry.0)")
            item.selectedImage = Host.selectedTabImage(shape: "demo_tab_\(entry.0)_on_shape", detail: "demo_tab_\(entry.0)_on_detail")
        }
    }

    /// Palette or mode changed: rebuild each tab's root screen with the new colours, keeping
    /// pushed screens (e.g. Settings, which refreshes itself) and the selected tab.
    private func rebuildForTheme() {
        guard let navs = viewControllers as? [UINavigationController], navs.count == 3 else { return }
        applyChrome()
        let roots: [UIViewController] = [
            HomeViewController(),
            DemoMessagesController(accountId: accountId, preview: preview),
            MineViewController(accountId: accountId, previewIdentity: previewIdentity)
        ]
        for (nav, root) in zip(navs, roots) {
            nav.setViewControllers([root] + nav.viewControllers.dropFirst(), animated: false)
        }
        applyTabTitles()
        applyDarkNavigation(navs)
        if !preview { loadUnreadBadge() }
    }

    private func applyTabTitles() {
        let titles = [DemoText.get("demo_home"), DemoText.get("demo_messages"), DemoText.get("demo_me")]
        for (item, title) in zip(viewControllers ?? [], titles) { item.tabBarItem.title = title }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyChrome()
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(forName: DemoThemeCoordinator.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildForTheme()
        }
        NotificationCenter.default.addObserver(forName: DemoLanguage.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildForTheme()
        }
        let home = UINavigationController(rootViewController: HomeViewController())
        let messages = UINavigationController(rootViewController: DemoMessagesController(accountId: accountId, preview: preview))
        let mine = UINavigationController(rootViewController: MineViewController(accountId: accountId, previewIdentity: previewIdentity))
        home.tabBarItem = UITabBarItem(title: DemoText.get("demo_home"), image: nil, tag: 0)
        messages.tabBarItem = UITabBarItem(title: DemoText.get("demo_messages"), image: nil, tag: 1)
        mine.tabBarItem = UITabBarItem(title: DemoText.get("demo_me"), image: nil, tag: 2)
        viewControllers = [home, messages, mine]
        [home, messages, mine].forEach { HostNavigationTransition.install(on: $0) }
        delegate = self
        applyTabImages()
        applyDarkNavigation([home, messages, mine])
        if !preview {
            loadUnreadBadge()
            DemoGroupWatcher.shared.ensureStarted(accountId: accountId)
            DemoCallPromoter.shared.ensureStarted()
            DemoMessageBanner.shared.ensureStarted(accountId: accountId)
            DemoMessageBanner.shared.onShown = { [weak self] in self?.bounceMessagesBadge() }
        }
    }

    func bounceMessagesBadge() {
        let buttons = tabBar.subviews
            .filter { String(describing: type(of: $0)).contains("TabBarButton") }
            .sorted { $0.frame.minX < $1.frame.minX }
        guard buttons.count > 1,
              let badge = buttons[1].subviews.first(where: { String(describing: type(of: $0)).contains("Badge") }) else { return }
        Motion.bump(badge)
    }

    /// Shows the Messages tab and opens the sender's 1v1 chat on top of it.
    func openChat(userID: String, title: String? = nil) {
        guard !preview, let nav = viewControllers?[safe: 1] as? UINavigationController else { return }
        selectedIndex = 1
        nav.popToRootViewController(animated: false)
        var info = ConversationInfo(conversationID: "c2c_\(userID)")
        info.type = .c2c
        info.title = title ?? userID
        nav.pushViewController(DemoChat.makePage(conversation: info, onBack: { [weak nav] in
            nav?.popViewController(animated: true)
        }), animated: true)
    }

    /// The bottom Messages tab shows the 消息 segment badge plus the 好友 segment badge, see `DemoBadgeCenter`.
    private func loadUnreadBadge() {
        cancellables.removeAll()
        DemoBadgeCenter.shared.ensureStarted(accountId: accountId)
        DemoBadgeCenter.shared.total
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                guard let self, let item = self.viewControllers?[1].tabBarItem else { return }
                item.badgeValue = count > 0 ? (count > 99 ? "99+" : "\(count)") : nil
                if count > self.shownBadgeCount {
                    DispatchQueue.main.async { self.bounceMessagesBadge() }
                }
                self.shownBadgeCount = count
            }
            .store(in: &cancellables)
    }

    private func applyDarkNavigation(_ controllers: [UINavigationController]) {
        controllers.forEach { nav in
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = Host.tokens.bgColorTopBar
            appearance.titleTextAttributes = [.foregroundColor: Palette.text]
            nav.navigationBar.standardAppearance = appearance
            nav.navigationBar.scrollEdgeAppearance = appearance
            nav.navigationBar.tintColor = Palette.accent
        }
    }
}

// MARK: - Home

final class GreetingGlyphView: UIView {
    private let heartColor: UIColor

    init(heartColor: UIColor) {
        self.heartColor = heartColor
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let scale = min(bounds.width, bounds.height) / 48
        context.scaleBy(x: scale, y: scale)

        UIColor.white.setFill()
        UIBezierPath(roundedRect: CGRect(x: 10, y: 13, width: 28, height: 19), cornerRadius: 9).fill()
        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: 14, y: 30))
        tail.addLine(to: CGPoint(x: 13, y: 37))
        tail.addLine(to: CGPoint(x: 21, y: 31))
        tail.close()
        tail.fill()

        heartColor.setFill()
        heartPath().fill()
    }

    private func heartPath() -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 12, y: 21.35))
        path.addLine(to: CGPoint(x: 10.55, y: 20.03))
        path.addCurve(to: CGPoint(x: 2, y: 8.5), controlPoint1: CGPoint(x: 5.4, y: 15.36), controlPoint2: CGPoint(x: 2, y: 12.28))
        path.addCurve(to: CGPoint(x: 7.5, y: 3), controlPoint1: CGPoint(x: 2, y: 5.42), controlPoint2: CGPoint(x: 4.42, y: 3))
        path.addCurve(to: CGPoint(x: 12, y: 5.09), controlPoint1: CGPoint(x: 9.24, y: 3), controlPoint2: CGPoint(x: 10.91, y: 3.81))
        path.addCurve(to: CGPoint(x: 16.5, y: 3), controlPoint1: CGPoint(x: 13.09, y: 3.81), controlPoint2: CGPoint(x: 14.76, y: 3))
        path.addCurve(to: CGPoint(x: 22, y: 8.5), controlPoint1: CGPoint(x: 19.58, y: 3), controlPoint2: CGPoint(x: 22, y: 5.42))
        path.addCurve(to: CGPoint(x: 13.45, y: 20.04), controlPoint1: CGPoint(x: 22, y: 12.28), controlPoint2: CGPoint(x: 18.6, y: 15.36))
        path.close()
        let k: CGFloat = 0.6
        path.apply(CGAffineTransform(scaleX: k, y: k).concatenating(CGAffineTransform(translationX: 24 - 12 * k, y: 22.5 - 12.17 * k)))
        return path
    }
}

// MARK: - Messages

/// Messages tab (design S1 `527:167`, S2 `527:636`, 好友 S5, 通话记录): header 「消息」 (add friend +
/// light/dark toggle) and segment tabs 消息 / 好友 / 通话.
///  - 消息: search bar, the 「打招呼消息」 entry row (72pt, count badge, chevron; opens the greeting
///    second-level page listing the real conversations that carry the greeting mark), group line,
///    group header 「最近聊天」 and the real one-to-one conversations without it.
///  - 好友: the real friend list (A-Z), only the real 「新的联系人」 entry is kept.
///  - 通话: the SDK's real recent call records (CallStore); tapping a row calls back.
/// No local array stands in for IM data.
private final class DemoMessagesController: DemoTabRootController {
    private let accountId: String
    private let preview: Bool
    /// Holds the three segment pages: each is built once and only slid in / out afterwards (rebuilding re-subscribed
    /// and re-fetched everything and made the screen blink). Tapping a tab slides, a horizontal drag pages.
    private let container = HostSwipePager()
    private var pages: [Int: UIViewController] = [:]
    private var segBar: HostSegBar?
    private var entryDesc: UILabel?
    private var entryBadgeHolder: UIView?
    private var cancellables = Set<AnyCancellable>()
    private var greetingCancellables = Set<AnyCancellable>()
    private var greetingDescText = DemoText.get("demo_no_new_greetings")
    private var greetingUnread = 0
    private var selected = 0

    init(accountId: String, preview: Bool) {
        self.accountId = accountId
        self.preview = preview
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.backButtonDisplayMode = .minimal
        let tokens = Host.tokens
        view.backgroundColor = tokens.bgColorTopBar

        let seg = HostSegBar(titles: [DemoText.get("demo_messages"), DemoText.get("demo_friends"), DemoText.get("demo_calls")], selected: selected) { [weak self] index in
            self?.selected = index
            self?.showSegment(index, animate: true)
        }
        segBar = seg
        container.pageCount = 3
        container.provider = { [weak self] index in
            guard let self else { return UIView() }
            let page: UIViewController
            switch index {
            case 1: page = self.contactsPage()
            case 2: page = DemoCallRecordsController(callReady: true)
            default: page = self.messagesPage()
            }
            self.pages[index] = page
            self.addChild(page)
            return page.view
        }
        container.didAddPage = { [weak self] index, _ in
            guard let self else { return }
            self.pages[index]?.didMove(toParent: self)
        }
        // The tab bar travels with the pages (tap slide, drag and settle), see HostSegBar.setPosition.
        container.onProgress = { [weak self] position in self?.segBar?.setPosition(position) }
        container.onSwiped = { [weak self] index in
            guard let self else { return }
            self.selected = index
            self.pageShown(index)
        }
        // A conversation row opens its action buttons on a left swipe (and closes them on a right one); that drag stays with the row.
        container.yieldDrag = { [weak self] point, _ in
            guard let self, self.selected == 0 else { return false }
            var hit = self.container.hitTest(point, with: nil)
            while let view = hit {
                if view is UITableViewCell { return true }
                hit = view.superview
            }
            return false
        }
        if !preview {
            DemoBadgeCenter.shared.messagesSegment.receive(on: DispatchQueue.main)
                .sink { [weak seg] count in seg?.setBadge(0, count: count) }.store(in: &cancellables)
            DemoBadgeCenter.shared.friendsSegment.receive(on: DispatchQueue.main)
                .sink { [weak seg] count in seg?.setBadge(1, count: count) }.store(in: &cancellables)
        }
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(seg)
        view.addSubview(container)
        NSLayoutConstraint.activate([
            seg.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            seg.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            seg.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.topAnchor.constraint(equalTo: seg.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if preview {
            let notice = label(DemoText.get("demo_preview_mode_im_is_not_logged_in"), 13, tokens.textColorTertiary)
            notice.textAlignment = .center
            notice.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(notice)
            NSLayoutConstraint.activate([notice.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                                         notice.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
                                         notice.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)])
            return
        }
        showSegment(0)
        observeGreetings()
        NotificationCenter.default.publisher(for: DemoGroupDiagnostics.didChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.dropPage(0)
                if self.selected == 0 { self.showSegment(0) }
                self.observeGreetings()
            }
            .store(in: &cancellables)
    }

    /// Forgets a page (and removes it) so the next visit builds it again.
    private func dropPage(_ index: Int) {
        guard let page = pages.removeValue(forKey: index) else { return }
        container.invalidate(index)
        page.willMove(toParent: nil)
        page.removeFromParent()
    }

    private func showSegment(_ index: Int, animate: Bool = false) {
        container.show(index, animate: animate)
        if animate { pageShown(index) }
    }

    /// Call records can change while another screen was on top; the page dedupes, so an unchanged list is not redrawn.
    private func pageShown(_ index: Int) {
        (pages[index] as? DemoCallRecordsController)?.refresh()
    }

    private func openChat(_ info: ConversationInfo, locateMessage: MessageInfo? = nil) {
        let chat = DemoChat.makePage(conversation: info, locateMessage: locateMessage, onBack: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        })
        navigationController?.pushViewController(chat, animated: true)
    }

    private func messagesPage() -> UIViewController {
        let watcher = DemoGroupWatcher.shared
        return ConversationsPage(
            conversationGroup: ConversationGroup.c2c.rawValue,
            exclusion: { watcher.slot(of: $0) != .recent },
            emptyText: DemoGroupDiagnostics.emptyText(DemoText.get("demo_no_recent_messages_yet")),
            showsHeader: false,
            searchPlaceholder: DemoText.get("demo_search_nickname_user_id"),
            listHeaderView: entryBlock(),
            exclusionChanges: watcher.contextChanges,
            titleAccessory: { conversation in
                DemoPeerTags.inline(peerID: Self.peerID(of: conversation.conversationID))
            }
        ) { [weak self] info in
            self?.openChat(info.conversation, locateMessage: info.locateMessage)
        }
    }

    static func peerID(of conversationID: String) -> String {
        conversationID.hasPrefix("c2c_") ? String(conversationID.dropFirst(4)) : conversationID
    }

    private func contactsPage() -> UIViewController {
        ContactsPage(
            config: ChatContactListConfig(showNewContacts: true, showGroupApplications: false, showMyGroups: false,
                                          showBlacklist: true, showSearchBar: true),
            showsHeader: false,
            onContactClick: { [weak self] contact in
                var info = ConversationInfo(conversationID: "c2c_\(contact.userID)")
                info.type = .c2c
                info.title = contact.userID
                self?.openChat(info)
            },
            subtitleAccessory: { userID in DemoPeerTags.inline(peerID: userID) },
            peerTags: { userID in DemoPeerTags.inline(peerID: userID) }
        )
    }

    // MARK: 打招呼消息

    /// Entry row + 1px group line + 「最近聊天」 header, on the list surface (bgColorTopBar).
    private func entryBlock() -> UIView {
        let tokens = Host.tokens
        let block = UIStackView()
        block.axis = .vertical
        block.backgroundColor = tokens.bgColorTopBar

        let icon = UIView()
        icon.layer.cornerRadius = HostMetrics.convAvatar / 2
        icon.clipsToBounds = true
        let gradient = Host.brandGradientLayer(startPoint: .zero, endPoint: CGPoint(x: 1, y: 1))
        gradient.frame = CGRect(x: 0, y: 0, width: HostMetrics.convAvatar, height: HostMetrics.convAvatar)
        icon.layer.addSublayer(gradient)
        let glyph = GreetingGlyphView(heartColor: tokens.buttonColorPrimaryDefault)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        icon.addSubview(glyph)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: HostMetrics.convAvatar),
            icon.heightAnchor.constraint(equalToConstant: HostMetrics.convAvatar),
            glyph.leadingAnchor.constraint(equalTo: icon.leadingAnchor), glyph.trailingAnchor.constraint(equalTo: icon.trailingAnchor),
            glyph.topAnchor.constraint(equalTo: icon.topAnchor), glyph.bottomAnchor.constraint(equalTo: icon.bottomAnchor)
        ])

        let title = label(DemoText.get("demo_greetings"), 18, tokens.textColorPrimary)
        title.numberOfLines = 1
        let desc = label(greetingDescText, 14, tokens.textColorSecondary)
        desc.numberOfLines = 1
        entryDesc = desc
        let mid = UIStackView(arrangedSubviews: [title, desc])
        mid.axis = .vertical
        mid.spacing = 2

        let badgeHolder = UIStackView()
        badgeHolder.axis = .horizontal
        entryBadgeHolder = badgeHolder
        applyGreetingEntry()
        let chevron = Host.icon("demo_ic_chevron", size: 12, tint: tokens.textColorTertiary)

        let row = UIStackView(arrangedSubviews: [icon, mid, UIView(), badgeHolder, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.setCustomSpacing(8, after: badgeHolder)
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 0, left: HostMetrics.screenPaddingH, bottom: 0, right: HostMetrics.screenPaddingH)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: HostMetrics.convItemH).isActive = true
        row.isAccessibilityElement = true
        row.accessibilityLabel = DemoText.get("demo_greetings")
        row.accessibilityTraits = .button
        row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openGreetings)))

        let line = UIView()
        line.backgroundColor = tokens.strokeColorPrimary
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true

        let head = label(DemoText.get("demo_recent_chats"), 13, tokens.textColorTertiary, bold: true)
        let headRow = UIStackView(arrangedSubviews: [head])
        headRow.isLayoutMarginsRelativeArrangement = true
        headRow.layoutMargins = UIEdgeInsets(top: 12, left: HostMetrics.screenPaddingH, bottom: 6, right: HostMetrics.screenPaddingH)

        [row, line, headRow].forEach(block.addArrangedSubview)
        return block
    }

    /// Live count + latest preview from the real greeting group; only valid, unique members count, and the
    /// count spans every page of the group.
    private func observeGreetings() {
        greetingCancellables.removeAll()
        let watcher = DemoGroupWatcher.shared
        watcher.state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] view in
                guard let self else { return }
                let members = watcher.greetingMembers(view)
                let latest = members.max { ($0.lastMessage?.timestamp ?? 0) < ($1.lastMessage?.timestamp ?? 0) }
                self.greetingUnread = DemoBadgeRules.greetingUnread(watcher.badgeCandidates(view))
                if let latest {
                    let name = latest.title ?? ""
                    let summary = DemoMessagesController.summary(of: latest)
                    self.greetingDescText = summary.isEmpty ? name : "\(name)：\(summary)"
                } else {
                    self.greetingDescText = DemoGroupDiagnostics.packageUnsupported
                        ? DemoText.get("demo_conversation_groups_are_unavailable_the_ultimate") : DemoText.get("demo_no_new_greetings")
                }
                self.applyGreetingEntry()
            }
            .store(in: &greetingCancellables)
    }

    /// The entry row is rebuilt on every segment switch, so the last summary is re-applied to it.
    private func applyGreetingEntry() {
        if let desc = entryDesc {
            // 表情消息在 IM 里是「[TUIEmoji_Smile]」这种 key，纯 text 会露出 key；换成把 key 画成表情图的富文本。
            if greetingDescText.contains("[TUIEmoji_") {
                desc.attributedText = ConversationBannerSummary.attributedText(
                    forText: greetingDescText, font: desc.font, color: Host.tokens.textColorSecondary)
            } else {
                desc.text = greetingDescText
            }
        }
        entryBadgeHolder?.subviews.forEach { $0.removeFromSuperview() }
        if greetingUnread > 0, let holder = entryBadgeHolder as? UIStackView {
            holder.addArrangedSubview(Host.badge(greetingUnread))
        }
    }

    private static func summary(of conversation: ConversationInfo) -> String {
        guard let message = conversation.lastMessage else { return "" }
        if ConversationBannerSummary.isCallMessage(message) { return ConversationBannerSummary.text(for: conversation) }
        switch message.messagePayload {
        case .text(let payload): return payload.text
        case .image: return DemoText.get("demo_image")
        case .audio: return DemoText.get("demo_voice")
        case .video: return DemoText.get("demo_video")
        case .file: return DemoText.get("demo_file")
        case .custom(let payload):
            return DemoCardProtocol.summary(DemoCardProtocol.parse(payload.customData))
        default: return DemoText.get("demo_message")
        }
    }

    @objc private func openGreetings() {
        let page = DemoGreetingsController { [weak self] info in
            self?.openChat(info.conversation, locateMessage: info.locateMessage)
        }
        navigationController?.pushViewController(page, animated: true)
    }
}

/// S1b 「打招呼消息」 second-level page: back, title, 「忽略未读」, tip bar and the greeting group list.
private final class DemoGreetingsController: DemoTabRootController {
    private let onOpen: (NavigationInfo) -> Void

    init(onOpen: @escaping (NavigationInfo) -> Void) {
        self.onOpen = onOpen
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let tokens = Host.tokens
        view.backgroundColor = tokens.bgColorTopBar

        let back = UIButton(type: .custom)
        back.setImage(Host.image("demo_hd_back")?.withRenderingMode(.alwaysTemplate), for: .normal)
        back.tintColor = tokens.textColorPrimary
        back.accessibilityLabel = DemoText.get("demo_back")
        back.translatesAutoresizingMaskIntoConstraints = false
        back.widthAnchor.constraint(equalToConstant: 24).isActive = true
        back.heightAnchor.constraint(equalToConstant: 24).isActive = true
        back.addAction(UIAction { [weak self] _ in self?.navigationController?.popViewController(animated: true) }, for: .touchUpInside)

        let readAll = UIButton(type: .system)
        readAll.setTitle(DemoText.get("demo_ignore_unread"), for: .normal)
        readAll.setTitleColor(tokens.textColorLink, for: .normal)
        readAll.titleLabel?.font = .adaptiveSystemFont(ofSize: 14)
        readAll.addAction(UIAction { [weak self] _ in self?.confirmIgnoreUnread() }, for: .touchUpInside)

        let header = HostHeaderView(title: DemoText.get("demo_greetings"), left: back, ops: [readAll])
        let border = UIView()
        border.backgroundColor = tokens.strokeColorSecondary
        border.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(border)

        let tipIcon = Host.icon("demo_ic_heart", size: 14, tint: tokens.tagColorLevel4)
        let tipText = label(DemoText.get("demo_messages_and_calls_from_strangers_land_here"), 12, tokens.textColorSecondary)
        let tip = UIStackView(arrangedSubviews: [tipIcon, tipText])
        tip.axis = .horizontal
        tip.alignment = .center
        tip.spacing = 6
        tip.isLayoutMarginsRelativeArrangement = true
        tip.layoutMargins = UIEdgeInsets(top: 8, left: HostMetrics.screenPaddingH, bottom: 8, right: HostMetrics.screenPaddingH)
        tip.backgroundColor = tokens.bgColorOperate

        let watcher = DemoGroupWatcher.shared
        let page = ConversationsPage(
            exclusion: { watcher.slot(of: $0) != .greeting },
            emptyText: DemoGroupDiagnostics.emptyText(DemoText.get("demo_no_new_greeting_messages")),
            showsHeader: false,
            showsSearchBar: false,
            markType: DemoConversationClassifier.greetingMark,
            exclusionChanges: watcher.contextChanges,
            titleAccessory: { conversation in
                let id = conversation.conversationID
                return DemoPeerTags.inline(peerID: id.hasPrefix("c2c_") ? String(id.dropFirst(4)) : id)
            }
        ) { [weak self] info in self?.onOpen(info) }
        addChild(page)
        page.view.translatesAutoresizingMaskIntoConstraints = false

        let column = UIStackView(arrangedSubviews: [header, tip])
        column.axis = .vertical
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        view.addSubview(page.view)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            border.leadingAnchor.constraint(equalTo: header.leadingAnchor), border.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            border.bottomAnchor.constraint(equalTo: header.bottomAnchor), border.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            page.view.topAnchor.constraint(equalTo: column.bottomAnchor),
            page.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            page.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            page.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        page.didMove(toParent: self)
    }

    /// 有未读数，或被标为未读（只有标记、没有未读数）的打招呼会话，都算“未读”。
    private func unreadTargets() -> [ConversationInfo] {
        DemoGroupWatcher.shared.greetingMembers().filter {
            $0.unreadCount > 0 || $0.conversationMarkList.contains(.unread)
        }
    }

    /// 忽略未读会一次清掉全部打招呼会话的未读，先二次确认；没有可忽略的未读时不弹框。
    private func confirmIgnoreUnread() {
        guard !unreadTargets().isEmpty else { return }
        let alert = UIAlertController(title: DemoText.get("demo_ignore_unread"),
                                      message: DemoText.get("demo_ignore_unread_confirm_message"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: DemoText.get("demo_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: DemoText.get("demo_confirm"), style: .default) { [weak self] _ in
            guard let self else { return }
            // 确认弹框期间会话可能已变化，按点“确定”时的最新状态再取一遍。
            ConversationUnreadClearer.clearConversationsUnread(store: ConversationListStore.create(),
                                                               conversations: self.unreadTargets())
        })
        present(alert, animated: true)
    }
}

/// Process-wide IM profile cache (nickname / avatar by userID).
///
/// The conversation list, the call records and the message banner all show the same peers, so a profile is fetched
/// once per run instead of once per page — which is what let the call list show a userID first and fill in the
/// nickname a moment later.
final class DemoUserProfiles {
    static let shared = DemoUserProfiles()

    private var cache: [String: V2TIMUserFullInfo] = [:]

    func profile(_ userID: String) -> V2TIMUserFullInfo? { cache[userID] }

    /// Fetches whatever is missing; `completion` runs on the main thread, also when the request fails, so a caller
    /// waiting to paint can never be left hanging.
    func load(_ ids: [String], completion: @escaping () -> Void) {
        let missing = Array(Set(ids)).filter { !$0.isEmpty && cache[$0] == nil }
        guard !missing.isEmpty else {
            completion()
            return
        }
        V2TIMManager.sharedInstance().getUsersInfo(missing, succ: { [weak self] infos in
            infos?.forEach { info in
                if let id = info.userID { self?.cache[id] = info }
            }
            DispatchQueue.main.async { completion() }
        }, fail: { _, _ in
            DispatchQueue.main.async { completion() }
        })
    }
}

/// Call records (design 通话 `.call`): 72pt rows with a 48pt avatar, name 18, direction + duration 14
/// (missed in the error colour), time 12 and a primary-coloured call icon. Data comes from the SDK
/// (`CallStore.queryRecentCalls`); names and avatars from the real IM profiles of the peers.
private final class DemoCallRecordsController: UIViewController, UITextFieldDelegate {
    private let callReady: Bool
    private let field = UITextField()
    private var query = ""
    private let list = UIStackView()
    private var records: [CallInfo] = []
    private var profiles: [String: V2TIMUserFullInfo] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let selfID = V2TIMManager.sharedInstance().getLoginUser() ?? ""
    /// Built rows by call id: a row is rebuilt only when what it shows changed, so avatars are not reloaded
    /// every time the call state ticks (which blinked every avatar after coming back from a call).
    private var rowCache: [String: (signature: String, view: UIView)] = [:]

    /// True once the first complete list (nicknames + pictures) is on screen.
    private var ready = false
    private let spinner = UIActivityIndicatorView(style: .medium)
    /// Prefetches at normal priority: the shared prefetcher runs low priority, which can miss the short wait below.
    private let prefetcher = SDWebImagePrefetcher()

    init(callReady: Bool) {
        self.callReady = callReady
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let tokens = Host.tokens
        view.backgroundColor = tokens.bgColorTopBar
        field.font = .adaptiveSystemFont(ofSize: 14)
        field.textColor = tokens.textColorPrimary
        field.tintColor = tokens.buttonColorPrimaryDefault
        field.attributedPlaceholder = NSAttributedString(string: DemoText.get("demo_search_call_records"),
                                                         attributes: [.foregroundColor: tokens.textColorTertiary])
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.clearButtonMode = .whileEditing
        field.delegate = self
        field.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
        let search = UIStackView(arrangedSubviews: [Host.icon("demo_hd_search", size: 16, tint: tokens.textColorSecondary), field])
        search.axis = .horizontal
        search.alignment = .center
        search.spacing = 6
        search.isLayoutMarginsRelativeArrangement = true
        search.layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        search.backgroundColor = tokens.bgColorInput
        search.layer.cornerRadius = HostMetrics.searchBarRadius
        search.translatesAutoresizingMaskIntoConstraints = false
        search.heightAnchor.constraint(equalToConstant: HostMetrics.searchBarH).isActive = true
        let searchWrap = UIView()
        searchWrap.addSubview(search)
        search.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([search.topAnchor.constraint(equalTo: searchWrap.topAnchor, constant: 4),
                                     search.bottomAnchor.constraint(equalTo: searchWrap.bottomAnchor, constant: -12),
                                     search.leadingAnchor.constraint(equalTo: searchWrap.leadingAnchor, constant: HostMetrics.screenPaddingH),
                                     search.trailingAnchor.constraint(equalTo: searchWrap.trailingAnchor, constant: -HostMetrics.screenPaddingH)])

        list.axis = .vertical
        list.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .onDrag
        scroll.showsVerticalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(list)
        searchWrap.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchWrap)
        view.addSubview(scroll)
        prefetcher.options = []
        spinner.color = tokens.buttonColorPrimaryDefault
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            searchWrap.topAnchor.constraint(equalTo: view.topAnchor),
            searchWrap.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchWrap.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: searchWrap.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            list.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            list.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        refresh()
        CallStore.shared.state
            .subscribe()
            .map { $0.recentCalls }
            .removeDuplicates { old, new in Self.recordsSignature(old) == Self.recordsSignature(new) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] calls in
                guard let self else { return }
                self.records = calls.sorted { $0.startTime > $1.startTime }
                self.prepare()
            }
            .store(in: &cancellables)
        // Loading from the start: the store's first emission is often an empty list, which must not flash the
        // "no records yet" text before the real ones arrive.
        spinner.startAnimating()
        // Nothing came back (offline / empty account): show the empty state instead of spinning forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, !self.ready, self.records.isEmpty else { return }
            self.spinner.stopAnimating()
            self.render()
        }
    }

    func refresh() {
        CallStore.shared.queryRecentCalls(cursor: "", count: 0, completion: nil)
    }

    private static func recordsSignature(_ calls: [CallInfo]) -> [String] {
        calls.map { "\($0.callId)|\($0.result.rawValue)|\($0.duration)|\($0.startTime)|\($0.mediaType?.rawValue ?? -1)" }
    }

    @objc private func queryChanged() {
        query = (field.text ?? "").trimmingCharacters(in: .whitespaces)
        render()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    /// Records whose peer nickname or user ID contains the query (case-insensitive).
    private func visibleRecords() -> [CallInfo] {
        guard !query.isEmpty else { return records }
        return records.filter { info in
            let peerID = peer(of: info) ?? ""
            let name = profiles[peerID]?.nickName ?? ""
            return name.localizedCaseInsensitiveContains(query) || peerID.localizedCaseInsensitiveContains(query)
        }
    }

    private func peer(of info: CallInfo) -> String? {
        ([info.inviterId] + info.inviteeIds).first { !$0.isEmpty && $0 != selfID }
    }

    /// The first paint only happens once every peer has a nickname and the avatars are already in the picture cache:
    /// the list used to render with userIDs and letter avatars and then rebuild itself twice, which is what flickered.
    /// Later updates render straight away — the row cache keeps everything that did not change.
    private func prepare() {
        let peers = Array(Set(records.compactMap { peer(of: $0) }))
        if ready {
            peers.forEach { if let profile = DemoUserProfiles.shared.profile($0) { profiles[$0] = profile } }
            render()
            return
        }
        // The first emission of the store is often an empty list: keep the loading state until the timeout above.
        guard !records.isEmpty else { return }
        spinner.startAnimating()
        DemoUserProfiles.shared.load(peers) { [weak self] in
            guard let self else { return }
            peers.forEach { if let profile = DemoUserProfiles.shared.profile($0) { self.profiles[$0] = profile } }
            self.prefetchThenShow(peers: peers)
        }
    }

    private func prefetchThenShow(peers: [String]) {
        guard !ready else {
            render()
            return
        }
        var shown = false
        func show() {
            guard !shown else { return }
            shown = true
            spinner.stopAnimating()
            ready = true
            render()
        }
        let urls = peers.compactMap { profiles[$0]?.faceURL }.compactMap { URL(string: $0) }
        guard !urls.isEmpty else {
            show()
            return
        }
        prefetcher.prefetchURLs(urls, progress: nil) { _, _ in
            DispatchQueue.main.async { show() }
        }
        // A slow picture must not keep the page empty: show the list and let that avatar fill in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { show() }
    }

    private func rowSignature(_ info: CallInfo) -> String {
        let peerID = peer(of: info) ?? ""
        let profile = profiles[peerID]
        return [info.callId, "\(info.result.rawValue)", "\(info.duration)", "\(info.startTime)", "\(info.mediaType?.rawValue ?? -1)",
                peerID, profile?.nickName ?? "", profile?.faceURL ?? ""].joined(separator: "|")
    }

    private func render() {
        let tokens = Host.tokens
        let shown = visibleRecords()
        let keep = Set(shown.map { $0.callId })
        rowCache = rowCache.filter { keep.contains($0.key) }
        var wanted: [UIView] = []
        for (index, info) in shown.enumerated() {
            let signature = rowSignature(info)
            let view: UIView
            if let cached = rowCache[info.callId], cached.signature == signature {
                view = cached.view
            } else {
                view = row(info)
                rowCache[info.callId] = (signature, view)
            }
            wanted.append(view)
            if index < shown.count - 1 { wanted.append(divider()) }
        }
        // Keep the views that stay; only add / remove the difference.
        let wantedSet = Set(wanted.map { ObjectIdentifier($0) })
        for view in list.arrangedSubviews where !wantedSet.contains(ObjectIdentifier(view)) {
            list.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if shown.isEmpty {
            let empty = label(DemoText.get(records.isEmpty ? "demo_no_call_records_yet" : "demo_no_matching_call_records"), 13, tokens.textColorTertiary)
            empty.textAlignment = .center
            let holder = UIStackView(arrangedSubviews: [empty])
            holder.isLayoutMarginsRelativeArrangement = true
            holder.layoutMargins = UIEdgeInsets(top: 48, left: 0, bottom: 48, right: 0)
            list.addArrangedSubview(holder)
            return
        }
        for (position, view) in wanted.enumerated() {
            if position < list.arrangedSubviews.count, list.arrangedSubviews[position] === view { continue }
            if view.superview === list { list.removeArrangedSubview(view); view.removeFromSuperview() }
            list.insertArrangedSubview(view, at: min(position, list.arrangedSubviews.count))
        }
    }

    private func divider() -> UIView {
        let view = UIView()
        let line = UIView()
        line.backgroundColor = Host.tokens.strokeColorPrimary
        line.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(line)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([view.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
                                     line.topAnchor.constraint(equalTo: view.topAnchor), line.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                                     line.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 76),
                                     line.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        return view
    }

    private static func timeText(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "" }
        let date = Date(timeIntervalSince1970: interval > 1_000_000_000_000 ? interval / 1000 : interval)
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if calendar.isDateInToday(date) { formatter.dateFormat = "HH:mm" }
        else if calendar.isDateInYesterday(date) { return DemoText.get("demo_yesterday") }
        else { formatter.dateFormat = DemoText.get("demo_m_d") }
        return formatter.string(from: date)
    }

    private func row(_ info: CallInfo) -> UIView {
        let tokens = Host.tokens
        let peerID = peer(of: info)
        let profile = peerID.flatMap { profiles[$0] }
        let name = (profile?.nickName).flatMap { $0.isEmpty ? nil : $0 } ?? peerID ?? DemoText.get("demo_unknown_user")
        let missed = info.result == .missed
        let video = info.mediaType == .video
        let direction: String
        switch info.result {
        case .missed: direction = DemoText.get("demo_missed_call")
        case .incoming: direction = DemoText.get("demo_incoming_call")
        default: direction = DemoText.get("demo_outgoing_call")
        }
        let seconds = Int(info.duration)
        let duration = seconds > 0 ? " · \(seconds / 60):" + String(format: "%02d", seconds % 60) : ""
        let glyph = video ? "demo_ic_call_video" : "demo_ic_call_voice"
        let tint = missed ? tokens.textColorError : tokens.textColorSecondary

        let avatar = DemoRemoteAvatar(name: name, url: profile?.faceURL, size: HostMetrics.convAvatar)
        let title = label(name, 18, tokens.textColorPrimary)
        title.numberOfLines = 1
        let meta = UIStackView(arrangedSubviews: [Host.icon(glyph, size: 14, tint: tint), label(direction + duration, 14, tint)])
        meta.axis = .horizontal
        meta.alignment = .center
        meta.spacing = 4
        let titleRow = UIStackView(arrangedSubviews: [title])
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 6
        if let peerID, let tags = DemoPeerTags.inline(peerID: peerID) {
            titleRow.addArrangedSubview(tags)
        }
        titleRow.addArrangedSubview(UIView())
        let mid = UIStackView(arrangedSubviews: [titleRow, meta])
        mid.axis = .vertical
        mid.spacing = 2
        let time = label(Self.timeText(info.startTime), 12, tokens.textColorSecondary)
        time.numberOfLines = 1
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        time.setContentHuggingPriority(.required, for: .horizontal)
        mid.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let action = Host.icon(glyph, size: 20, tint: tokens.buttonColorPrimaryDefault)
        let right = UIStackView(arrangedSubviews: [time, action])
        right.setContentCompressionResistancePriority(.required, for: .horizontal)
        right.axis = .vertical
        right.alignment = .trailing
        right.spacing = 6

        let row = UIStackView(arrangedSubviews: [avatar, mid, UIView(), right])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 0, left: HostMetrics.screenPaddingH, bottom: 0, right: HostMetrics.screenPaddingH)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: HostMetrics.convItemH).isActive = true
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(name) \(direction)"
        row.accessibilityTraits = .button
        if let peerID, callReady {
            row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(callBack(_:))))
            objc_setAssociatedObject(row, &Self.callKey, CallTarget(peer: peerID, video: video), .OBJC_ASSOCIATION_RETAIN)
        }
        return row
    }

    private final class CallTarget { let peer: String; let video: Bool; init(peer: String, video: Bool) { self.peer = peer; self.video = video } }
    private static var callKey: UInt8 = 0

    @objc private func callBack(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view, let target = objc_getAssociatedObject(view, &Self.callKey) as? CallTarget else { return }
        ChatCallEventPublisher.publishStartCall(
            participantIDs: [target.peer],
            mediaType: target.video ? .video : .audio
        )
    }
}
