import UIKit
import AtomicX
import TUIHostBase

/// Horizontally paged photo strip for the profile cover; a tap anywhere opens the album.
/// With more than one photo it is an endless loop: the strip holds a clone of the last photo in front and a
/// clone of the first behind, and the offset is moved by one lap when a clone is reached, so the slide always
/// moves forward. Auto play runs its own eased animation on a display link; a drag takes over immediately.
final class CoverPager: UIScrollView, UIScrollViewDelegate {
    /// Continuous circular page position in `0..<count`; drives the indicator on every frame.
    var onProgress: ((CGFloat) -> Void)?
    private let onTap: () -> Void
    private let pageCount: Int
    private var looping: Bool { pageCount > 1 }
    private var autoTimer: Timer?
    private var link: CADisplayLink?
    private var slideStart: CFTimeInterval = 0
    private var slideFrom: CGFloat = 0
    private var positioned = false
    private static let autoInterval: TimeInterval = 2.5
    private static let slideDuration: CFTimeInterval = 0.8

    init(photos: [String], onTap: @escaping () -> Void) {
        self.onTap = onTap
        self.pageCount = photos.count
        super.init(frame: .zero)
        isPagingEnabled = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bounces = false
        isDirectionalLockEnabled = true
        delegate = self
        let strip = UIStackView()
        strip.axis = .horizontal
        strip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(strip)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            strip.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            strip.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            strip.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor)
        ])
        let names = looping ? [photos[photos.count - 1]] + photos + [photos[0]] : photos
        for name in names {
            let photo = ProfileUI.photo(name)
            photo.translatesAutoresizingMaskIntoConstraints = false
            strip.addArrangedSubview(photo)
            photo.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor).isActive = true
        }
        isAccessibilityElement = true
        accessibilityLabel = DemoText.get("demo_view_album")
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        autoTimer?.invalidate()
        link?.invalidate()
    }

    @objc private func tapped() { onTap() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard looping, !positioned, bounds.width > 0 else { return }
        positioned = true
        contentOffset = CGPoint(x: bounds.width, y: 0)
    }

    func startAutoPlay() {
        stopAutoPlay()
        guard looping else { return }
        let timer = Timer(timeInterval: Self.autoInterval, repeats: false) { [weak self] _ in self?.slide() }
        autoTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopAutoPlay() {
        autoTimer?.invalidate()
        autoTimer = nil
        cancelSlide()
    }

    private func slide() {
        autoTimer = nil
        guard looping, bounds.width > 0, !isTracking, !isDragging, !isDecelerating, link == nil else { return startAutoPlay() }
        slideFrom = (contentOffset.x / bounds.width).rounded() * bounds.width
        slideStart = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step() {
        let t = min(1, (CACurrentMediaTime() - slideStart) / Self.slideDuration)
        let eased = CGFloat(-(cos(.pi * t) - 1) / 2)
        contentOffset = CGPoint(x: slideFrom + bounds.width * eased, y: 0)
        if t >= 1 {
            cancelSlide()
            startAutoPlay()
        }
    }

    private func cancelSlide() {
        link?.invalidate()
        link = nil
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let width = bounds.width
        guard width > 0, pageCount > 0 else { return }
        guard looping else {
            onProgress?(0)
            return
        }
        let lap = CGFloat(pageCount) * width
        var x = contentOffset.x
        if x <= 0 {
            x += lap
            contentOffset.x = x
        } else if x >= lap + width {
            x -= lap
            contentOffset.x = x
        }
        let count = CGFloat(pageCount)
        let position = (x / width - 1).truncatingRemainder(dividingBy: count)
        onProgress?(position < 0 ? position + count : position)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { stopAutoPlay() }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { startAutoPlay() }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { startAutoPlay() }
    }
}

/// Cover page indicator. Every item is a 6pt dot that widens to a 14pt accent pill by the weight it has at the
/// pager's continuous (circular) position, and the neighbours are pushed aside so the gap stays 5pt. The weights of
/// the two items around the position always add up to one, so the total width is constant and the pill morphs from
/// one dot into the next, including the wrap from the last item back to the first, instead of jumping.
final class CoverIndicator: UIView {
    var count: Int = 0 {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }
    var progress: CGFloat = 0 {
        didSet { relayoutItems() }
    }

    private let dot: CGFloat = 6
    private let gap: CGFloat = 5
    private let pillWidth: CGFloat = 14
    private var items: [CALayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        let n = CGFloat(max(count, 1))
        return CGSize(width: n * dot + (n - 1) * gap + (pillWidth - dot), height: dot)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if items.count != count {
            items.forEach { $0.removeFromSuperlayer() }
            items = (0..<count).map { _ in
                let layer = CALayer()
                layer.cornerRadius = dot / 2
                self.layer.addSublayer(layer)
                return layer
            }
        }
        relayoutItems()
    }

    private func relayoutItems() {
        guard !items.isEmpty else { return }
        let idle = UIColor.white.withAlphaComponent(0.4)
        let accent = Host.tokens.buttonColorPrimaryDefault
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var x: CGFloat = 0
        for (index, layer) in items.enumerated() {
            let weight = weight(of: index)
            let width = dot + (pillWidth - dot) * weight
            layer.frame = CGRect(x: x, y: 0, width: width, height: dot)
            layer.backgroundColor = Self.blend(idle, accent, weight).cgColor
            x += width + gap
        }
        CATransaction.commit()
    }

    private func weight(of index: Int) -> CGFloat {
        let n = CGFloat(count)
        var distance = abs(progress - CGFloat(index))
        distance = min(distance, n - distance)
        return min(1, max(0, 1 - distance))
    }

    private static func blend(_ from: UIColor, _ to: UIColor, _ t: CGFloat) -> UIColor {
        var a: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var b: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        from.getRed(&a.0, green: &a.1, blue: &a.2, alpha: &a.3)
        to.getRed(&b.0, green: &b.1, blue: &b.2, alpha: &b.3)
        return UIColor(red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t,
                       blue: a.2 + (b.2 - a.2) * t, alpha: a.3 + (b.3 - a.3) * t)
    }
}

/// Shared pieces of the other-person profile (design B5) and its album / posts sub page (B6).
/// Pure view builders: all data is passed in by the caller, no IM or data source access.
enum ProfileUI {
    static var tokens: ColorTokens { Host.tokens }

    static func photo(_ name: String, radius: CGFloat = 0) -> UIView {
        Host.photo(name, radius: radius)
    }

    /// `.playbadge`: black 45% disc with a white play glyph.
    static func playBadge(_ diameter: CGFloat) -> UIView {
        let disc = UIView()
        disc.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        disc.layer.cornerRadius = diameter / 2
        disc.translatesAutoresizingMaskIntoConstraints = false
        let glyph = Host.icon("demo_ic_play", size: diameter / 2, tint: .white)
        disc.addSubview(glyph)
        NSLayoutConstraint.activate([
            disc.widthAnchor.constraint(equalToConstant: diameter), disc.heightAnchor.constraint(equalToConstant: diameter),
            glyph.centerXAnchor.constraint(equalTo: disc.centerXAnchor), glyph.centerYAnchor.constraint(equalTo: disc.centerYAnchor)
        ])
        return disc
    }

    /// `.thumb`: photo tile with an optional centred play badge.
    static func thumb(_ name: String, radius: CGFloat, videoBadge: CGFloat = 0, onTap: (() -> Void)? = nil) -> UIView {
        let tile = photo(name, radius: radius)
        if videoBadge > 0 {
            let badge = playBadge(videoBadge)
            tile.addSubview(badge)
            NSLayoutConstraint.activate([badge.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
                                         badge.centerYAnchor.constraint(equalTo: tile.centerYAnchor)])
        }
        if let onTap {
            tile.isAccessibilityElement = true
            tile.accessibilityLabel = DemoText.get("demo_photo")
            tile.onTap(onTap)
        }
        return tile
    }

    /// `.blockhead`: bold 16 title + count (8pt gap) and a 12pt 「全部」 link.
    static func blockHead(_ title: String, count: Int, onAll: (() -> Void)?) -> UIView {
        let t = label(title, 16, tokens.textColorPrimary, bold: true)
        let n = label("\(count)", 16, tokens.textColorPrimary, bold: true)
        let all = UIButton(type: .system)
        all.setTitle(DemoText.get("demo_all"), for: .normal)
        all.setTitleColor(tokens.textColorSecondary, for: .normal)
        all.titleLabel?.font = .adaptiveSystemFont(ofSize: 12)
        all.accessibilityLabel = DemoText.get("demo_view_all", "\(title)")
        all.addAction(UIAction { _ in onAll?() }, for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [t, n, UIView()] + (onAll == nil ? [] : [all]))
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        return row
    }

    /// `.itag`: h26 r13, level colour at 16% fill with the level colour as ink.
    static func interestTag(_ text: String, level: Int) -> UIView {
        let color = [tokens.tagColorLevel1, tokens.tagColorLevel2, tokens.tagColorLevel3, tokens.tagColorLevel4][max(1, min(4, level)) - 1]
        let tag = DemoPaddedLabel()
        tag.insets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        tag.text = text
        tag.font = .adaptiveSystemFont(ofSize: 12)
        tag.textColor = color
        tag.backgroundColor = color.withAlphaComponent(0.16)
        tag.layer.cornerRadius = 13
        tag.clipsToBounds = true
        tag.translatesAutoresizingMaskIntoConstraints = false
        tag.heightAnchor.constraint(equalToConstant: 26).isActive = true
        tag.setContentHuggingPriority(.required, for: .horizontal)
        return tag
    }

    /// `.sextag--solid` textual (B5): 「女 23」, h20 r10, the age token at 92% (same fill as every solid tag), bold 11.
    static func solidSexTag(sex: String, age: Int) -> UIView {
        let tag = DemoPaddedLabel()
        tag.insets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        tag.text = "\(sex == "m" ? DemoText.get("demo_male") : DemoText.get("demo_female")) \(age)"
        tag.font = .adaptiveSystemFont(ofSize: 11, weight: .bold)
        tag.textColor = tokens.textColorButton
        tag.textAlignment = .center
        tag.backgroundColor = Host.tagAccent(Host.ageKind(sex: sex)).withAlphaComponent(0.92)
        tag.layer.cornerRadius = 10
        tag.clipsToBounds = true
        tag.translatesAutoresizingMaskIntoConstraints = false
        tag.heightAnchor.constraint(equalToConstant: 20).isActive = true
        tag.setContentHuggingPriority(.required, for: .horizontal)
        return tag
    }

    /// `.ident__voice`: h36 pill, four-bar glyph and 「听听我的声音  8s」 in the link colour.
    /// Tap plays a silent preview (see `VoiceSignaturePill`); `onPlay` runs when a preview starts.
    static func voiceButton(seconds: Int, onPlay: @escaping () -> Void = {}) -> UIView {
        VoiceSignaturePill(seconds: seconds, onPlay: onPlay)
    }

    /// `.post`: avatar 40 + name / 实名 / sub, text, 172pt photo, topic pill, like / comment / 私聊.
    static func postCard(card: HomeUserCard, post: HomeProfilePost, onComment: (() -> Void)? = nil) -> UIView {
        let box = UIView()
        box.backgroundColor = tokens.bgColorOperate
        box.layer.cornerRadius = HostMetrics.cardRadius

        let name = label(card.displayName, 14, tokens.textColorPrimary, bold: true)
        name.numberOfLines = 1
        let nameRow = UIStackView(arrangedSubviews: [name, Host.verifiedTag(DemoText.get("demo_verified"))])
        nameRow.axis = .horizontal
        nameRow.alignment = .center
        nameRow.spacing = 5
        let nameCol = UIStackView(arrangedSubviews: [nameRow, label(post.sub, 11, tokens.textColorTertiary)])
        nameCol.axis = .vertical
        nameCol.alignment = .leading
        nameCol.spacing = 3
        let head = UIStackView(arrangedSubviews: [Host.sampleAvatar(card.avatar, name: card.displayName, size: 40), nameCol])
        head.axis = .horizontal
        head.alignment = .center
        head.spacing = 10

        let body = label("", 14, tokens.textColorPrimary)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3.5
        body.attributedText = NSAttributedString(string: post.text, attributes: [
            .font: UIFont.adaptiveSystemFont(ofSize: 14), .foregroundColor: tokens.textColorPrimary, .paragraphStyle: para])

        let column = UIStackView(arrangedSubviews: [head, body])
        column.axis = .vertical
        column.spacing = 10
        column.alignment = .fill
        if let first = post.photos.first {
            let image = photo(first, radius: 10)
            image.translatesAutoresizingMaskIntoConstraints = false
            image.heightAnchor.constraint(equalToConstant: 172).isActive = true
            column.addArrangedSubview(image)
        }
        if !post.topic.isEmpty {
            let ink = Host.isDark ? Host.lerp(tokens.tagColorLevel3, .white, 0.25) : tokens.tagColorLevel3
            let topic = DemoPaddedLabel()
            topic.insets = UIEdgeInsets(top: 0, left: 9, bottom: 0, right: 10)
            topic.text = post.topic
            topic.font = .adaptiveSystemFont(ofSize: 11)
            topic.textColor = ink
            topic.backgroundColor = tokens.tagColorLevel3.withAlphaComponent(0.15)
            topic.layer.cornerRadius = 12
            topic.clipsToBounds = true
            topic.translatesAutoresizingMaskIntoConstraints = false
            topic.heightAnchor.constraint(equalToConstant: 24).isActive = true
            let holder = UIStackView(arrangedSubviews: [topic, UIView()])
            holder.axis = .horizontal
            column.addArrangedSubview(holder)
        }

        // Like is a local toggle only; nothing is sent anywhere.
        var liked = false
        var likes = post.likes
        let dim = tokens.textColorPrimary.withAlphaComponent(0.4)
        let likeIcon = Host.icon("demo_ic_like", size: 15, tint: dim)
        let likeCount = label("\(likes)", 12, tokens.textColorTertiary)
        let like = UIStackView(arrangedSubviews: [likeIcon, likeCount])
        like.axis = .horizontal
        like.alignment = .center
        like.spacing = 5
        like.isAccessibilityElement = true
        like.accessibilityLabel = DemoText.get("demo_like")
        like.onTap {
            liked.toggle()
            likes += liked ? 1 : -1
            likeCount.text = "\(likes)"
            likeCount.textColor = liked ? tokens.tagColorLevel4 : tokens.textColorTertiary
            likeIcon.image = Host.image(liked ? "demo_ic_like_on" : "demo_ic_like")?.withRenderingMode(.alwaysTemplate)
            likeIcon.tintColor = liked ? tokens.tagColorLevel4 : dim
        }
        let comment = UIStackView(arrangedSubviews: [Host.icon("demo_ic_comment", size: 15, tint: dim),
                                                     label("\(post.comments)", 12, tokens.textColorTertiary)])
        comment.axis = .horizontal
        comment.alignment = .center
        comment.spacing = 5
        if let onComment { comment.onTap(onComment) }

        let ops = UIStackView(arrangedSubviews: [like, comment, UIView()])
        ops.axis = .horizontal
        ops.alignment = .center
        ops.spacing = 28
        column.addArrangedSubview(ops)

        column.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            column.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
            column.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            column.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12)
        ])
        return box
    }
}

