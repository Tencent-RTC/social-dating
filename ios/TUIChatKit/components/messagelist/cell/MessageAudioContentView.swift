import UIKit
import Combine
import SnapKit
import AtomicXCore
import AtomicX

/// Voice bubble per design S3/S8 (prototype `.bubble--voice`): 40pt high, width 140...200 from the
/// duration (`140 + (dur - 6) * 5`), 12pt side padding, play glyph 14 + wave (2pt bars, 16pt max) + duration 12pt.
/// The SDK still owns the bubble fill, tap-to-play and playback state.
final class MessageAudioContentView: UIView, MessageContentView {
    static let minWidth: CGFloat = 140

    static let maxWidth: CGFloat = 200

    private static let height: CGFloat = 40

    private static let sideInset: CGFloat = 12

    private static let contentSpacing: CGFloat = 8

    private static let waveHeights12: [CGFloat] = [4, 10, 14, 6, 16, 12, 7, 15, 9, 13, 5, 8]

    private static let waveHeights13: [CGFloat] = [5, 9, 13, 7, 16, 11, 6, 12, 8, 14, 7, 10, 5]

    private static let dimmedContainerAlpha: CGFloat = 0.85

    private var message: MessageInfo?

    private var isSelf = false

    private var durationSeconds = 0

    private weak var messageListStore: MessageListStore?

    private var playingCancellable: AnyCancellable?

    private var currentPlayingMsgID: String?

    private var contentWidthConstraint: Constraint?

    private let bubbleView = UIView()

    private let contentStack = UIStackView()

    private let playView = VoicePlayGlyphView()

    private let waveView = VoiceWaveView()

    private let durationLabel = UILabel()

    private var progressTimer: Timer?

    private var progressStart: Date?

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        constructViewHierarchy()
        activateConstraints()
        setupViewStyle()
        bindInteraction()
        subscribePlaybackState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        progressTimer?.invalidate()
    }

    // MARK: - Metrics (internal for the static test)

    static func width(forDuration seconds: Int) -> CGFloat {
        min(max(minWidth + CGFloat(seconds - 6) * 5, minWidth), maxWidth)
    }

    static func barCount(forWidth width: CGFloat) -> Int {
        12 + Int((width - minWidth) / 10 + 0.5)
    }

    static func barHeights(count: Int) -> [CGFloat] {
        let sequence = count == 12 ? waveHeights12 : waveHeights13
        return (0..<count).map { sequence[$0 % sequence.count] }
    }

    // MARK: - MessageContentView

    func bind(message: MessageInfo, context: MessageContentContext) {
        self.message = message
        self.isSelf = context.isSelf
        self.messageListStore = context.messageListStore

        let duration = max(Self.audioDuration(from: message), 0)
        durationSeconds = duration
        durationLabel.text = Self.formatDuration(duration)
        let width = Self.width(forDuration: duration)
        waveView.heights = Self.barHeights(count: Self.barCount(forWidth: width))
        applyColors(isSelf: context.isSelf)
        contentWidthConstraint?.update(offset: width)
        updatePlaybackVisualState()
    }

    // MARK: - Private

    private func constructViewHierarchy() {
        addSubview(bubbleView)
        bubbleView.addSubview(contentStack)
        contentStack.addArrangedSubview(playView)
        contentStack.addArrangedSubview(waveView)
        contentStack.addArrangedSubview(durationLabel)
    }

    private func activateConstraints() {
        bubbleView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalTo(Self.height)
            contentWidthConstraint = make.width.equalTo(Self.minWidth).constraint
        }
        contentStack.snp.makeConstraints { make in
            make.leading.equalTo(bubbleView).offset(Self.sideInset)
            make.trailing.equalTo(bubbleView).offset(-Self.sideInset)
            make.centerY.equalTo(bubbleView)
        }
        playView.snp.makeConstraints { make in
            make.width.height.equalTo(14)
        }
        waveView.snp.makeConstraints { make in
            make.height.equalTo(16)
        }
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        waveView.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func setupViewStyle() {
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = Self.contentSpacing
        durationLabel.font = .adaptiveSystemFont(ofSize: 12)
        durationLabel.numberOfLines = 1
    }

    private func bindInteraction() {
        bubbleView.isUserInteractionEnabled = true
        bubbleView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    private func subscribePlaybackState() {
        playingCancellable = ChatAudioPlaybackCoordinator.shared.playingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msgID in
                self?.currentPlayingMsgID = msgID
                self?.updatePlaybackVisualState()
            }
    }

    private func applyColors(isSelf: Bool) {
        let colors = TUIChatKitTheme.colors
        if isSelf {
            let idle = colors.textColorButton.withAlphaComponent(0.75)
            playView.color = colors.textColorButton
            durationLabel.textColor = idle
            waveView.apply(idle: idle, unplayed: colors.textColorButton.withAlphaComponent(0.40), played: colors.textColorButton)
        } else {
            playView.color = colors.textColorPrimary
            durationLabel.textColor = colors.textColorSecondary
            waveView.apply(idle: colors.textColorPrimary.withAlphaComponent(0.82), unplayed: colors.textColorTertiary,
                           played: colors.textColorLink)
        }
    }

    private func updatePlaybackVisualState() {
        guard let message = message else { return }
        let isCurrent = currentPlayingMsgID == message.msgID
        let isPlaying = isCurrent && ChatAudioPlaybackCoordinator.shared.isPlaying(msgID: message.msgID)
        if isPlaying {
            startProgress()
        } else {
            stopProgress()
        }
        durationLabel.alpha = isCurrent ? 1.0 : Self.dimmedContainerAlpha
        let someonePlaying = currentPlayingMsgID != nil
        self.alpha = (isCurrent || !someonePlaying) ? 1.0 : Self.dimmedContainerAlpha
    }

    private func startProgress() {
        guard progressTimer == nil else { return }
        progressStart = Date()
        let total = max(Double(durationSeconds), 1)
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let start = self.progressStart else { return }
            self.waveView.progress = CGFloat(min(Date().timeIntervalSince(start) / total, 1))
        }
    }

    private func stopProgress() {
        progressTimer?.invalidate()
        progressTimer = nil
        progressStart = nil
        waveView.progress = -1
    }

    @objc private func handleTap() {
        guard let message = message else { return }
        guard case .audio(let payload) = message.messagePayload else { return }

        if let path = payload.audioPath,
           !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            ChatAudioPlaybackCoordinator.shared.toggle(msgID: message.msgID, url: URL(fileURLWithPath: path))
            return
        }
        if let urlString = payload.audioURL,
           !urlString.isEmpty,
           let url = URL(string: urlString) {
            ChatAudioPlaybackCoordinator.shared.toggle(msgID: message.msgID, url: url)
            return
        }
        downloadThenPlay(message: message)
    }

    private func downloadThenPlay(message: MessageInfo) {
        MessageActionStore.create(message: message).downloadMedia(quality: nil) { [weak self] result in
            guard case .success = result else { return }
            DispatchQueue.main.async {
                self?.playAfterDownload(msgID: message.msgID)
            }
        }
    }

    private func playAfterDownload(msgID: String) {
        let latest = messageListStore?.state.value.messageList.first { $0.msgID == msgID }
        guard case .audio(let payload)? = latest?.messagePayload else { return }
        if let path = payload.audioPath,
           !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            ChatAudioPlaybackCoordinator.shared.toggle(msgID: msgID, url: URL(fileURLWithPath: path))
        } else if let urlString = payload.audioURL,
                  !urlString.isEmpty,
                  let url = URL(string: urlString) {
            ChatAudioPlaybackCoordinator.shared.toggle(msgID: msgID, url: url)
        }
    }

    private static func audioDuration(from message: MessageInfo) -> Int {
        if case .audio(let payload) = message.messagePayload {
            return payload.audioDuration
        }
        return 0
    }

    static func formatDuration(_ seconds: Int) -> String {
        return "\(max(seconds, 0))\u{2033}"
    }
}

