import UIKit
import AtomicX
import AtomicXCore

/// Hard metrics of the V2 host shell, from the prototype tokens (`tokens.css :root`) and
/// `uikit.css`. 1pt = 1px of the 360 x 800 design frame. Android uses the same numbers in
/// `HostMetrics` (HostWidgets.kt); `tools/tests/test_host_shell.py` keeps the two in sync.
public enum HostMetrics {
    public static let pageHeaderH: CGFloat = 48
    public static let pageTitleSize: CGFloat = 19
    public static let segBarH: CGFloat = 44
    public static let searchBarH: CGFloat = 36
    public static let searchBarRadius: CGFloat = 10
    public static let convItemH: CGFloat = 72
    /// Home card nickname / intro: same sizes as the conversation row title (18) and subtitle (14).
    public static let userCardNameSize: CGFloat = 18
    public static let userCardMetaSize: CGFloat = 14
    public static let convAvatar: CGFloat = 48
    public static let screenPaddingH: CGFloat = 16
    public static let cardRadius: CGFloat = 14

    // Bottom tab bar
    public static let tabBarH: CGFloat = 64
    public static let tabItemH: CGFloat = 54
    public static let tabIcon: CGFloat = 28
    public static let floatingTabGlyphWidth: CGFloat = 76
    public static let tabLabelSize: CGFloat = 12
    public static let tabBadge: CGFloat = 18
    public static let tabBadgeRing: CGFloat = 2
    public static let tabBadgeOffsetTop: CGFloat = -3
    public static let tabBadgeOffsetLeft: CGFloat = 16

    // Segment tabs
    public static let segGap: CGFloat = 20
    public static let segGapTight: CGFloat = 18
    public static let segTextSize: CGFloat = 18
    public static let segTextOnSize: CGFloat = 20
    public static let segUnderlineW: CGFloat = 16
    public static let segUnderlineH: CGFloat = 3

    // Home user card
    public static let userCardGap: CGFloat = 12
    public static let userCardMaskH: CGFloat = 64
    public static let distTagH: CGFloat = 18
    public static let sexTagH: CGFloat = 16

    // Mine
    public static let meAvatar: CGFloat = 72
    public static let meBlockGap: CGFloat = 8
    public static let walletH: CGFloat = 80
    public static let walletRadius: CGFloat = 14
    public static let menuRowH: CGFloat = 56
}

public enum HostTagKind { case ageMale, ageFemale, city, height, verified }

/// Colours come from the current social palette on every access; screens rebuild on
/// `DemoThemeCoordinator.didChange`, so nothing here is cached across a theme change.
public enum Host {
    public static var tokens: ColorTokens { ThemeStore.shared.colorTokens }

    /// The one colour token of a tag class; every page (profile, chat title, lists, home card) reads it from here.
    public static func tagAccent(_ kind: HostTagKind) -> UIColor {
        switch kind {
        case .ageMale: return tokens.tagColorLevel1
        case .ageFemale: return tokens.tagColorLevel4
        case .city: return tokens.tagColorLevel2
        case .height: return tokens.textColorWarning
        case .verified: return tokens.tagColorLevel1
        }
    }

    /// Age / gender tag class of a peer: male = blue-ish token, female = pink token.
    public static func ageKind(sex: String) -> HostTagKind { sex == "m" ? .ageMale : .ageFemale }

    public static var isDark: Bool {
        var white: CGFloat = 0
        tokens.bgColorDefault.getWhite(&white, alpha: nil)
        return white < 0.5
    }

    public static func hapticConfirm() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    private static var imageCache: [String: UIImage] = [:]

    /// Icons are bundled as `<name>@3x.png`; photos as flat `<name>.jpg` (UIImage(named:) does not
    /// resolve extension-less jpg names reliably, so fall back to an explicit path lookup).
    public static func image(_ name: String) -> UIImage? {
        if let cached = imageCache[name] { return cached }
        var found = UIImage(named: name)
        if found == nil {
            for bundle in HostResources.bundles {
                if let image = UIImage(named: name, in: bundle, compatibleWith: nil) { found = image; break }
            }
        }
        if found == nil {
            for bundle in [Bundle.main] + HostResources.bundles {
                if let path = bundle.path(forResource: name, ofType: "jpg"), let image = UIImage(contentsOfFile: path) { found = image; break }
            }
        }
        if let found { imageCache[name] = found }
        return found
    }