/// Other-person profile (design B5 `527:2357`): header with back + name, square
/// cover (bottom mask, page dots), identity block (name, 女 23, 实名, meta, voice sign,
/// bio, interest tags), 缘分值 row, four facts, album preview and the sticky 去聊天 / 视频聊聊 bar.
public final class ProfileViewController: DemoSubPageController {
    private let userKey: String
    private let fromChat: Bool
    private var card: HomeUserCard!
    private var profile: HomeUserDetail?
    private var friendButton: FriendActionButton?
    private var friendNow = false
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let state = HostStateView()
    private var coverPager: CoverPager?

    public init(userKey: String, fromChat: Bool = false) {
        self.userKey = userKey
        self.fromChat = fromChat
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    public required init?(coder: NSCoder) { fatalError() }

    private var tokens: ColorTokens { Host.tokens }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        coverPager?.startAutoPlay()
        refreshFriendAction()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        coverPager?.stopAutoPlay()
        super.viewWillDisappear(animated)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = tokens.bgColorTopBar
        load()
    }

    private func load() {
        view.subviews.forEach { $0.removeFromSuperview() }
        let header = HostHeaderView(title: "", left: backButton())
        state.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(state)
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor), header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            state.topAnchor.constraint(equalTo: header.bottomAnchor), state.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            state.leadingAnchor.constraint(equalTo: view.leadingAnchor), state.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        if let cached = HomeKit.cachedDetail(userKey) { return show(cached) }
        state.showLoading()
        HomeKit.dataSource.loadUserDetail(userKey: userKey) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let detail):
                    HomeKit.cacheDetail(self.userKey, detail)
                    self.show(detail)
                case .failure:
                    self.state.showError { [weak self] in self?.load() }
                }
            }
        }
    }

    private func show(_ detail: HomeUserDetail) {
        card = detail.card
        profile = detail
        view.subviews.forEach { $0.removeFromSuperview() }
        for subview in stack.arrangedSubviews { subview.removeFromSuperview() }
        buildPage()
    }

    private func buildPage() {
        let action = FriendActionButton()
        action.render(friend: false)
        action.isHidden = true
        action.addAction(UIAction { [weak self] _ in self?.onFriendAction() }, for: .touchUpInside)
        friendButton = action
        let header = HostHeaderView(title: card.displayName, left: backButton(), ops: [action])
        refreshFriendAction()

        let bar = stickyBar()
        scroll.backgroundColor = tokens.bgColorDefault
        scroll.showsVerticalScrollIndicator = false
        stack.axis = .vertical
        for item in [header, scroll, bar, stack] { item.translatesAutoresizingMaskIntoConstraints = false }
        scroll.addSubview(stack)
        view.addSubview(scroll)
        view.addSubview(bar)
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor), header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor)
        ])

        stack.addArrangedSubview(cover())
        stack.addArrangedSubview(identity())
        if let profile {
            if profile.matchScore > 0 {
                stack.addArrangedSubview(gap())
                stack.addArrangedSubview(matchRow(profile))
            }
            if !profile.facts.isEmpty { stack.addArrangedSubview(facts(profile)) }
            if !profile.albumPhotos.isEmpty {
                stack.addArrangedSubview(gap())
                stack.addArrangedSubview(albumPreview(profile))
            }
            stack.addArrangedSubview(gap())
            stack.addArrangedSubview(moments(profile))
        }
        let tail = UIView()
        tail.translatesAutoresizingMaskIntoConstraints = false
        tail.heightAnchor.constraint(equalToConstant: 16).isActive = true
        stack.addArrangedSubview(tail)
    }

    private func gap() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 8).isActive = true
        return view
    }

    private func inset(_ content: UIView, _ insets: UIEdgeInsets, background: UIColor? = nil) -> UIView {
        let wrapper = UIView()
        wrapper.backgroundColor = background
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -insets.bottom),
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -insets.right)
        ])
        return wrapper
    }

    /// Cover pages: the card photo first, then the first three album photos (4 pages in total, as in the design).
    private func coverPages() -> [String] {
        var seen = Set<String>()
        return ([card.photo] + Array((profile?.albumPhotos ?? []).prefix(3))).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// `.cover`: square swipeable photo pager, 140pt bottom mask, one page dot per photo.
    private func cover() -> UIView {
        let container = UIView()
        container.backgroundColor = tokens.bgColorFunction
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        let pages = coverPages().isEmpty ? [card.photo] : coverPages()
        let pager = CoverPager(photos: pages) { [weak self] in self?.openAlbum() }
        pager.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pager)
        Host.pin(pager, to: container)
        DispatchQueue.main.async { Motion.kenBurns(pager) }
        let mask = HostGradientView(colors: [UIColor(white: 0, alpha: 0), UIColor(red: 5 / 255, green: 3 / 255, blue: 13 / 255, alpha: 0.88)])
        mask.translatesAutoresizingMaskIntoConstraints = false
        mask.isUserInteractionEnabled = false
        container.addSubview(mask)
        NSLayoutConstraint.activate([
            mask.leadingAnchor.constraint(equalTo: container.leadingAnchor), mask.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mask.bottomAnchor.constraint(equalTo: container.bottomAnchor), mask.heightAnchor.constraint(equalToConstant: 140)
        ])
        let dots = CoverIndicator()
        dots.count = pages.count
        dots.isHidden = pages.count < 2
        dots.translatesAutoresizingMaskIntoConstraints = false
        pager.onProgress = { [weak dots] position in dots?.progress = position }
        container.addSubview(dots)
        NSLayoutConstraint.activate([dots.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                                     dots.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)])
        coverPager = pager
        return container
    }

    /// `.ident`: padding 14/16/16, gap 8 on the top-bar surface.
    private func identity() -> UIView {
        let name = label(card.displayName, 22, tokens.textColorPrimary, bold: true)
        name.numberOfLines = 1
        let heightTag = Host.kindTag(.height, card.height > 0 ? DemoText.get("demo_height_cm", "\(card.height)") : "",
                                     height: 20, radius: 10, textSize: 11)
        heightTag.isHidden = card.height <= 0
        let nameRow = UIStackView(arrangedSubviews: [name, ProfileUI.solidSexTag(sex: card.sex, age: card.age), heightTag,
                                                     Host.verifiedTag(DemoText.get("demo_verified")), UIView()])
        nameRow.axis = .horizontal
        nameRow.alignment = .center
        nameRow.spacing = 8
        let rawMeta = (profile?.meta.isEmpty == false) ? profile!.meta : card.city
        let metaText = rawMeta.components(separatedBy: " · ").filter { part in
            !(part.hasSuffix("km") && Double(part.dropLast(2)) != nil)
        }.joined(separator: " · ")
        let column = UIStackView(arrangedSubviews: [nameRow, label(metaText, 12, tokens.textColorSecondary)])
        column.axis = .vertical
        column.spacing = 8
        if let profile, profile.voiceSeconds > 0 {
            column.addArrangedSubview(ProfileUI.voiceButton(seconds: profile.voiceSeconds))
        }
        let bio = label("", 14, tokens.textColorPrimary)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3.5
        bio.attributedText = NSAttributedString(string: (profile?.bio.isEmpty == false) ? profile!.bio : card.bio, attributes: [
            .font: UIFont.adaptiveSystemFont(ofSize: 14), .foregroundColor: tokens.textColorPrimary, .paragraphStyle: para])
        column.addArrangedSubview(bio)
        if let interests = profile?.interests, !interests.isEmpty {
            let row = UIStackView(arrangedSubviews: interests.map { ProfileUI.interestTag($0.text, level: $0.level) } + [UIView()])
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            column.addArrangedSubview(row)
        }
        return inset(column, UIEdgeInsets(top: 14, left: 16, bottom: 16, right: 16), background: tokens.bgColorTopBar)
    }

    /// `.matchrow`: warning-tinted 「缘分值 92」 pill + sentence.
    private func matchRow(_ profile: HomeUserDetail) -> UIView {
        let pill = DemoPaddedLabel()
        pill.insets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        pill.text = DemoText.get("demo_match", "\(profile.matchScore)")
        pill.font = .adaptiveSystemFont(ofSize: 11, weight: .bold)
        pill.textColor = tokens.textColorWarning
        pill.backgroundColor = tokens.textColorWarning.withAlphaComponent(0.16)
        pill.layer.cornerRadius = 12
        pill.clipsToBounds = true
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.heightAnchor.constraint(equalToConstant: 24).isActive = true
        pill.setContentHuggingPriority(.required, for: .horizontal)
        let text = label(profile.matchText, 12, tokens.textColorSecondary)
        text.numberOfLines = 1
        let row = UIStackView(arrangedSubviews: [pill, text])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        return inset(row, UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16), background: tokens.bgColorTopBar)
    }

    /// `.facts`: four equal columns, value 16 bold over label 11 tertiary.
    private func facts(_ profile: HomeUserDetail) -> UIView {
        let row = UIStackView(arrangedSubviews: profile.facts.map { fact in
            let column = UIStackView(arrangedSubviews: [label(fact.value, 16, tokens.textColorPrimary, bold: true),
                                                        label(fact.label, 11, tokens.textColorTertiary)])
            column.axis = .vertical
            column.alignment = .center
            column.spacing = 4
            return column
        })
        row.axis = .horizontal
        row.distribution = .fillEqually
        return inset(row, UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16), background: tokens.bgColorTopBar)
    }

    /// `.albumprev`: 「相册 12」 head + 4 thumbs (h76, r8, gap 8), the third carries a 24pt play badge.
    private func albumPreview(_ profile: HomeUserDetail) -> UIView {
        let thumbs = UIStackView(arrangedSubviews: profile.albumPhotos.prefix(4).enumerated().map { index, name in
            let tile = ProfileUI.thumb(name, radius: 8, videoBadge: index == 2 ? 24 : 0) { [weak self] in self?.openAlbum() }
            tile.translatesAutoresizingMaskIntoConstraints = false
            tile.heightAnchor.constraint(equalToConstant: 76).isActive = true
            return tile
        })
        thumbs.axis = .horizontal
        thumbs.distribution = .fillEqually
        thumbs.spacing = 8
        let column = UIStackView(arrangedSubviews: [
            ProfileUI.blockHead(DemoText.get("demo_album"), count: profile.albumCount) { [weak self] in self?.openAlbum() }, thumbs])
        column.axis = .vertical
        column.spacing = 10
        return inset(column, UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16), background: tokens.bgColorTopBar)
    }

    /// `.plist`: 「动态 N」 head (no 「全部」 link, the posts live right here) then post cards or the empty line.
    private func moments(_ profile: HomeUserDetail) -> UIView {
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 10
        column.addArrangedSubview(ProfileUI.blockHead(DemoText.get("demo_moments"), count: profile.posts.count, onAll: nil))
        if profile.posts.isEmpty {
            let empty = label(DemoText.get("demo_they_haven_t_posted_any_moments_yet"), 12, tokens.textColorTertiary)
            empty.textAlignment = .center
            column.addArrangedSubview(inset(empty, UIEdgeInsets(top: 28, left: 0, bottom: 28, right: 0)))
        }
        for post in profile.posts {
            column.addArrangedSubview(ProfileUI.postCard(card: card, post: post, onComment: { [weak self] in
                guard let self else { return }
                HomeKit.actions.commentTapped(from: self, user: self.card, post: post)
            }))
        }
        return inset(column, UIEdgeInsets(top: 14, left: 16, bottom: 16, right: 16), background: tokens.bgColorTopBar)
    }

    /// `.stickyops`: 去聊天 (function surface) and 视频聊聊 (brand), 44pt pills.
    private func stickyBar() -> UIView {
        func button(_ title: String, fill: UIColor, ink: UIColor, action: @escaping () -> Void) -> UIButton {
            let button = UIButton(type: .custom)
            button.setTitle(title, for: .normal)
            button.setTitleColor(ink, for: .normal)
            button.titleLabel?.font = .adaptiveSystemFont(ofSize: 16, weight: .bold)
            button.backgroundColor = fill
            button.layer.cornerRadius = 22
            button.accessibilityLabel = title
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            return button
        }
        let row = UIStackView(arrangedSubviews: [
            button(DemoText.get("demo_go_chat"), fill: tokens.bgColorFunction, ink: tokens.textColorPrimary) { [weak self] in self?.openChat() },
            button(DemoText.get("demo_video_chat"), fill: tokens.buttonColorPrimaryDefault, ink: tokens.textColorButton) { [weak self] in self?.videoChat() }])
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12
        let bar = UIView()
        bar.backgroundColor = tokens.bgColorTopBar
        row.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: bar.topAnchor, constant: 10),
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
        return bar
    }

    private func openAlbum() {
        navigationController?.pushViewController(AlbumViewController(userKey: userKey), animated: true)
    }

    /// Non-friend: send the preset friend request. Friend: the grey「已是好友」asks before deleting.
    private func onFriendAction() {
        guard let user = card else { return }
        if friendNow {
            confirmDeleteFriend(user)
        } else {
            HomeKit.actions.addFriend(from: self, user: user) { [weak self] outcome in
                guard let self, outcome == .added else { return }
                // Set the state directly: the friend list may not have synced yet for a re-query.
                self.friendNow = true
                self.friendButton?.render(friend: true, animate: true)
            }
        }
    }

    private func confirmDeleteFriend(_ user: HomeUserCard) {
        let alert = UIAlertController(
            title: DemoText.get("demo_delete_friend"),
            message: DemoText.get("demo_delete_friend_message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: DemoText.get("demo_delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            HomeKit.actions.deleteFriend(from: self, user: user) { [weak self] deleted in
                guard let self, deleted else { return }
                // Same as the add path: reflect the known state instead of re-querying before sync.
                self.friendNow = false
                self.friendButton?.render(friend: false, animate: true)
            }
        })
        alert.addAction(UIAlertAction(title: DemoText.get("demo_cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func refreshFriendAction() {
        guard let button = friendButton, let user = card else { return }
        guard !user.userId.isEmpty else {
            button.isHidden = true
            return
        }
        HomeKit.actions.isFriend(user: user) { [weak self, weak button] friend in
            DispatchQueue.main.async {
                guard let self, let button else { return }
                self.friendNow = friend
                button.render(friend: friend)
                button.isHidden = false
            }
        }
    }

    private func openChat() {
        if fromChat {
            navigationController?.popViewController(animated: true)
        } else {
            HomeKit.actions.openChat(from: self, user: card)
        }
    }

    private func videoChat() {
        HomeKit.actions.videoChat(from: self, user: card)
    }
}

/// Profile header right action, icon only (Ardot board M, shortened): a 32pt disc inside a 36pt touch area.
/// Not a friend: brand gradient disc + person-with-plus; friend: quiet function disc + person with a green check.
/// Colours come from the semantic tokens, so every palette and light/dark mode follows.
final class FriendActionButton: UIControl {
    private static let touchSize: CGFloat = 36
    private static let discSize: CGFloat = 32
    private static let iconSize: CGFloat = 18
    /// The icon paths are drawn on a 24-unit grid (same as the Android vectors) and scaled to `iconSize`.
    private static let unit = iconSize / 24

    private let disc = CAGradientLayer()
    private let personLayer = CAShapeLayer()
    private let badgeLayer = CAShapeLayer()
    private var shownFriend: Bool?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.touchSize).isActive = true
        heightAnchor.constraint(equalToConstant: Self.touchSize).isActive = true
        isAccessibilityElement = true
        accessibilityTraits = .button
        disc.startPoint = CGPoint(x: 0, y: 0.5)
        disc.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(disc)
        for icon in [personLayer, badgeLayer] {
            icon.fillColor = nil
            icon.lineWidth = 2.2 * Self.unit
            icon.lineCap = .round
            icon.lineJoin = .round
            layer.addSublayer(icon)
        }
        personLayer.path = Self.personPath().cgPath
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let discInset = (Self.touchSize - Self.discSize) / 2
        disc.frame = CGRect(x: discInset, y: discInset, width: Self.discSize, height: Self.discSize)
        disc.cornerRadius = Self.discSize / 2
        let iconInset = (Self.touchSize - Self.iconSize) / 2
        for icon in [personLayer, badgeLayer] {
            icon.frame = CGRect(x: iconInset, y: iconInset, width: Self.iconSize, height: Self.iconSize)
        }
    }

    /// Shows the add / friend state; `animate` plays the short pop used when the state flips after a tap.
    func render(friend: Bool, animate: Bool = false) {
        let changed = shownFriend != nil && shownFriend != friend
        shownFriend = friend
        let tokens = Host.tokens
        accessibilityLabel = DemoText.get(friend ? "demo_already_friends" : "demo_add_friend")
        if friend {
            disc.colors = [tokens.bgColorFunction.cgColor, tokens.bgColorFunction.cgColor]
            personLayer.strokeColor = tokens.textColorSecondary.cgColor
            badgeLayer.path = Self.checkPath().cgPath
            badgeLayer.strokeColor = tokens.textColorSuccess.cgColor
        } else {
            disc.colors = [tokens.buttonColorPrimaryDefault.cgColor, tokens.tagColorLevel4.cgColor]
            personLayer.strokeColor = tokens.textColorButton.cgColor
            badgeLayer.path = Self.plusPath().cgPath
            badgeLayer.strokeColor = tokens.textColorButton.cgColor
        }
        if animate && changed && Motion.enabled { pop() }
    }

    private func pop() {
        transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.16, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: []) {
            self.transform = .identity
        }
        let badgePop = CASpringAnimation(keyPath: "transform.scale")
        badgePop.fromValue = 0.8
        badgePop.toValue = 1
        badgePop.damping = 10
        badgePop.duration = badgePop.settlingDuration
        badgeLayer.add(badgePop, forKey: "pop")
    }

    private static func scaled(_ path: UIBezierPath) -> UIBezierPath {
        path.apply(CGAffineTransform(scaleX: unit, y: unit))
        return path
    }

    private static func personPath() -> UIBezierPath {
        let path = UIBezierPath(arcCenter: CGPoint(x: 9.5, y: 8), radius: 3.8, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        path.move(to: CGPoint(x: 2.5, y: 20.5))
        path.addCurve(to: CGPoint(x: 9.5, y: 14.3), controlPoint1: CGPoint(x: 2.5, y: 16.8), controlPoint2: CGPoint(x: 5.6, y: 14.3))
        path.addCurve(to: CGPoint(x: 16.5, y: 20.5), controlPoint1: CGPoint(x: 13.4, y: 14.3), controlPoint2: CGPoint(x: 16.5, y: 16.8))
        return scaled(path)
    }

    private static func plusPath() -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 19.5, y: 7))
        path.addLine(to: CGPoint(x: 19.5, y: 13))
        path.move(to: CGPoint(x: 16.5, y: 10))
        path.addLine(to: CGPoint(x: 22.5, y: 10))
        return scaled(path)
    }

    private static func checkPath() -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 16.2, y: 11.4))
        path.addLine(to: CGPoint(x: 18.8, y: 14.1))
        path.addLine(to: CGPoint(x: 23.1, y: 9.1))
        return scaled(path)
    }
}