/// Prototype icon `play`: M8.6 5.4 l10 6.6 -10 6.6 z in a 24pt viewBox, scaled to the view.
/// Shared with the video bubble's play badge.
final class VoicePlayGlyphView: UIView {
    var color: UIColor = .white { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let scale = bounds.width / 24
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 8.6 * scale, y: 5.4 * scale))
        path.addLine(to: CGPoint(x: 18.6 * scale, y: 12 * scale))
        path.addLine(to: CGPoint(x: 8.6 * scale, y: 18.6 * scale))
        path.close()
        color.setFill()
        path.fill()
    }
}

/// 2pt rounded bars spread across the width; `progress < 0` paints every bar idle, otherwise bars
/// up to the progress are "played".
private final class VoiceWaveView: UIView {
    var heights: [CGFloat] = [] { didSet { setNeedsDisplay() } }
    var progress: CGFloat = -1 { didSet { setNeedsDisplay() } }
    private var idle = UIColor.white
    private var unplayed = UIColor.gray
    private var played = UIColor.white

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(idle: UIColor, unplayed: UIColor, played: UIColor) {
        self.idle = idle
        self.unplayed = unplayed
        self.played = played
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let count = heights.count
        guard count > 0 else { return }
        let barWidth: CGFloat = 2
        let gap = count > 1 ? (bounds.width - barWidth * CGFloat(count)) / CGFloat(count - 1) : 0
        let playedBars = progress < 0 ? -1 : Int((progress * CGFloat(count)).rounded())
        for index in 0..<count {
            let color: UIColor
            if playedBars < 0 { color = idle } else if index < playedBars { color = played } else { color = unplayed }
            color.setFill()
            let x = CGFloat(index) * (barWidth + gap)
            let barRect = CGRect(x: x, y: (bounds.height - heights[index]) / 2, width: barWidth, height: heights[index])
            UIBezierPath(roundedRect: barRect, cornerRadius: 1).fill()
        }
    }
}
