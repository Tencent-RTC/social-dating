import UIKit
import AtomicX

// MARK: - Spec (kept in this file so the pod needs no re-install)

/// Spec of the conversation long-press menu (S2) and the left-swipe actions, taken from the
/// design "527:636" / prototype `.ctxmenu` and `.conv-swipe`.
enum ConversationMenuSpec {
    static let menuWidth: CGFloat = 168
    static let menuItemHeight: CGFloat = 44
    static let menuRadius: CGFloat = 8
    static let menuIconSize: CGFloat = 20
    static let menuIconGap: CGFloat = 10
    static let menuPaddingH: CGFloat = 14
    static let menuFontSize: CGFloat = 14
    static let dividerHeight: CGFloat = 1

    /// Long-press menu order of the prototype: pin, mute, unread, clear, delete.
    static let menuOrder: [String] = [
        ConversationActionIDs.pin,
        ConversationActionIDs.mute,
        ConversationActionIDs.markUnread,
        ConversationActionIDs.clearHistory,
        ConversationActionIDs.delete,
    ]

    /// Id of the swipe-only "More" button (it is not an action of its own, it opens a sheet).
    static let moreActionID = "conversation.more"

    /// WeChat style left swipe, listed from the trailing edge inwards (UIKit puts the first
    /// action next to the edge): delete, more, mark read / unread.
    static let swipeDirectActionIDs: [String] = [
        ConversationActionIDs.delete,
        ConversationActionIDs.markUnread,
    ]

    /// Row layout of the swipe buttons (same 72 wide, 18 icon, 13 text as Android).
    static let swipeButtonWidth: CGFloat = 72
    static let swipeIconSize: CGFloat = 18
    static let swipeFontSize: CGFloat = 13
    static let swipeIconTextGap: CGFloat = 3

    static func menuHeight(itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        return CGFloat(itemCount) * menuItemHeight + CGFloat(itemCount - 1) * dividerHeight
    }

    /// Known actions first (prototype order); custom actions keep their relative order after them.
    static func orderForMenu(_ actions: [ConversationCustomAction]) -> [ConversationCustomAction] {
        let known = menuOrder.compactMap { id in actions.first { $0.ID == id } }
        let custom = actions.filter { !menuOrder.contains($0.ID) }
        return known + custom
    }

    /// Actions that get their own swipe button: mark read / unread and delete.
    static func swipeDirectActions(of actions: [ConversationCustomAction]) -> [ConversationCustomAction] {
        return swipeDirectActionIDs.compactMap { id in actions.first { $0.ID == id } }
    }

    /// Everything else (pin, mute, clear history, custom ones) is folded behind "More".
    static func swipeMoreActions(of actions: [ConversationCustomAction]) -> [ConversationCustomAction] {
        return orderForMenu(actions).filter { !swipeDirectActionIDs.contains($0.ID) }
    }

    static func assetName(for actionID: String) -> String? {
        switch actionID {
        case ConversationActionIDs.pin: return "conversation_menu_pin"
        case ConversationActionIDs.mute: return "conversation_menu_mute"
        case ConversationActionIDs.markUnread: return "conversation_menu_unread"
        case ConversationActionIDs.clearHistory: return "conversation_menu_clear"
        case ConversationActionIDs.delete: return "conversation_menu_delete"
        case moreActionID: return "conversation_menu_more"
        default: return nil
        }
    }

    /// Same glyphs as the Android menu (`conversation_list_menu_*_icon`), template rendered.
    static func icon(for actionID: String) -> UIImage? {
        guard let name = assetName(for: actionID) else { return nil }
        return AtomicXChatResources.image(named: name)?.withRenderingMode(.alwaysTemplate)
    }

