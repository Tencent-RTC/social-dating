import UIKit
import AtomicX
import TUIHostBase

/// Home tab. The grid is a UICollectionView (only the visible cards exist as views), pull-to-refresh replaces the first
/// page, and the next page is requested while the user is still `preloadCards` cards away from the end. Each section
/// keeps its own list, cursor and load state, so switching sections never refetches.
public final class HomeViewController: DemoTabRootController, UICollectionViewDelegate {
    private final class SectionState {
        var cards: [HomeUserCard]
        var cursor: String?
        var loadingMore = false
        var loadMoreFailed = false
        var refreshing = false
        var generation = 0

        init(cards: [HomeUserCard], cursor: String?) {
            self.cards = cards
            self.cursor = cursor
        }
    }

    private enum Block: Int { case head, grid, footer }

    fileprivate enum FooterKind: Hashable { case idle, loading, end, error }

    private enum Item: Hashable {
        case head
        case card(HomeUserCard)
        case footer(FooterKind)
    }

    private static let preloadCards = 6
    private static let staggerLimit = 10

    private var feed: HomeFeed?
    private var states: [String: SectionState] = [:]
    private var activeSection = 0
    private var leaving = false
    private weak var refreshIcon: UIView?
    private let segHolder = UIStackView()
    private let state = HostStateView()
    private let body = UIView()
    private let pager = HostSwipePager()
    private weak var segBar: HostSegBar?
    private var pendingStagger = false

    /// One list per section, built the first time the section is shown and then only hidden / shown again, so a
    /// switch never re-binds cards or reloads avatars and each section keeps its scroll position.
    private final class Page {
        let sectionId: String
        let collection: UICollectionView
        let refreshControl: UIRefreshControl
        var dataSource: UICollectionViewDiffableDataSource<Block, Item>!
        var staggerNext = false

        init(sectionId: String, collection: UICollectionView, refreshControl: UIRefreshControl) {
            self.sectionId = sectionId
            self.collection = collection
            self.refreshControl = refreshControl
        }
    }

    private var pages: [String: Page] = [:]
    private var pageIndexes: [Int: String] = [:]
    private var activePage: Page? { activeId.flatMap { pages[$0] } }

