import UIKit
import SnapKit
import AtomicX

protocol MessageInputMorePanelDelegate: AnyObject {
    func morePanelDidSelectAlbum()
    func morePanelDidSelectCamera()
    func morePanelDidSelectVideo()
    func morePanelDidSelectFile()
    func morePanelDidSelectVideoCall()
    func morePanelDidSelectAudioCall()
}

/// "More" panel: 4 x 2 tiles per page, horizontally paged with page dots, matching the
/// Android `MoreActionsPanelView` and design E4. The panel height stays fixed by the host,
/// so actions beyond one page are reachable by swiping instead of being clipped.
final class MessageInputMorePanel: UIView {
    weak var delegate: MessageInputMorePanelDelegate?

    /// Called after a tap cleared an item's red dot, so the owner can refresh the
    /// more button's own dot.
    var onRedDotDismissed: (() -> Void)?

    var hasVisibleRedDot: Bool {
        return actions.contains { $0.showRedDot && !dismissedRedDotIDs.contains($0.ID) }
    }

    func performAction(id: String) -> Bool {
        guard let action = actions.first(where: { $0.ID == id }) else { return false }
        action.onClick()
        return true
    }

    var bottomSafeAreaInset: CGFloat = 0 {
        didSet {
            guard bottomSafeAreaInset != oldValue else { return }
            pageControlBottomConstraint?.update(inset: Self.pageControlBottomPadding + bottomSafeAreaInset)
        }
    }

    private let config: MessageInputConfigProtocol

    fileprivate static let columns = 4

    fileprivate static let rowsPerPage = 2

    fileprivate static var pageSize: Int { columns * rowsPerPage }

    fileprivate static let iconSize: CGFloat = 56

    fileprivate static let iconTileCornerRadius: CGFloat = CGFloat(RadiusScheme.alertRadius)

    fileprivate static let iconGlyphSize: CGFloat = 28

    fileprivate static let redDotSize: CGFloat = 8

    fileprivate static let titleTopSpacing: CGFloat = CGFloat(SpacingScheme.iconTextSpacing)

    fileprivate static let titleAreaHeight: CGFloat = 20

    fileprivate static let rowSpacing: CGFloat = 14

    fileprivate static let panelPadding: CGFloat = CGFloat(SpacingScheme.bubbleSpacing)

    fileprivate static let pageControlHeight: CGFloat = 14

    fileprivate static let pageControlBottomPadding: CGFloat = 6

    /// "NEW" pill (design E4): 15pt high, rises 6pt above the tile, overhangs its end edge.
    fileprivate static let badgeHeight: CGFloat = 15

    fileprivate static let badgeRise: CGFloat = 6

    fileprivate static let badgeOverhang: CGFloat = 6

    private let scrollView = UIScrollView()

    private let pageControl = UIPageControl()

    private var pageControlBottomConstraint: Constraint?

    private var tiles: [MorePanelTileView] = []

    private var actions: [MessageInputMenuAction] = []

    private var dismissedRedDotIDs: Set<String> = []