/// Voice signature pill. Tap starts a silent preview: the four bars bounce, a link-tinted fill sweeps the pill from
/// the leading edge over `seconds` and the label counts down; tapping again (or the end) resets it.
final class VoiceSignaturePill: UIView {
    private let seconds: Int
    private let onPlay: () -> Void
    private let fill = UIView()
    private let bars = UIStackView()
    private let text = UILabel()
    private var barViews: [UIView] = []
    private var fillWidth: NSLayoutConstraint?
    private var timer: Timer?
    private var started = Date()
    private var isPlaying = false

    init(seconds: Int, onPlay: @escaping () -> Void) {
        self.seconds = seconds
        self.onPlay = onPlay
        super.init(frame: .zero)
        let tokens = Host.tokens
        backgroundColor = tokens.bgColorFunction
        layer.cornerRadius = 18
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = DemoText.get("demo_voice_signature")
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 36).isActive = true

        fill.backgroundColor = tokens.textColorLink.withAlphaComponent(0.18)
        fill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fill)
        let width = fill.widthAnchor.constraint(equalToConstant: 0)
        fillWidth = width
        NSLayoutConstraint.activate([fill.leadingAnchor.constraint(equalTo: leadingAnchor),
                                     fill.topAnchor.constraint(equalTo: topAnchor),
                                     fill.bottomAnchor.constraint(equalTo: bottomAnchor), width])

        bars.axis = .horizontal
        bars.alignment = .center
        bars.spacing = 1.5
        bars.isLayoutMarginsRelativeArrangement = true
        bars.layoutMargins = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        for height in [4, 9, 6, 8] as [CGFloat] {
            let bar = UIView()
            bar.backgroundColor = tokens.textColorLink
            bar.layer.cornerRadius = 1
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.widthAnchor.constraint(equalToConstant: 2).isActive = true
            bar.heightAnchor.constraint(equalToConstant: height).isActive = true
            bars.addArrangedSubview(bar)
            barViews.append(bar)
        }
        bars.translatesAutoresizingMaskIntoConstraints = false
        text.font = .adaptiveSystemFont(ofSize: 12)
        text.textColor = tokens.textColorLink
        text.numberOfLines = 1
        text.translatesAutoresizingMaskIntoConstraints = false
        renderLabel(seconds)
        addSubview(bars)
        addSubview(text)
        NSLayoutConstraint.activate([
            bars.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            bars.centerYAnchor.constraint(equalTo: centerYAnchor),
            bars.widthAnchor.constraint(equalToConstant: 16), bars.heightAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: bars.trailingAnchor, constant: 8),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        onTap { [weak self] in self?.toggle() }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { timer?.invalidate() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { reset() }
    }

    private func renderLabel(_ remaining: Int) {
        text.text = DemoText.get("demo_listen_to_my_voice_s", "\(remaining)")
    }

    private func toggle() {
        if isPlaying { return reset() }
        isPlaying = true
        onPlay()
        started = Date()
        if Motion.enabled { startBounce() }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let elapsed = Date().timeIntervalSince(started)
        let fraction = min(1, elapsed / Double(seconds))
        if Motion.enabled { fillWidth?.constant = bounds.width * CGFloat(fraction) }
        renderLabel(max(0, Int(ceil(Double(seconds) * (1 - fraction)))))
        if fraction >= 1 { reset() }
    }

    private func startBounce() {
        for (index, bar) in barViews.enumerated() {
            let pulse = CABasicAnimation(keyPath: "transform.scale.y")
            pulse.fromValue = 0.5
            pulse.toValue = 1.7
            pulse.duration = 0.32 + Double(index) * 0.07
            pulse.beginTime = CACurrentMediaTime() + Double(index) * 0.09
            pulse.fillMode = .backwards
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.layer.add(pulse, forKey: "voice.bounce")
        }
    }

    private func reset() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        barViews.forEach { $0.layer.removeAnimation(forKey: "voice.bounce") }
        fillWidth?.constant = 0
        renderLabel(seconds)
    }
}