    private func page(of collectionView: UICollectionView) -> Page? {
        pages.values.first { $0.collection === collectionView }
    }

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) { fatalError() }

    private var activeId: String? { feed?.sections[safe: activeSection]?.id }
    private var active: SectionState? { activeId.flatMap { states[$0] } }

    public override func viewDidLoad() {
        super.viewDidLoad()
        ComponentUsage.report(ComponentUsage.socialHome)
        let tokens = Host.tokens
        view.backgroundColor = tokens.bgColorTopBar
        segHolder.axis = .vertical
        state.translatesAutoresizingMaskIntoConstraints = false
        pager.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(pager)
        body.addSubview(state)
        pager.provider = { [weak self] position in self?.makePage(position: position).collection ?? UIView() }
        pager.didAddPage = { [weak self] position, _ in
            guard let self, let id = self.pageIndexes[position], let page = self.pages[id] else { return }
            self.fill(page, stagger: self.pendingStagger)
        }
        // The tab bar travels with the pages (tap slide, drag and settle), see HostSegBar.setPosition.
        pager.onProgress = { [weak self] position in self?.segBar?.setPosition(position) }
        pager.onSwiped = { [weak self] position in
            guard let self else { return }
            self.activeSection = position
            self.updateStateView()
            DispatchQueue.main.async { [weak self] in self?.loadMoreIfNeeded() }
        }
        let column = UIStackView(arrangedSubviews: [segHolder, body])
        column.axis = .vertical
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pager.topAnchor.constraint(equalTo: body.topAnchor), pager.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            pager.leadingAnchor.constraint(equalTo: body.leadingAnchor), pager.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            state.topAnchor.constraint(equalTo: body.topAnchor), state.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            state.leadingAnchor.constraint(equalTo: body.leadingAnchor), state.trailingAnchor.constraint(equalTo: body.trailingAnchor)
        ])
        load()
    }

    // MARK: - Loading

    private func load() {
        state.isUserInteractionEnabled = true
        state.showLoading()
        HomeKit.dataSource.loadFeed { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let loaded):
                    self.pager.reset()
                    self.pages = [:]
                    self.pageIndexes = [:]
                    self.pager.pageCount = loaded.sections.count
                    self.feed = loaded
                    self.states = Dictionary(loaded.sections.map { ($0.id, SectionState(cards: $0.cards, cursor: $0.nextCursor)) },
                                             uniquingKeysWith: { first, _ in first })
                    self.activeSection = 0
                    self.showHeader(loaded)
                    self.showActive(stagger: true)
                case .failure:
                    self.state.isUserInteractionEnabled = true
                    self.state.showError { [weak self] in self?.load() }
                }
            }
        }
    }

    private func showHeader(_ loaded: HomeFeed) {
        segHolder.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let bar = HostSegBar(titles: loaded.sections.map { $0.title }, selected: activeSection, tight: true) { [weak self] index in
            guard let self, index != self.activeSection else { return }
            self.activeSection = index
            // Already built sections slide back in untouched; a new one is built once and slides in.
            self.showActive(stagger: false, animate: true)
        }
        segBar = bar
        segHolder.addArrangedSubview(bar)
    }

    private func leaveThen(_ next: @escaping () -> Void) {
        guard !leaving else { return }
        let cards = (activePage?.collection.visibleCells ?? []).compactMap { $0 as? HomeCardCell }
        guard !cards.isEmpty, Motion.enabled else { return next() }
        leaving = true
        cards.forEach { Motion.cardLeave($0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.leaving = false
            next()
        }
    }

    // MARK: - List state

    private func snapshot(for section: SectionState?) -> NSDiffableDataSourceSnapshot<Block, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Block, Item>()
        snapshot.appendSections([.head])
        snapshot.appendItems([.head], toSection: .head)
        if let section, !section.cards.isEmpty {
            snapshot.appendSections([.grid, .footer])
            snapshot.appendItems(section.cards.map { .card($0) }, toSection: .grid)
            snapshot.appendItems([.footer(footerKind(section))], toSection: .footer)
        }
        return snapshot
    }

    private func footerKind(_ section: SectionState) -> FooterKind {
        if section.loadMoreFailed { return .error }
        if section.loadingMore { return .loading }
        return section.cursor == nil ? .end : .idle
    }

    private func makePage(position: Int) -> Page {
        let sectionId = feed?.sections[safe: position]?.id ?? ""
        pageIndexes[position] = sectionId
        let collection = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.showsVerticalScrollIndicator = false
        collection.delegate = self
        let refresh = UIRefreshControl()
        refresh.tintColor = Host.tokens.textColorTertiary
        refresh.addTarget(self, action: #selector(pulled), for: .valueChanged)
        collection.refreshControl = refresh
        let page = Page(sectionId: sectionId, collection: collection, refreshControl: refresh)
        page.dataSource = makeDataSource(for: page)
        pages[sectionId] = page
        return page
    }

    /// Shows the active section. Its list is built once; later visits only slide it back in (nothing is rebound or
    /// refetched). `stagger` plays the card entrance for a freshly built list, `animate` slides between sections.
    private func showActive(stagger: Bool, animate: Bool = false) {
        pendingStagger = stagger
        pager.show(activeSection, animate: animate)
        updateStateView()
        DispatchQueue.main.async { [weak self] in self?.loadMoreIfNeeded() }
    }

    /// Replaces a section's list with its saved state (first build, pull-to-refresh and 换一批) and scrolls to the top.
    private func fill(_ page: Page, stagger: Bool) {
        view.layoutIfNeeded()
        page.staggerNext = stagger && Motion.enabled
        page.dataSource.applySnapshotUsingReloadData(snapshot(for: states[page.sectionId]))
        page.collection.layoutIfNeeded()
        page.staggerNext = false
        page.collection.setContentOffset(CGPoint(x: 0, y: -page.collection.adjustedContentInset.top), animated: false)
    }

    private func updateStateView() {
        if active?.cards.isEmpty ?? true {
            state.isUserInteractionEnabled = false
            state.showEmpty()
        } else {
            state.hide()
        }
    }

    private func refreshFooter(of page: Page) {
        guard let section = states[page.sectionId], !section.cards.isEmpty else { return }
        var snapshot = page.dataSource.snapshot()
        let old = snapshot.itemIdentifiers(inSection: .footer)
        snapshot.deleteItems(old)
        snapshot.appendItems([.footer(footerKind(section))], toSection: .footer)
        page.dataSource.apply(snapshot, animatingDifferences: false)
    }

    @objc private func pulled() { reload() }

    /// Pull-to-refresh and "换一批" both end here: a fresh first page replaces the list, whatever the outcome.
    private func reload() {
        guard let sectionId = activeId, let section = states[sectionId], !section.refreshing else { return }
        section.refreshing = true
        section.loadingMore = false
        section.loadMoreFailed = false
        section.generation += 1
        HomeKit.dataSource.refresh(sectionId: sectionId) { [weak self] result in
            DispatchQueue.main.async {
                section.refreshing = false
                guard let self else { return }
                switch result {
                case .success(let page):
                    if !page.cards.isEmpty {
                        section.cards = Self.distinct(page.cards)
                        section.cursor = page.nextCursor
                    }
                case .failure:
                    if self.activeId == sectionId { SocialToast.show(DemoText.get("demo_refresh_failed"), kind: .error) }
                }
                if let page = self.pages[sectionId] {
                    page.refreshControl.endRefreshing()
                    self.fill(page, stagger: self.activeId == sectionId)
                    if self.activeId == sectionId { self.updateStateView() }
                }
            }
        }
    }

    private static func distinct(_ cards: [HomeUserCard]) -> [HomeUserCard] {
        var seen = Set<String>()
        return cards.filter { seen.insert($0.id).inserted }
    }

    private func loadMoreIfNeeded() {
        guard let section = active, section.cursor != nil, !section.loadingMore, !section.loadMoreFailed, !section.refreshing,
              !section.cards.isEmpty else { return }
        guard let collection = activePage?.collection else { return }
        let last = collection.indexPathsForVisibleItems.filter { $0.section == Block.grid.rawValue }.map { $0.item }.max() ?? -1
        if last >= 0, last >= section.cards.count - 1 - Self.preloadCards { loadMore() }
    }

    private func loadMore() {
        guard let sectionId = activeId, let section = states[sectionId], let cursor = section.cursor, !section.loadingMore else { return }
        section.loadingMore = true
        section.loadMoreFailed = false
        let generation = section.generation
        if let page = pages[sectionId] { refreshFooter(of: page) }
        HomeKit.dataSource.loadMore(sectionId: sectionId, cursor: cursor) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, generation == section.generation else { return }
                section.loadingMore = false
                switch result {
                case .success(let page):
                    let known = Set(section.cards.map { $0.id })
                    let fresh = Self.distinct(page.cards).filter { !known.contains($0.id) }
                    // A page with nothing new ends the list, so a source that repeats itself cannot loop forever.
                    section.cursor = fresh.isEmpty ? nil : page.nextCursor
                    section.cards += fresh
                case .failure:
                    section.loadMoreFailed = true
                }
                if let page = self.pages[sectionId] {
                    page.dataSource.apply(self.snapshot(for: section), animatingDifferences: false)
                }
                if self.activeId == sectionId {
                    DispatchQueue.main.async { [weak self] in self?.loadMoreIfNeeded() }
                }
            }
        }
    }

    // MARK: - Collection

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { index, env in
            let full = NSCollectionLayoutDimension.fractionalWidth(1)
            switch Block(rawValue: index) ?? .footer {
            case .head:
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: full, heightDimension: .estimated(40)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: full, heightDimension: .estimated(40)), subitems: [item])
                return NSCollectionLayoutSection(group: group)
            case .grid:
                // Exact heights (square photo + a fixed-height text area), so reloads never depend on self-sizing passes.
                let width = (env.container.effectiveContentSize.width - HostMetrics.screenPaddingH * 2 - HostMetrics.userCardGap) / 2
                let height = HomeCardCell.height(forWidth: width)
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(0.5), heightDimension: .absolute(height)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: full, heightDimension: .absolute(height)),
                                                               subitem: item, count: 2)
                group.interItemSpacing = .fixed(HostMetrics.userCardGap)
                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = HostMetrics.userCardGap
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: HostMetrics.screenPaddingH, bottom: 0, trailing: HostMetrics.screenPaddingH)
                return section
            case .footer:
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: full, heightDimension: .estimated(56)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: full, heightDimension: .estimated(56)), subitems: [item])
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: HostMetrics.userCardGap, leading: 0, bottom: 0, trailing: 0)
                return section
            }
        }
    }

    private func makeDataSource(for page: Page) -> UICollectionViewDiffableDataSource<Block, Item> {
        let head = UICollectionView.CellRegistration<UICollectionViewCell, Item> { [weak self] cell, _, _ in
            guard let self else { return }
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            let row = self.sectionHead()
            row.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: cell.contentView.topAnchor), row.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                row.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor), row.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor)
            ])
        }
        let card = UICollectionView.CellRegistration<HomeCardCell, HomeUserCard> { [weak self, weak page] cell, indexPath, user in
            cell.configure(user)
            cell.onOpen = { [weak self] in
                guard let self else { return }
                self.navigationController?.pushViewController(ProfileViewController(userKey: user.id), animated: true)
            }
            if page?.staggerNext == true, indexPath.item < Self.staggerLimit {
                Motion.rowIn(cell, delay: Motion.gridDelay(indexPath.item), duration: Motion.slow)
            }
        }
        let footer = UICollectionView.CellRegistration<HomeFooterCell, FooterKind> { cell, _, kind in
            cell.configure(kind)
        }
        return UICollectionViewDiffableDataSource<Block, Item>(collectionView: page.collection) { view, indexPath, item in
            switch item {
            case .head: return view.dequeueConfiguredReusableCell(using: head, for: indexPath, item: item)
            case .card(let user): return view.dequeueConfiguredReusableCell(using: card, for: indexPath, item: user)
            case .footer(let kind): return view.dequeueConfiguredReusableCell(using: footer, for: indexPath, item: kind)
            }
        }
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard indexPath.section == Block.grid.rawValue, let owner = page(of: collectionView), let section = states[owner.sectionId] else { return }
        // Never mutate the data source from inside a layout pass.
        if indexPath.item >= section.cards.count - 1 - Self.preloadCards {
            DispatchQueue.main.async { [weak self] in self?.loadMoreIfNeeded() }
        }
    }

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        indexPath.section == Block.footer.rawValue && active?.loadMoreFailed == true
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard indexPath.section == Block.footer.rawValue, let section = active, section.loadMoreFailed else { return }
        section.loadMoreFailed = false
        loadMore()
    }

    // MARK: - Head and actions

    private func sectionHead() -> UIView {
        let tokens = Host.tokens
        let refresh = Host.icon("demo_ic_refresh", size: 12, tint: tokens.textColorTertiary)
        refreshIcon = refresh
        let action = UIStackView(arrangedSubviews: [refresh, label(DemoText.get("demo_refresh"), 12, tokens.textColorTertiary)])
        action.axis = .horizontal
        action.alignment = .center
        action.spacing = 4
        action.isAccessibilityElement = true
        action.accessibilityLabel = DemoText.get("demo_refresh")
        action.accessibilityTraits = .button
        action.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shuffle)))
        let row = UIStackView(arrangedSubviews: [label(DemoText.get("demo_recommended_for_you"), 13, tokens.textColorTertiary, bold: true), UIView(), action])
        row.axis = .horizontal
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 10, left: HostMetrics.screenPaddingH, bottom: 8, right: HostMetrics.screenPaddingH)
        row.backgroundColor = tokens.bgColorTopBar
        return row
    }

    @objc private func shuffle() {
        guard let section = active, !section.refreshing, !leaving else { return }
        if Motion.enabled, let icon = refreshIcon {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = CGFloat.pi * 2
            spin.duration = Motion.slow
            icon.layer.add(spin, forKey: "motion.spin")
        }
        leaveThen { [weak self] in self?.reload() }
    }
}