    /// Template glyph tinted with `tint`.
    public static func icon(_ name: String, size: CGFloat, tint: UIColor) -> UIImageView {
        let view = UIImageView(image: image(name)?.withRenderingMode(.alwaysTemplate))
        view.tintColor = tint
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        return view
    }

    public static func brandGradientLayer(startPoint: CGPoint = CGPoint(x: 0, y: 0.5), endPoint: CGPoint = CGPoint(x: 1, y: 0.5)) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.colors = [tokens.buttonColorPrimaryDefault.cgColor, tokens.tagColorLevel4.cgColor]
        layer.startPoint = startPoint
        layer.endPoint = endPoint
        return layer
    }

    public static func lerp(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var (ar, ag, ab, aa) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        var (br, bg, bb, ba) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: aa + (ba - aa) * t)
    }

    // MARK: tags

    private static func pill(_ views: [UIView], fill: UIColor, radius: CGFloat, insets: UIEdgeInsets, height: CGFloat, spacing: CGFloat) -> UIView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = spacing
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = insets
        stack.backgroundColor = fill
        stack.layer.cornerRadius = radius
        stack.clipsToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.heightAnchor.constraint(equalToConstant: height).isActive = true
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        return stack
    }

    private static func dot(_ color: UIColor, size: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = color
        view.layer.cornerRadius = size / 2
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        return view
    }

    /// `.tag--verified`: shield 10 + text; dark palettes lift the text one step towards white.
    public static func verifiedTag(_ text: String) -> UIView {
        let base = tagAccent(.verified)
        let ink = isDark ? lerp(base, .white, 0.22) : base
        return pill([icon("demo_ic_shield", size: 10, tint: ink), label(text, 10, ink)],
                    fill: base.withAlphaComponent(0.18), radius: 5,
                    insets: UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 6), height: 18, spacing: 3)
    }

    /// `.sextag`: gender glyph 10 + age, h16 r8; male = tagColorLevel1 (blue), female = tagColorLevel4 (pink); the glyph repeats the gender.
    public static func sexTag(sex: String, age: Int) -> UIView {
        let male = sex == "m"
        let accent = tagAccent(ageKind(sex: sex))
        let ink: UIColor = isDark ? lerp(accent, .white, 0.30) : accent
        let fill: UIColor = accent.withAlphaComponent(0.18)
        return pill([icon(male ? "demo_ic_male" : "demo_ic_female", size: 10, tint: ink), label("\(age)", 10, ink)],
                    fill: fill, radius: 8, insets: UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 6),
                    height: HostMetrics.sexTagH, spacing: 2)
    }

    /// `.metatag`: solid tagColorLevelN pill with `textColorButton` 10 text, used for city / age / height.
    public static func metaTag(_ text: String, accent: UIColor, height: CGFloat = HostMetrics.distTagH,
                               radius: CGFloat = 9, textColor: UIColor? = nil, textSize: CGFloat = 10) -> DemoPaddedLabel {
        let view = DemoPaddedLabel()
        view.insets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 7)
        view.text = text
        view.font = .adaptiveSystemFont(ofSize: textSize)
        view.textColor = textColor ?? tokens.textColorButton
        view.textAlignment = .center
        view.backgroundColor = accent.withAlphaComponent(0.92)
        view.layer.cornerRadius = radius
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        return view
    }

    /// Solid chip of a tag class: always `metaTag` filled with that class's `tagAccent`.
    public static func kindTag(_ kind: HostTagKind, _ text: String, height: CGFloat = HostMetrics.distTagH,
                               radius: CGFloat = 9, textSize: CGFloat = 10) -> DemoPaddedLabel {
        metaTag(text, accent: tagAccent(kind), height: height, radius: radius, textSize: textSize)
    }

    /// The one colour of every unread indicator (count badge, red dot) on every page: the error token.
    public static var unreadAccent: UIColor { tokens.textColorError }

    /// Count badge (`.badge`): h18 min-w17 pill, `unreadAccent` with textColorButton bold text.
    public static func badge(_ count: Int, size: CGFloat = 18, textSize: CGFloat = 11) -> UIView {
        let text = DemoPaddedLabel()
        text.insets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)
        text.text = count > 99 ? "99+" : "\(count)"
        text.font = .adaptiveSystemFont(ofSize: textSize, weight: .bold)
        text.textColor = tokens.textColorButton
        text.textAlignment = .center
        text.backgroundColor = unreadAccent
        text.layer.cornerRadius = size / 2
        text.clipsToBounds = true
        text.translatesAutoresizingMaskIntoConstraints = false
        text.heightAnchor.constraint(equalToConstant: size).isActive = true
        text.widthAnchor.constraint(greaterThanOrEqualToConstant: size - 1).isActive = true
        text.setContentHuggingPriority(.required, for: .horizontal)
        return text
    }

    /// Avatar from a bundled design sample, or the first letter of `name` on the avatar surface.
    public static func sampleAvatar(_ imageName: String, name: String, size: CGFloat) -> UIView {
        let container = UIView()
        container.backgroundColor = tokens.bgColorAvatar
        container.layer.cornerRadius = size / 2
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: size).isActive = true
        container.heightAnchor.constraint(equalToConstant: size).isActive = true
        if !imageName.isEmpty, let image = image(imageName) {
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFill
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: container.topAnchor), view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor), view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            ])
        } else {
            let letter = label(String(name.prefix(1)), size * 0.4, tokens.textColorPrimary, bold: true)
            letter.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(letter)
            NSLayoutConstraint.activate([letter.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                                         letter.centerYAnchor.constraint(equalTo: container.centerYAnchor)])
        }
        return container
    }

    // MARK: tab bar images

    /// Selected tab glyph: the white alpha mask is filled with the palette gradient
    /// (buttonColorPrimaryDefault to tagColorLevel4, top-left to bottom-right) and the white
    /// details are drawn on top, like the design's "图标/Tab" selected state.
    public static func selectedTabImage(shape: String, detail: String) -> UIImage? {
        guard let mask = image(shape)?.cgImage, let top = image(detail) else { return nil }
        let size = CGSize(width: HostMetrics.tabIcon, height: HostMetrics.tabIcon)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            cg.saveGState()
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            cg.clip(to: rect, mask: mask)
            cg.scaleBy(x: 1, y: -1)
            cg.translateBy(x: 0, y: -size.height)
            let colors = [tokens.buttonColorPrimaryDefault.cgColor, tokens.tagColorLevel4.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            cg.restoreGState()
            top.draw(in: rect)
        }
        return widenedForFloatingTabBar(rendered.withRenderingMode(.alwaysOriginal))
    }

    /// Two-tone header glyph: `base` follows textColorPrimary, `accent` textColorWarning (sun core, moon star).
    public static func twoToneIcon(base: String, accent: String, size: CGFloat) -> UIImage {
        let canvas = CGSize(width: size, height: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let rect = CGRect(origin: .zero, size: canvas)
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            if let image = Host.image(base)?.withRenderingMode(.alwaysTemplate) {
                tokens.textColorPrimary.setFill()
                image.withTintColor(tokens.textColorPrimary, renderingMode: .alwaysOriginal).draw(in: rect)
            }
            if let image = Host.image(accent) {
                image.withTintColor(tokens.textColorWarning, renderingMode: .alwaysOriginal).draw(in: rect)
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    /// Template glyph drawn at `HostMetrics.tabIcon` (the asset's own size would ignore the metric).
    public static func templateTabImage(_ name: String) -> UIImage? {
        guard let source = image(name) else { return nil }
        let size = CGSize(width: HostMetrics.tabIcon, height: HostMetrics.tabIcon)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysTemplate)
        return widenedForFloatingTabBar(rendered)
    }

    /// iOS 26+ floating tab bar sizes each tab from its glyph width and ignores `itemWidth` / `itemSpacing`,
    /// so a wider bar is made by centring the glyph on a wider transparent canvas.
    static func widenedForFloatingTabBar(_ image: UIImage?) -> UIImage? {
        guard #available(iOS 26.0, *), let image, image.size.width < HostMetrics.floatingTabGlyphWidth else { return image }
        let canvas = CGSize(width: HostMetrics.floatingTabGlyphWidth, height: image.size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let mode = image.renderingMode
        let origin = CGPoint(x: (canvas.width - image.size.width) / 2, y: 0)
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            image.draw(at: origin)
        }.withRenderingMode(mode)
    }
}

/// Page header: 48pt, centred 17pt bold title, optional left view and right action views.
public final class HostHeaderView: UIView {
    public init(title: String, left: UIView? = nil, ops: [UIView] = [], opsGap: CGFloat = 14) {
        super.init(frame: .zero)
        backgroundColor = Host.tokens.bgColorTopBar
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: HostMetrics.pageHeaderH).isActive = true
        let titleLabel = label(title, HostMetrics.pageTitleSize, Host.tokens.textColorPrimary, bold: true)
        titleLabel.numberOfLines = 1
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                                     titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)])
        if let left {
            left.translatesAutoresizingMaskIntoConstraints = false
            addSubview(left)
            NSLayoutConstraint.activate([left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HostMetrics.screenPaddingH),
                                         left.centerYAnchor.constraint(equalTo: centerYAnchor)])
        }
        if !ops.isEmpty {
            let stack = UIStackView(arrangedSubviews: ops)
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = opsGap
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -HostMetrics.screenPaddingH),
                                         stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        }
    }

    public required init?(coder: NSCoder) { fatalError() }
}

