import UIKit
import SnapKit
import Kingfisher
import AtomicXCore

/// Video bubble per design board F (prototype `.bubble--video`): a fixed 202x136pt frame (design 176x118
/// scaled by 15%) with 16pt corners, a center-cropped snapshot, a 46pt translucent play badge in the middle
/// and a 20pt duration pill at (133, 107). Tap-to-open, loading and violation handling are unchanged.
final class MessageVideoContentView: UIView, MessageContentView {
    private static let frameSize = CGSize(width: 202, height: 136)

    private static let cornerRadius: CGFloat = 16

    private static let playBadgeSize: CGFloat = 46

    private static let playBadgeFillAlpha: CGFloat = 0.2

    private static let playBadgeRingAlpha: CGFloat = 0.55

    private static let playBadgeRingWidth: CGFloat = 1

    private static let playGlyphSize: CGFloat = 18

    private static let durationLeft: CGFloat = 133

    private static let durationTop: CGFloat = 107

    private static let durationHeight: CGFloat = 20

    private static let durationRadius: CGFloat = 10

    private static let durationFillAlpha: CGFloat = 0.55

    private static let durationInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

    private var boundMsgID: String?

    private var hasTriggeredDownload = false

    private var boundMessage: MessageInfo?

    private var onMediaTap: ((MessageInfo) -> Void)?

    private let snapshotView = UIImageView()

    private let playBadge = UIView()

    private let playGlyph = VoicePlayGlyphView()

    private let durationLabel = PaddedLabel(insets: MessageVideoContentView.durationInsets)

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        constructViewHierarchy()
        activateConstraints()
        setupViewStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - MessageContentView

    func bind(message: MessageInfo, context: MessageContentContext) {
        if boundMsgID != message.msgID {
            hasTriggeredDownload = false
        }
        boundMsgID = message.msgID
        boundMessage = message
        onMediaTap = context.onMediaTap

        guard case .video(let payload) = message.messagePayload else {
            applyFrame(width: 0, height: 0)
            showPlaceholder()
            durationLabel.isHidden = true
            return
        }
        applyFrame(width: payload.videoSnapshotWidth, height: payload.videoSnapshotHeight)
        applyDuration(payload.videoDuration)
        loadSnapshot(payload: payload, message: message)
    }

    // MARK: - Private

    private func constructViewHierarchy() {
        addSubview(snapshotView)
        snapshotView.addSubview(playBadge)
        playBadge.addSubview(playGlyph)
        snapshotView.addSubview(durationLabel)
    }

    private func activateConstraints() {
        remakeFrameConstraints(size: Self.frameSize, durationOrigin: CGPoint(x: Self.durationLeft, y: Self.durationTop))
        playBadge.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(Self.playBadgeSize)
        }
        playGlyph.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(Self.playGlyphSize)
        }
    }

    private func applyFrame(width: Int, height: Int) {
        let portrait = Self.isPortrait(width: width, height: height)
        remakeFrameConstraints(size: Self.displayFrame(width: width, height: height), durationOrigin: Self.durationOrigin(isPortrait: portrait))
    }

    private func remakeFrameConstraints(size: CGSize, durationOrigin: CGPoint) {
        snapshotView.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(size.width)
            make.height.equalTo(size.height)
        }
        durationLabel.snp.remakeConstraints { make in
            make.left.equalToSuperview().offset(durationOrigin.x)
            make.top.equalToSuperview().offset(durationOrigin.y)
            make.height.equalTo(Self.durationHeight)
        }
    }

    private static func isPortrait(width: Int, height: Int) -> Bool {
        width > 0 && height > width
    }

    private static func displayFrame(width: Int, height: Int) -> CGSize {
        if isPortrait(width: width, height: height) {
            return CGSize(width: frameSize.height, height: frameSize.width)
        }
        return frameSize
    }

    private static func durationOrigin(isPortrait: Bool) -> CGPoint {
        if isPortrait {
            return CGPoint(
                x: frameSize.height - (frameSize.width - durationLeft),
                y: frameSize.width - (frameSize.height - durationTop)
            )
        }
        return CGPoint(x: durationLeft, y: durationTop)
    }

    private func setupViewStyle() {
        snapshotView.contentMode = .scaleAspectFill
        snapshotView.clipsToBounds = true
        snapshotView.layer.cornerRadius = Self.cornerRadius
        snapshotView.isUserInteractionEnabled = true

        playBadge.backgroundColor = UIColor(white: 1, alpha: Self.playBadgeFillAlpha)
        playBadge.layer.cornerRadius = Self.playBadgeSize / 2
        playBadge.layer.borderWidth = Self.playBadgeRingWidth
        playBadge.layer.borderColor = UIColor(white: 1, alpha: Self.playBadgeRingAlpha).cgColor
        playBadge.isUserInteractionEnabled = false
        playGlyph.color = .white
        playGlyph.isUserInteractionEnabled = false

        durationLabel.font = FontScheme.caption4Regular
        durationLabel.textColor = .white
        durationLabel.backgroundColor = UIColor(white: 0, alpha: Self.durationFillAlpha)
        durationLabel.textAlignment = .center
        durationLabel.layer.cornerRadius = Self.durationRadius
        durationLabel.clipsToBounds = true
        durationLabel.layer.masksToBounds = true

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleMediaTap)))
    }

    @objc private func handleMediaTap() {
        guard let message = boundMessage else { return }

        guard message.status != .violation else { return }
        onMediaTap?(message)
    }

    private func applyDuration(_ seconds: Int) {
        durationLabel.isHidden = false
        durationLabel.text = Self.formatDuration(seconds)
    }

    private func loadSnapshot(payload: VideoMessagePayload, message: MessageInfo) {
        if let path = payload.videoSnapshotPath,
           !path.isEmpty,
           FileManager.default.fileExists(atPath: path),
           let image = UIImage(contentsOfFile: path) {
            snapshotView.kf.cancelDownloadTask()
            snapshotView.image = image
            snapshotView.backgroundColor = .clear
            playBadge.isHidden = false
            return
        }
        if let urlString = payload.videoSnapshotURL,
           !urlString.isEmpty,
           let url = URL(string: urlString) {
            snapshotView.backgroundColor = TUIChatKitTheme.colors.bgColorBubbleReciprocal
            snapshotView.kf.setImage(with: url)
            playBadge.isHidden = false
            return
        }
        showPlaceholder()
        triggerDownloadIfNeeded(message: message)
    }

    private func showPlaceholder() {
        snapshotView.kf.cancelDownloadTask()
        snapshotView.image = nil
        snapshotView.backgroundColor = TUIChatKitTheme.colors.bgColorBubbleReciprocal
        playBadge.isHidden = false
    }

    private func triggerDownloadIfNeeded(message: MessageInfo) {
        guard !hasTriggeredDownload else { return }
        guard message.status != .sending else { return }
        hasTriggeredDownload = true
        MessageActionStore.create(message: message).downloadMedia(quality: .thumbnail) { _ in }
    }

    private static func formatDuration(_ seconds: Int) -> String {
        return DateHelper.formatDurationSeconds(seconds)
    }
}

private final class PaddedLabel: UILabel {
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }

    private let insets: UIEdgeInsets

    init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }
}