    init(config: MessageInputConfigProtocol) {
        self.config = config
        super.init(frame: .zero)
        setupActions()
        setupView()
        rebuildTiles()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupActions() {
        var defaults: [MessageInputMenuAction] = [
            MessageInputMenuAction(
                ID: MessageInputActionIDs.album,
                title: LocalizedChatString("MorePhoto"),
                iconName: "more_picture",
                onClick: { [weak self] in self?.delegate?.morePanelDidSelectAlbum() }
            )
        ]
        if config.isShowPhotoTaker {
            defaults.append(MessageInputMenuAction(
                ID: MessageInputActionIDs.takePhoto,
                title: LocalizedChatString("MoreCamera"),
                iconName: "more_camera",
                onClick: { [weak self] in self?.delegate?.morePanelDidSelectCamera() }
            ))
            defaults.append(MessageInputMenuAction(
                ID: MessageInputActionIDs.recordVideo,
                title: LocalizedChatString("MoreVideo"),
                iconName: "more_video",
                onClick: { [weak self] in self?.delegate?.morePanelDidSelectVideo() }
            ))
        }
        defaults.append(MessageInputMenuAction(
            ID: MessageInputActionIDs.file,
            title: LocalizedChatString("MoreFile"),
            iconName: "more_file",
            onClick: { [weak self] in self?.delegate?.morePanelDidSelectFile() }
        ))
        if config.isShowVideoCall {
            defaults.append(MessageInputMenuAction(
                ID: MessageInputActionIDs.videoCall,
                title: LocalizedChatString("MoreVideoCall"),
                iconName: "more_video_call",
                onClick: { [weak self] in self?.delegate?.morePanelDidSelectVideoCall() }
            ))
        }
        if config.isShowAudioCall {
            defaults.append(MessageInputMenuAction(
                ID: MessageInputActionIDs.audioCall,
                title: LocalizedChatString("MoreVoiceCall"),
                iconName: "more_voice_call",
                onClick: { [weak self] in self?.delegate?.morePanelDidSelectAudioCall() }
            ))
        }
        if let customizer = config.actionCustomizer {
            let editor = CustomEditor(items: defaults)
            customizer(editor)
            actions = editor.build()
        } else {
            actions = defaults
        }
    }

    private func setupView() {
        let colors = TUIChatKitTheme.colors
        backgroundColor = colors.bgColorOperate
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.clipsToBounds = false
        scrollView.delegate = self
        addSubview(scrollView)
        pageControl.isUserInteractionEnabled = false
        pageControl.pageIndicatorTintColor = colors.textColorDisable
        // Same as Android until the S05 brand palette exists (design: buttonColorPrimary).
        pageControl.currentPageIndicatorTintColor = colors.textColorPrimary
        pageControl.hidesForSinglePage = true
        addSubview(pageControl)
        clipsToBounds = true

        scrollView.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(Self.panelPadding + Self.badgeRise)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(Self.pageHeight)
        }
        pageControl.snp.makeConstraints { make in
            make.top.greaterThanOrEqualTo(scrollView.snp.bottom).offset(4)
            make.centerX.equalToSuperview()
            make.height.equalTo(Self.pageControlHeight)
            pageControlBottomConstraint = make.bottom.lessThanOrEqualToSuperview()
                .inset(Self.pageControlBottomPadding).constraint
        }
    }

    fileprivate static var rowHeight: CGFloat { iconSize + titleTopSpacing + titleAreaHeight }

    fileprivate static var pageHeight: CGFloat { rowHeight * CGFloat(rowsPerPage) + rowSpacing }

    private func rebuildTiles() {
        tiles.forEach { $0.removeFromSuperview() }
        tiles = actions.enumerated().map { index, action in
            let tile = MorePanelTileView()
            tile.configure(
                icon: action.icon ?? AtomicXChatResources.image(named: action.iconName),
                title: action.title,
                fullBleed: action.fullBleedIcon,
                showRedDot: action.showRedDot && !dismissedRedDotIDs.contains(action.ID),
                badge: dismissedRedDotIDs.contains(action.ID) ? nil : action.badgeText
            )
            tile.tag = index
            tile.addTarget(self, action: #selector(handleTileTap(_:)), for: .touchUpInside)
            scrollView.addSubview(tile)
            return tile
        }
        pageControl.numberOfPages = max(1, Int(ceil(Double(actions.count) / Double(Self.pageSize))))
        pageControl.currentPage = 0
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pageWidth = scrollView.bounds.width
        guard pageWidth > 0 else { return }
        let inset = Self.panelPadding
        let itemWidth = floor((pageWidth - inset * 2) / CGFloat(Self.columns))
        for (index, tile) in tiles.enumerated() {
            let page = index / Self.pageSize
            let slot = index % Self.pageSize
            let column = slot % Self.columns
            let row = slot / Self.columns
            tile.frame = CGRect(
                x: CGFloat(page) * pageWidth + inset + CGFloat(column) * itemWidth,
                y: CGFloat(row) * (Self.rowHeight + Self.rowSpacing),
                width: itemWidth,
                height: Self.rowHeight
            )
        }
        scrollView.contentSize = CGSize(width: pageWidth * CGFloat(pageControl.numberOfPages),
                                        height: Self.pageHeight)
    }

    @objc private func handleTileTap(_ sender: MorePanelTileView) {
        guard actions.indices.contains(sender.tag) else { return }
        let action = actions[sender.tag]
        let hadMarker = (action.showRedDot || action.badgeText != nil)
        if hadMarker, dismissedRedDotIDs.insert(action.ID).inserted {
            sender.clearMarkers()
            if action.showRedDot { onRedDotDismissed?() }
        }
        action.onClick()
    }
}

// MARK: - UIScrollViewDelegate

extension MessageInputMorePanel: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        pageControl.currentPage = Int((scrollView.contentOffset.x + width / 2) / width)
    }
}

// MARK: - MorePanelTileView

private final class MorePanelTileView: UIControl {
    private let iconTileView = UIView()

    private let iconImageView = UIImageView()

    private let titleLabel = UILabel()

    private let redDotView = UIView()

    private let badgeLabel = MorePanelBadgeLabel()

    private var glyphConstraints: [Constraint] = []