/// Segment tabs (`.segbar`): 44pt, text 18 secondary / 20 bold primary + 16x3 underline, optional right control.
///
/// The bar is driven by a continuous position (`setPosition`, `0...n-1`): a pager reports where it is on every frame (tap
/// slide, finger drag and the settle after release alike), so labels and underline travel with the pages instead of
/// switching when they land. A label's weight is `1 - |position - index|`: size 18 -> 20, font weight regular -> bold and
/// colour secondary -> primary. The single underline stretches between two tabs (the leading edge runs ahead of the
/// trailing one) and settles back to 16pt.
public final class HostSegBar: UIView {
    private var labels: [UILabel] = []
    private var columns: [UIView] = []
    private let row = UIStackView()
    private let indicator = UIView()
    private let onSelect: (Int) -> Void
    private var position: CGFloat = -1
    private static let stretch: CGFloat = 1.7

    public init(titles: [String], selected: Int, tight: Bool = false, right: UIView? = nil, onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect
        super.init(frame: .zero)
        backgroundColor = Host.tokens.bgColorTopBar
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: HostMetrics.segBarH).isActive = true
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = tight ? HostMetrics.segGapTight : HostMetrics.segGap
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HostMetrics.screenPaddingH),
                                     row.centerYAnchor.constraint(equalTo: centerYAnchor)])
        for (index, title) in titles.enumerated() {
            let text = label(title, HostMetrics.segTextSize, Host.tokens.textColorSecondary)
            text.numberOfLines = 1
            // Keeps the room (and the position) of the underline; the visible one is the shared `indicator`.
            let spacer = UIView()
            spacer.isUserInteractionEnabled = false
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.widthAnchor.constraint(equalToConstant: HostMetrics.segUnderlineW).isActive = true
            spacer.heightAnchor.constraint(equalToConstant: HostMetrics.segUnderlineH).isActive = true
            let column = UIStackView(arrangedSubviews: [text, spacer])
            column.axis = .vertical
            column.alignment = .center
            column.spacing = 4
            column.tag = index
            column.isUserInteractionEnabled = true
            column.isAccessibilityElement = true
            column.accessibilityLabel = title
            column.accessibilityTraits = .button
            column.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
            labels.append(text)
            columns.append(column)
            row.addArrangedSubview(column)
        }
        indicator.backgroundColor = Host.tokens.buttonColorPrimaryDefault
        indicator.layer.cornerRadius = HostMetrics.segUnderlineH / 2
        indicator.isUserInteractionEnabled = false
        addSubview(indicator)
        if let right {
            right.translatesAutoresizingMaskIntoConstraints = false
            addSubview(right)
            NSLayoutConstraint.activate([right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -HostMetrics.screenPaddingH),
                                         right.centerYAnchor.constraint(equalTo: centerYAnchor)])
        }
        select(selected, notify: false)
    }

    public required init?(coder: NSCoder) { fatalError() }

    // The pager answers a tap with its slide, which moves the bar frame by frame; nothing is switched here, so a tap
    // and a swipe look the same.
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag else { return }
        onSelect(index)
    }

    private var badgeViews: [Int: UIView] = [:]
    private var badgeCounts: [Int: Int] = [:]

    public func setBadge(_ index: Int, count: Int) {
        guard labels.indices.contains(index) else { return }
        let previous = badgeCounts[index] ?? 0
        badgeCounts[index] = count
        badgeViews[index]?.removeFromSuperview()
        badgeViews[index] = nil
        guard count > 0 else { return }
        let text = labels[index]
        let badge = Host.badge(count, size: 16, textSize: 10)
        badge.translatesAutoresizingMaskIntoConstraints = false
        text.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: text.trailingAnchor, constant: -4),
            badge.centerYAnchor.constraint(equalTo: text.topAnchor, constant: 0)
        ])
        badgeViews[index] = badge
        if count > previous, window != nil { Motion.bump(badge) }
    }

    /// Jumps to `index` with no transition; `notify` reports it to the select callback.
    public func select(_ index: Int, notify: Bool) {
        setPosition(CGFloat(index))
        if notify { onSelect(index) }
    }

    /// Continuous position between tabs: `1.5` is half way from the second tab to the third.
    public func setPosition(_ value: CGFloat) {
        let p = max(0, min(CGFloat(max(labels.count - 1, 0)), value))
        guard p != position else { return }
        position = p
        let tokens = Host.tokens
        let regular = HostMetrics.segTextSize
        let on = HostMetrics.segTextOnSize
        for (i, text) in labels.enumerated() {
            let w = max(0, min(1, 1 - abs(p - CGFloat(i))))
            text.font = .adaptiveSystemFont(ofSize: regular + (on - regular) * w,
                                    weight: UIFont.Weight(rawValue: UIFont.Weight.bold.rawValue * w))
            text.textColor = Self.blend(tokens.textColorSecondary, tokens.textColorPrimary, w)
        }
        // The labels changed width, so the columns have to be laid out before the underline reads their frames.
        if bounds.width > 0 {
            row.setNeedsLayout()
            row.layoutIfNeeded()
        }
        placeIndicator()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // The row is laid out after this view's own pass; iOS 26 does it in one go, so the tab frames the underline
        // reads would still be empty and the underline never showed. Settle the row first.
        row.layoutIfNeeded()
        placeIndicator()
    }

    /// Where a tab's underline sits: centred under its label, on the bottom edge of the tab column. Worked out from the
    /// column frame (known as soon as the row is laid out) instead of the spacer inside it, whose own layout pass can
    /// still be pending, which left the underline invisible on iOS 26.
    private func underlineRect(_ index: Int) -> CGRect {
        let frame = row.convert(columns[index].frame, to: self)
        let width = HostMetrics.segUnderlineW
        let height = HostMetrics.segUnderlineH
        return CGRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
    }

    private func placeIndicator() {
        guard !columns.isEmpty, position >= 0, bounds.width > 0 else { return }
        let first = max(0, min(columns.count - 1, Int(floor(position))))
        let second = min(first + 1, columns.count - 1)
        let t = max(0, min(1, position - CGFloat(first)))
        let a = underlineRect(first)
        let b = underlineRect(second)
        guard a.maxX > a.minX, columns[first].bounds.width > 0 else { return }
        // The edge in front runs ahead of the one behind, so the line stretches while it travels and relaxes on arrival.
        let ahead = 1 - pow(1 - t, Self.stretch)
        let behind = pow(t, Self.stretch)
        let left = a.minX + (b.minX - a.minX) * behind
        let rightEdge = a.maxX + (b.maxX - a.maxX) * ahead
        indicator.frame = CGRect(x: left, y: a.minY, width: max(rightEdge - left, 0), height: a.height)
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
