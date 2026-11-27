import UIKit
import SnapKit
import AtomicXCore
import AtomicX

enum ReactionPanelLevel {
    case recent
    case all
}

final class ReactionEmojiPanelView: UIView {
    static let panelWidth: CGFloat = horizontalPadding * 2 + cellSize * CGFloat(columns)

    static func panelHeight(level: ReactionPanelLevel) -> CGFloat {
        return headerHeight + dividerHeight + bodyHeight(level: level)
    }

    static func bodyHeight(level: ReactionPanelLevel) -> CGFloat {
        switch level {
        case .recent: return verticalPadding * 2 + cellSize * CGFloat(recentRows)
        case .all: return allBodyHeight
        }
    }

    var onBack: ((ReactionPanelLevel) -> Void)?

    var onMore: (() -> Void)?

    var onToggleEmoji: ((EmojiData) -> Void)?

    private static let columns = 7

    private static let recentRows = 2

    private static let maxRecentEmojiCount = columns * recentRows - 1

    private static let cellSize: CGFloat = 36

    private static let glyphSize: CGFloat = 26

    private static let horizontalPadding: CGFloat = 8

    private static let verticalPadding: CGFloat = 6

    private static let headerHeight: CGFloat = 36

    private static let headerStartPadding: CGFloat = 6

    private static let headerEndPadding: CGFloat = 14

    private static let dividerHeight: CGFloat = 1

    private static let dividerMargin: CGFloat = 14

    private static let allBodyHeight: CGFloat = 174

    private static let backHeight: CGFloat = 28

    private static let backIconSize: CGFloat = 14

    private static let moreCircleSize: CGFloat = 26

    private let message: MessageInfo

    private let level: ReactionPanelLevel