/// Ice-breaker card (design board M `702:271`): the first item of a 1v1 chat. It is not an IM message: it never counts as
/// unread, never enters the conversation summary and has no long-press menu. Pure view builder, all data comes from
/// `HomeUserDetail` (mock fixtures for now, no IM access). Mirrors Android `IcebreakerCard`.
///
/// The returned view fills the frame its host gives it (one third of the chat page, see `ChatPage.setMessageListHeader`).
public enum IcebreakerCard {
    /// Basic facts shown on the card: height, education, hometown. The income fact (index 2) stays on the profile page.
    private static let factIndexes = [0, 1, 3]
    private static let maxTags = 3
    private static let maxThumbs = 3

    public struct Actions {
        public var onProfile: () -> Void
        public var onAlbum: () -> Void
        public var onVoicePlay: () -> Void

        public init(onProfile: @escaping () -> Void, onAlbum: @escaping () -> Void, onVoicePlay: @escaping () -> Void = {}) {
            self.onProfile = onProfile
            self.onAlbum = onAlbum
            self.onVoicePlay = onVoicePlay
        }
    }

    /// True when there is enough to show; a card with no photo and no facts is hidden by the host instead.
    public static func hasContent(_ detail: HomeUserDetail) -> Bool {
        !detail.card.photo.isEmpty && (!detail.facts.isEmpty || !detail.interests.isEmpty)
    }