// MARK: - Cells

private final class HomeCardCell: UICollectionViewCell {
    var onOpen: (() -> Void)?

    private let photo = UIImageView()
    private let cityTag = Host.kindTag(.city, "")
    private let heightTag = Host.kindTag(.height, "")
    private let tagsRow = UIStackView()
    private let name = label("", HostMetrics.userCardNameSize, Host.tokens.textColorPrimary, bold: true)
    private let sexSlot = UIView()
    private let meta = label("", HostMetrics.userCardMetaSize, Host.tokens.textColorTertiary)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let tokens = Host.tokens
        contentView.backgroundColor = tokens.bgColorOperate
        contentView.layer.cornerRadius = HostMetrics.cardRadius
        contentView.clipsToBounds = true

        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.backgroundColor = tokens.bgColorFunction
        photo.isUserInteractionEnabled = true
        photo.translatesAutoresizingMaskIntoConstraints = false
        photo.setContentHuggingPriority(.defaultLow, for: .vertical)
        photo.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let mask = HostGradientView(colors: [UIColor.black.withAlphaComponent(0), UIColor.black.withAlphaComponent(0.68)])
        mask.translatesAutoresizingMaskIntoConstraints = false
        photo.addSubview(mask)

        tagsRow.axis = .horizontal
        tagsRow.spacing = 4
        tagsRow.alignment = .center
        tagsRow.translatesAutoresizingMaskIntoConstraints = false
        tagsRow.addArrangedSubview(cityTag)
        tagsRow.addArrangedSubview(heightTag)
        photo.addSubview(tagsRow)