    init(message: MessageInfo, level: ReactionPanelLevel) {
        self.message = message
        self.level = level
        super.init(frame: .zero)
        constructViewHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func constructViewHierarchy() {
        let header = buildHeader()
        addSubview(header)
        header.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(Self.headerHeight)
        }

        let divider = UIView()
        divider.backgroundColor = TUIChatKitTheme.colors.strokeColorPrimary
        addSubview(divider)
        divider.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom)
            make.leading.trailing.equalToSuperview().inset(Self.dividerMargin)
            make.height.equalTo(Self.dividerHeight)
        }

        let body = buildBody()
        addSubview(body)
        body.snp.makeConstraints { make in
            make.top.equalTo(divider.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(Self.bodyHeight(level: level))
        }

        snp.makeConstraints { make in
            make.width.equalTo(Self.panelWidth)
            make.height.equalTo(Self.panelHeight(level: level))
        }
    }

    private func buildHeader() -> UIView {
        let colors = TUIChatKitTheme.colors
        let header = UIView()

        let back = TappableControl { [weak self] in
            guard let self = self else { return }
            self.onBack?(self.level)
        }
        let backIcon = UIImageView()
        backIcon.contentMode = .scaleAspectFit
        backIcon.tintColor = colors.textColorSecondary
        backIcon.image = Self.icon(named: "message_chevron_down", fallback: "chevron.down")
        backIcon.transform = CGAffineTransform(rotationAngle: .pi / 2)
        back.addSubview(backIcon)
        backIcon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(4)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.backIconSize)
        }
        let backLabel = UILabel()
        backLabel.text = LocalizedChatString("Back")
        backLabel.font = UIFont.adaptiveSystemFont(ofSize: 12)
        backLabel.textColor = colors.textColorSecondary
        back.addSubview(backLabel)
        backLabel.snp.makeConstraints { make in
            make.leading.equalTo(backIcon.snp.trailing).offset(2)
            make.trailing.equalToSuperview().offset(-10)
            make.centerY.equalToSuperview()
        }
        back.layer.cornerRadius = Self.backHeight / 2
        header.addSubview(back)
        back.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.headerStartPadding)
            make.centerY.equalToSuperview()
            make.height.equalTo(Self.backHeight)
        }

        let titleLabel = UILabel()
        titleLabel.text = LocalizedChatString(level == .all ? "ReactionAllTitle" : "ReactionRecentUsed")
        titleLabel.font = UIFont.adaptiveSystemFont(ofSize: 11)
        titleLabel.textColor = colors.textColorTertiary
        header.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Self.headerEndPadding)
            make.centerY.equalToSuperview()
        }
        return header
    }

    private func buildBody() -> UIView {
        let cells: [UIView]
        switch level {
        case .recent:
            cells = recentEmojiList().map { buildEmojiCell($0) } + [buildMoreCell()]
        case .all:
            cells = EmojiManager.shared.getPickerEmojis().map { buildEmojiCell($0) }
        }
        let rowCount = max(1, (cells.count + Self.columns - 1) / Self.columns)
        let grid = UIView()
        for (index, cell) in cells.enumerated() {
            grid.addSubview(cell)
            let row = index / Self.columns
            let column = index % Self.columns
            cell.snp.makeConstraints { make in
                make.leading.equalToSuperview().offset(Self.horizontalPadding + CGFloat(column) * Self.cellSize)
                make.top.equalToSuperview().offset(Self.verticalPadding + CGFloat(row) * Self.cellSize)
                make.width.height.equalTo(Self.cellSize)
            }
        }
        guard level == .all else { return grid }

        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = false
        scroll.addSubview(grid)
        grid.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(Self.panelWidth)
            make.height.equalTo(Self.verticalPadding * 2 + Self.cellSize * CGFloat(rowCount))
        }
        return scroll
    }

    private func buildEmojiCell(_ emoji: EmojiData) -> UIView {
        let control = TappableControl { [weak self] in self?.onToggleEmoji?(emoji) }
        control.layer.cornerRadius = Self.cellSize / 2
        if let name = emoji.name,
           message.reactionList.contains(where: { $0.reactionID == name && $0.reactedByMyself }) {
            control.backgroundColor = TUIChatKitTheme.colors.floatingColorOperate
        }
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        imageView.image = ReactionEmojiRenderer.image(for: emoji) ?? UIImage(systemName: "face.smiling")
        control.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(Self.glyphSize)
        }
        return control
    }

    private func buildMoreCell() -> UIView {
        let control = TappableControl { [weak self] in self?.onMore?() }
        let circle = UIView()
        circle.backgroundColor = TUIChatKitTheme.colors.floatingColorOperate
        circle.layer.cornerRadius = Self.moreCircleSize / 2
        circle.layer.masksToBounds = true
        circle.isUserInteractionEnabled = false
        let icon = UIImageView()
        icon.contentMode = .scaleAspectFit
        icon.tintColor = TUIChatKitTheme.colors.textColorSecondary
        icon.image = Self.icon(named: "message_chevron_down", fallback: "chevron.down")
        circle.addSubview(icon)
        icon.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(Self.backIconSize)
        }
        control.addSubview(circle)
        circle.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(Self.moreCircleSize)
        }
        return control
    }

    private func recentEmojiList() -> [EmojiData] {
        let allEmojis = EmojiManager.shared.getPickerEmojis()
        guard !allEmojis.isEmpty else { return [] }
        let emojiByName = Dictionary(allEmojis.compactMap { emoji -> (String, EmojiData)? in
            guard let name = emoji.name else { return nil }
            return (name, emoji)
        }, uniquingKeysWith: { first, _ in first })
        var orderedNames: [String] = []
        orderedNames += message.reactionList.filter { $0.reactedByMyself }.map { $0.reactionID }
        let recentGroupID = EmojiManager.shared.reactionGroupID()
        orderedNames += EmojiManager.shared.getRecentEmojis(groupID: recentGroupID)
        orderedNames += allEmojis.compactMap { $0.name }

        var result: [EmojiData] = []
        var usedNames = Set<String>()
        for name in orderedNames {
            guard let emoji = emojiByName[name], usedNames.insert(name).inserted else { continue }
            result.append(emoji)
            if result.count >= Self.maxRecentEmojiCount { break }
        }
        return result
    }

    private static func icon(named name: String, fallback: String) -> UIImage? {
        if let image = AtomicXChatResources.image(named: name) {
            return image.withRenderingMode(.alwaysTemplate)
        }
        return UIImage(systemName: fallback)
    }
}

private final class TappableControl: UIControl {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func handleTap() { handler() }
}