    public static func build(detail: HomeUserDetail, actions: Actions) -> UIView {
        let tokens = Host.tokens
        let card = detail.card

        // Left column: portrait that takes the remaining height + a row of three album thumbnails.
        let portrait = ProfileUI.photo(card.photo, radius: 14)
        portrait.isAccessibilityElement = true
        portrait.accessibilityLabel = card.displayName
        portrait.onTap(actions.onProfile)
        let left = UIStackView(arrangedSubviews: [portrait])
        left.axis = .vertical
        left.spacing = 8
        if !detail.albumPhotos.isEmpty {
            left.addArrangedSubview(thumbRow(detail, actions))
        }

        // Right column.
        let name = label(card.displayName, HostMetrics.userCardNameSize, tokens.textColorPrimary, bold: true)
        name.numberOfLines = 1
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let nameRow = UIStackView(arrangedSubviews: card.age > 0 ? [name, ProfileUI.solidSexTag(sex: card.sex, age: card.age), UIView()] : [name, UIView()])
        nameRow.axis = .horizontal
        nameRow.alignment = .center
        nameRow.spacing = 6

        let right = UIStackView(arrangedSubviews: [nameRow])
        right.axis = .vertical
        right.alignment = .fill
        let sub = subtitle(detail)
        if !sub.isEmpty {
            let line = label(sub, 12, tokens.textColorSecondary)
            line.numberOfLines = 1
            right.addArrangedSubview(line)
            right.setCustomSpacing(4, after: nameRow)
        }
        let facts = factIndexes.compactMap { detail.facts.indices.contains($0) ? detail.facts[$0] : nil }
        if !facts.isEmpty {
            let row = FitRow(chips: facts.map { fact in
                let chip = DemoPaddedLabel()
                chip.insets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
                chip.text = fact.value
                chip.font = .adaptiveSystemFont(ofSize: 11)
                chip.textColor = tokens.textColorSecondary
                chip.textAlignment = .center
                chip.backgroundColor = tokens.bgColorFunction
                chip.layer.cornerRadius = 10
                chip.clipsToBounds = true
                chip.translatesAutoresizingMaskIntoConstraints = false
                chip.heightAnchor.constraint(equalToConstant: 20).isActive = true
                return chip
            })
            right.addArrangedSubview(spaced(row, height: 20))
            right.setCustomSpacing(8, after: right.arrangedSubviews[right.arrangedSubviews.count - 2])
        }
        if !detail.interests.isEmpty {
            let row = FitRow(chips: detail.interests.prefix(maxTags).map { ProfileUI.interestTag($0.text, level: $0.level) })
            right.addArrangedSubview(spaced(row, height: 26))
            right.setCustomSpacing(6, after: right.arrangedSubviews[right.arrangedSubviews.count - 2])
        }
        if detail.matchScore > 0 || !detail.matchText.isEmpty {
            right.addArrangedSubview(commonBox(detail))
            right.setCustomSpacing(8, after: right.arrangedSubviews[right.arrangedSubviews.count - 2])
        }
        let flexible = UIView()
        flexible.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
        flexible.setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
        right.addArrangedSubview(flexible)
        if detail.voiceSeconds > 0 {
            let pill = ProfileUI.voiceButton(seconds: detail.voiceSeconds, onPlay: actions.onVoicePlay)
            let holder = UIView()
            holder.addSubview(pill)
            pill.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                pill.leadingAnchor.constraint(equalTo: holder.leadingAnchor), pill.topAnchor.constraint(equalTo: holder.topAnchor, constant: 8),
                pill.bottomAnchor.constraint(equalTo: holder.bottomAnchor), pill.trailingAnchor.constraint(equalTo: holder.trailingAnchor)
            ])
            right.addArrangedSubview(holder)
        }

        let body = UIView()
        body.backgroundColor = tokens.bgColorEntryCard
        body.layer.cornerRadius = 20
        body.layer.borderWidth = 1
        body.layer.borderColor = tokens.strokeColorPrimary.cgColor
        body.translatesAutoresizingMaskIntoConstraints = false
        [left, right].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            body.addSubview($0)
        }
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 14),
            left.topAnchor.constraint(equalTo: body.topAnchor, constant: 14),
            left.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -14),
            left.widthAnchor.constraint(equalToConstant: 124),
            right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 12),
            right.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -14),
            right.topAnchor.constraint(equalTo: body.topAnchor, constant: 14),
            right.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -14)
        ])

        // A small pill, so the line stays readable over any chat background (the light theme keeps the dark starry one).
        let hint = DemoPaddedLabel()
        hint.insets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        hint.text = DemoText.get("demo_icebreaker_hint")
        hint.font = .adaptiveSystemFont(ofSize: 12)
        hint.textColor = tokens.textColorSecondary
        hint.textAlignment = .center
        hint.numberOfLines = 1
        hint.backgroundColor = tokens.bgColorEntryCard
        hint.layer.cornerRadius = 12
        hint.clipsToBounds = true
        hint.translatesAutoresizingMaskIntoConstraints = false

        let root = UIView()
        root.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.addSubview(body)
        root.addSubview(hint)
        let pad = CGFloat(HostMetrics.screenPaddingH)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -pad),
            body.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            hint.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 8),
            hint.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: pad),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -pad),
            hint.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6)
        ])
        return root
    }

    /// 「深圳 · 巨蟹座 · 独立音乐人」: the profile meta without the leading distance segment.
    private static func subtitle(_ detail: HomeUserDetail) -> String {
        let raw = detail.meta.isEmpty ? detail.card.city : detail.meta
        return raw.components(separatedBy: " · ")
            .filter { $0.range(of: "^\\d+(\\.\\d+)?km$", options: .regularExpression) == nil }
            .joined(separator: " · ")
    }

    private static func spaced(_ view: UIView, height: CGFloat) -> UIView {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    /// Three 36x40 album thumbnails; when the album holds more, the last carries a 50% scrim with 「+N」.
    private static func thumbRow(_ detail: HomeUserDetail, _ actions: Actions) -> UIView {
        let shown = Array(detail.albumPhotos.prefix(maxThumbs))
        let more = detail.albumCount - shown.count
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        for (index, name) in shown.enumerated() {
            let tile = ProfileUI.photo(name, radius: 8)
            tile.isAccessibilityElement = true
            tile.accessibilityLabel = DemoText.get("demo_album")
            if index == shown.count - 1, more > 0 {
                let scrim = UILabel()
                scrim.text = "+\(more)"
                scrim.font = .adaptiveSystemFont(ofSize: 12, weight: .bold)
                scrim.textColor = .white
                scrim.textAlignment = .center
                scrim.backgroundColor = UIColor.black.withAlphaComponent(0.5)
                scrim.translatesAutoresizingMaskIntoConstraints = false
                tile.addSubview(scrim)
                Host.pin(scrim, to: tile)
            }
            tile.onTap(actions.onAlbum)
            row.addArrangedSubview(tile)
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return row
    }

    /// Common-ground box: a 「缘分 88」 capsule and the one-line reason.
    private static func commonBox(_ detail: HomeUserDetail) -> UIView {
        let tokens = Host.tokens
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6
        if detail.matchScore > 0 {
            let pill = DemoPaddedLabel()
            pill.insets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
            pill.text = DemoText.get("demo_icebreaker_match", "\(detail.matchScore)")
            pill.font = .adaptiveSystemFont(ofSize: 11, weight: .bold)
            pill.textColor = tokens.textColorWarning
            pill.textAlignment = .center
            pill.backgroundColor = tokens.textColorWarning.withAlphaComponent(0.16)
            pill.layer.cornerRadius = 8
            pill.clipsToBounds = true
            pill.translatesAutoresizingMaskIntoConstraints = false
            pill.heightAnchor.constraint(equalToConstant: 16).isActive = true
            pill.setContentHuggingPriority(.required, for: .horizontal)
            pill.setContentCompressionResistancePriority(.required, for: .horizontal)
            row.addArrangedSubview(pill)
        }
        if !detail.matchText.isEmpty {
            let text = label(detail.matchText, 12, tokens.textColorPrimary)
            text.numberOfLines = 2
            row.addArrangedSubview(text)
        }
        let box = UIView()
        box.backgroundColor = tokens.bgColorFunction
        box.layer.cornerRadius = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8), row.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: box.topAnchor, constant: 6), row.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -6)
        ])
        return box
    }

    /// Horizontal row that hides the chips that no longer fit, so a narrow phone drops the last chip instead of clipping it.
    private final class FitRow: UIStackView {
        private let chips: [UIView]

        init(chips: [UIView]) {
            self.chips = chips
            super.init(frame: .zero)
            axis = .horizontal
            alignment = .center
            spacing = 6
            chips.forEach(addArrangedSubview)
            addArrangedSubview(UIView())
        }

        required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            var used: CGFloat = 0
            var full = false
            for chip in chips {
                let width = chip.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
                let need = used + width
                if full || need > bounds.width {
                    full = true
                    if !chip.isHidden { chip.isHidden = true }
                } else {
                    if chip.isHidden { chip.isHidden = false }
                    used = need + spacing
                }
            }
            super.layoutSubviews()
        }
    }
}