        name.numberOfLines = 1
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sexSlot.setContentHuggingPriority(.required, for: .horizontal)
        let nameRow = UIStackView(arrangedSubviews: [name, UIView(), sexSlot])
        nameRow.axis = .horizontal
        nameRow.alignment = .center
        nameRow.spacing = 4
        meta.numberOfLines = 1
        // The trailing spacer takes any extra height a self-sizing pass may give, so the text never spreads apart.
        let info = UIStackView(arrangedSubviews: [nameRow, meta, UIView()])
        info.axis = .vertical
        info.spacing = 4
        info.isLayoutMarginsRelativeArrangement = true
        info.layoutMargins = UIEdgeInsets(top: 8, left: 10, bottom: 10, right: 10)

        let stack = UIStackView(arrangedSubviews: [photo, info])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor), stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            photo.heightAnchor.constraint(equalTo: photo.widthAnchor),
            mask.leadingAnchor.constraint(equalTo: photo.leadingAnchor), mask.trailingAnchor.constraint(equalTo: photo.trailingAnchor),
            mask.bottomAnchor.constraint(equalTo: photo.bottomAnchor), mask.heightAnchor.constraint(equalToConstant: HostMetrics.userCardMaskH),
            tagsRow.leadingAnchor.constraint(equalTo: photo.leadingAnchor, constant: 8),
            tagsRow.topAnchor.constraint(equalTo: photo.topAnchor, constant: 8)
        ])
        contentView.onTap { [weak self] in self?.onOpen?() }
    }

    required init?(coder: NSCoder) { fatalError() }

    private static var measured: [CGFloat: CGFloat] = [:]

    /// Height of a card of this width: the square photo plus the text area, measured once from a real cell.
    static func height(forWidth width: CGFloat) -> CGFloat {
        let key = width.rounded()
        if let cached = measured[key] { return cached }
        let cell = HomeCardCell(frame: CGRect(x: 0, y: 0, width: key, height: 400))
        cell.configure(HomeUserCard(id: "", userId: "", displayName: "Aa", age: 20, sex: "f", city: "Aa", distanceKm: 1,
                                    height: 170, tags: ["Aa"], activity: "Aa", bio: "", photo: "", avatar: ""))
        cell.contentView.layoutIfNeeded()
        let fit = cell.contentView.systemLayoutSizeFitting(CGSize(width: key, height: UIView.layoutFittingCompressedSize.height),
                                                           withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let value = ceil(fit.height)
        measured[key] = value
        return value
    }

    func configure(_ card: HomeUserCard) {
        resetMotion()
        HostImage.bind(photo, ref: card.photo)
        photo.accessibilityLabel = card.displayName
        let heightText = card.height > 0 ? DemoText.get("demo_height_cm", "\(card.height)") : ""
        cityTag.text = card.city
        cityTag.isHidden = card.city.isEmpty
        heightTag.text = heightText
        heightTag.isHidden = heightText.isEmpty
        tagsRow.isHidden = card.city.isEmpty && heightText.isEmpty
        name.text = card.displayName
        sexSlot.subviews.forEach { $0.removeFromSuperview() }
        let tag = Host.sexTag(sex: card.sex, age: card.age)
        tag.translatesAutoresizingMaskIntoConstraints = false
        sexSlot.addSubview(tag)
        NSLayoutConstraint.activate([
            tag.topAnchor.constraint(equalTo: sexSlot.topAnchor), tag.bottomAnchor.constraint(equalTo: sexSlot.bottomAnchor),
            tag.leadingAnchor.constraint(equalTo: sexSlot.leadingAnchor), tag.trailingAnchor.constraint(equalTo: sexSlot.trailingAnchor)
        ])
        meta.text = (card.tags + (card.activity.isEmpty ? [] : [card.activity])).joined(separator: " · ")
    }

    private func resetMotion() {
        layer.removeAllAnimations()
        alpha = 1
        transform = .identity
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        resetMotion()
        onOpen = nil
    }
}

private final class HomeFooterCell: UICollectionViewCell {
    private var heightConstraint: NSLayoutConstraint?
    private let text = label("", 12, Host.tokens.textColorTertiary)

    override init(frame: CGRect) {
        super.init(frame: frame)
        text.textAlignment = .center
        text.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(text)
        let height = contentView.heightAnchor.constraint(equalToConstant: 24)
        height.priority = .defaultHigh
        heightConstraint = height
        NSLayoutConstraint.activate([
            height,
            text.centerXAnchor.constraint(equalTo: contentView.centerXAnchor), text.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            text.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            text.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    fileprivate func configure(_ kind: HomeViewController.FooterKind) {
        switch kind {
        case .idle:
            text.text = nil
            heightConstraint?.constant = 24
        case .loading:
            text.text = DemoText.get("demo_loading")
            heightConstraint?.constant = 56
        case .error:
            text.text = DemoText.get("demo_load_failed_tap_to_retry")
            heightConstraint?.constant = 56
        case .end:
            text.text = DemoText.get("demo_no_more_people")
            heightConstraint?.constant = 56
        }
        isAccessibilityElement = kind != .idle
        accessibilityLabel = text.text
        accessibilityTraits = kind == .error ? .button : .staticText
    }
}