    /// A swipe button is "icon over label" drawn into one original-rendered image: UIKit
    /// tints contextual-action images white and hides the title when the row is short,
    /// so drawing both ourselves is the only way to match the Android buttons.
    static func swipeButtonImage(actionID: String, title: String, color: UIColor) -> UIImage? {
        guard let icon = icon(for: actionID) else { return nil }
        let font = UIFont.adaptiveSystemFont(ofSize: swipeFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let width = max(swipeButtonWidth, ceil(textSize.width) + 12)
        let height = swipeIconSize + swipeIconTextGap + ceil(textSize.height)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { _ in
            icon.withTintColor(color, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: (width - swipeIconSize) / 2, y: 0, width: swipeIconSize, height: swipeIconSize))
            (title as NSString).draw(at: CGPoint(x: (width - textSize.width) / 2,
                                                 y: swipeIconSize + swipeIconTextGap),
                                     withAttributes: attributes)
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}


/// Bottom action sheet that mimics the pre-iOS 26 system action sheet: one rounded card holding the
/// actions, a separate rounded "Cancel" card under it, both pinned to the bottom edge.
/// iOS 26 renders `UIAlertController(.actionSheet)` as a floating glass card in the middle of the
/// screen, so the conversation list "More" menu uses this controller there to keep one look.
final class ConversationBottomSheetController: UIViewController {

    struct Item {
        let title: String
        let dangerous: Bool
        let handler: () -> Void
    }

    private let items: [Item]
    private let cancelTitle: String

    private let dimView = UIView()
    private let container = UIStackView()
    private let rowHeight: CGFloat = 57
    private let cardRadius: CGFloat = 14
    private let sideMargin: CGFloat = 10
    private var didShow = false

    init(items: [Item], cancelTitle: String) {
        self.items = items
        self.cancelTitle = cancelTitle
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimView.alpha = 0
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cancelTapped)))
        view.addSubview(dimView)

        container.axis = .vertical
        container.spacing = 8
        container.addArrangedSubview(makeCard(rows: items.map { item in
            makeRow(title: item.title, dangerous: item.dangerous, bold: false) { [weak self] in
                self?.dismiss(animated: true) { item.handler() }
            }
        }))
        container.addArrangedSubview(makeCard(rows: [
            makeRow(title: cancelTitle, dangerous: false, bold: true) { [weak self] in
                self?.dismiss(animated: true)
            }
        ]))
        view.addSubview(container)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dimView.frame = view.bounds
        let width = view.bounds.width - sideMargin * 2
        let height = container.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let bottomInset = max(view.safeAreaInsets.bottom, sideMargin)
        let shown = CGRect(x: sideMargin, y: view.bounds.height - bottomInset - height, width: width, height: height)
        if didShow {
            container.frame = shown
        } else {
            container.frame = shown.offsetBy(dx: 0, dy: height + bottomInset + sideMargin)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didShow else { return }
        didShow = true
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            self.dimView.alpha = 1
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        guard flag, presentingViewController != nil else {
            super.dismiss(animated: flag, completion: completion)
            return
        }
        let offset = container.frame.height + view.safeAreaInsets.bottom + sideMargin
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn], animations: {
            self.dimView.alpha = 0
            self.container.frame = self.container.frame.offsetBy(dx: 0, dy: offset)
        }, completion: { _ in
            super.dismiss(animated: false, completion: completion)
        })
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    private func makeCard(rows: [UIView]) -> UIView {
        let card = UIView()
        card.layer.cornerRadius = cardRadius
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        card.addSubview(blur)
        blur.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: card.topAnchor),
            blur.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])
        return card
    }

    private func makeRow(title: String, dangerous: Bool, bold: Bool, handler: @escaping () -> Void) -> UIView {
        let row = SheetRowView(handler: handler)
        row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        let label = UILabel()
        label.text = title
        label.font = .adaptiveSystemFont(ofSize: 20, weight: bold ? .semibold : .regular)
        label.textColor = dangerous ? .systemRed : TUIChatKitTheme.colors.textColorPrimary
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        let line = UIView()
        line.backgroundColor = UIColor.separator
        line.isUserInteractionEnabled = false
        line.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(line)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            line.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            line.topAnchor.constraint(equalTo: row.topAnchor),
            line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
        row.separator = line
        return row
    }

    /// First row of a card has no top hairline.
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        for case let card in container.arrangedSubviews {
            if let stack = card.subviews.compactMap({ $0 as? UIStackView }).first,
               let first = stack.arrangedSubviews.first as? SheetRowView {
                first.separator?.isHidden = true
            }
        }
    }
}

private final class SheetRowView: UIControl {
    var separator: UIView?
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? UIColor.label.withAlphaComponent(0.12) : .clear }
    }

    @objc private func tapped() { handler() }
}