    private var fullBleedConstraints: [Constraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTile()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.iconTileView.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
            }
        }
    }

    func configure(icon: UIImage?, title: String, fullBleed: Bool, showRedDot: Bool, badge: String?) {
        iconImageView.image = icon
        titleLabel.text = title
        redDotView.isHidden = !showRedDot
        badgeLabel.text = badge
        badgeLabel.isHidden = (badge ?? "").isEmpty
        // A full-bleed icon is the complete tile bitmap (background, glow, stroke, glyph).
        iconTileView.backgroundColor = fullBleed ? .clear : TUIChatKitTheme.colors.bgColorInput
        glyphConstraints.forEach { fullBleed ? $0.deactivate() : $0.activate() }
        fullBleedConstraints.forEach { fullBleed ? $0.activate() : $0.deactivate() }
    }

    func clearMarkers() {
        redDotView.isHidden = true
        badgeLabel.isHidden = true
    }

    private func setupTile() {
        let colors = TUIChatKitTheme.colors
        clipsToBounds = false

        iconTileView.isUserInteractionEnabled = false
        iconTileView.layer.cornerRadius = MessageInputMorePanel.iconTileCornerRadius
        iconTileView.layer.masksToBounds = true
        addSubview(iconTileView)

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = colors.textColorPrimary
        iconTileView.addSubview(iconImageView)

        titleLabel.font = .adaptiveSystemFont(ofSize: 12)
        titleLabel.textColor = colors.textColorSecondary
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        titleLabel.isUserInteractionEnabled = false
        addSubview(titleLabel)

        // Sits outside the tile, whose masksToBounds would clip it.
        redDotView.backgroundColor = colors.textColorError
        redDotView.layer.cornerRadius = MessageInputMorePanel.redDotSize / 2
        redDotView.isUserInteractionEnabled = false
        redDotView.isHidden = true
        addSubview(redDotView)

        badgeLabel.font = .adaptiveSystemFont(ofSize: 8, weight: .bold)
        badgeLabel.textColor = colors.textColorButton
        badgeLabel.isHidden = true
        addSubview(badgeLabel)

        iconTileView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.width.height.equalTo(MessageInputMorePanel.iconSize)
        }
        redDotView.snp.makeConstraints { make in
            make.top.equalTo(iconTileView.snp.top)
            make.trailing.equalTo(iconTileView.snp.trailing)
            make.width.height.equalTo(MessageInputMorePanel.redDotSize)
        }
        badgeLabel.snp.makeConstraints { make in
            make.top.equalTo(iconTileView.snp.top).offset(-MessageInputMorePanel.badgeRise)
            make.trailing.equalTo(iconTileView.snp.trailing).offset(MessageInputMorePanel.badgeOverhang)
            make.height.equalTo(MessageInputMorePanel.badgeHeight)
        }
        iconImageView.snp.makeConstraints { make in
            glyphConstraints = [
                make.center.equalToSuperview().constraint,
                make.width.height.equalTo(MessageInputMorePanel.iconGlyphSize).constraint
            ]
        }
        iconImageView.snp.prepareConstraints { make in
            fullBleedConstraints = [make.edges.equalToSuperview().constraint]
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(iconTileView.snp.bottom).offset(MessageInputMorePanel.titleTopSpacing)
            make.leading.trailing.equalToSuperview().inset(2)
            make.height.equalTo(MessageInputMorePanel.titleAreaHeight)
        }
    }
}

/// Gradient pill for "NEW" style badges (brand primary → accent), outlined with the
/// panel background so it reads as floating above the tile edge. The text lives in a child
/// label: a gradient sublayer on a UILabel would paint over its own glyphs.
private final class MorePanelBadgeLabel: UIView {
    private let gradient = CAGradientLayer()

    private let label = UILabel()

    var text: String? {
        get { label.text }
        set { label.text = newValue; invalidateIntrinsicContentSize() }
    }

    var font: UIFont {
        get { label.font }
        set { label.font = newValue }
    }

    var textColor: UIColor {
        get { label.textColor }
        set { label.textColor = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let colors = TUIChatKitTheme.colors
        gradient.colors = [colors.buttonColorPrimaryDefault.cgColor, colors.textColorError.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(gradient)
        layer.borderWidth = 1.5
        layer.borderColor = colors.bgColorOperate.cgColor
        clipsToBounds = true
        isUserInteractionEnabled = false
        label.textAlignment = .center
        addSubview(label)
        label.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let size = label.intrinsicContentSize
        return CGSize(width: size.width + 10, height: MessageInputMorePanel.badgeHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        layer.cornerRadius = bounds.height / 2
    }
}
