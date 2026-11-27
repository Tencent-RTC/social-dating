import UIKit
import SnapKit
import Kingfisher
import AtomicXCore

/// Image bubble per design S4 (prototype `.bubble--image`): a 173x138pt frame (design 150x120 scaled
/// by 15%; portrait images keep the 173pt width and grow to at most 230pt tall) with 14pt corners and a center-cropped thumbnail, no bubble fill. Tap-to-open, loading and
/// violation handling are unchanged.
final class MessageImageContentView: UIView, MessageContentView {
    private static let frameSize = CGSize(width: 173, height: 138)

    private static let portraitMaxHeight: CGFloat = 230

    private static let cornerRadius: CGFloat = 14

    private static let placeholderIconSize: CGFloat = 46

    private var boundMsgID: String?

    private var hasTriggeredDownload = false

    private var boundMessage: MessageInfo?

    private var onMediaTap: ((MessageInfo) -> Void)?

    private let imageView = UIImageView()

    private let placeholderIcon = UIImageView()

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

        guard case .image(let payload) = message.messagePayload else {
            remakeImageConstraints(size: Self.frameSize)
            showPlaceholder()
            return
        }
        remakeImageConstraints(size: Self.displayFrame(width: payload.originalImageWidth, height: payload.originalImageHeight))
        loadThumbnail(payload: payload, message: message)
    }

    // MARK: - Private

    private func constructViewHierarchy() {
        addSubview(imageView)
        imageView.addSubview(placeholderIcon)
    }

    private func activateConstraints() {
        remakeImageConstraints(size: Self.frameSize)
        placeholderIcon.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(Self.placeholderIconSize)
        }
    }

    private func remakeImageConstraints(size: CGSize) {
        imageView.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(size.width)
            make.height.equalTo(size.height)
        }
    }

    private static func isPortrait(width: Int, height: Int) -> Bool {
        width > 0 && height > width
    }

    private static func displayFrame(width: Int, height: Int) -> CGSize {
        if isPortrait(width: width, height: height) {
            let scaled = (frameSize.width * CGFloat(height) / CGFloat(width)).rounded()
            return CGSize(width: frameSize.width, height: min(max(scaled, frameSize.width), portraitMaxHeight))
        }
        return frameSize
    }

    private func setupViewStyle() {
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = Self.cornerRadius
        placeholderIcon.contentMode = .scaleAspectFit
        placeholderIcon.image = UIImage(systemName: "photo")
        placeholderIcon.tintColor = TUIChatKitTheme.colors.textColorSecondary
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleMediaTap)))
    }

    @objc private func handleMediaTap() {
        guard let message = boundMessage else { return }

        guard message.status != .violation else { return }
        onMediaTap?(message)
    }

    private func loadThumbnail(payload: ImageMessagePayload, message: MessageInfo) {
        if let path = payload.largeImagePath ?? payload.originalImagePath,
           !path.isEmpty,
           FileManager.default.fileExists(atPath: path),
           let image = UIImage(contentsOfFile: path) {
            imageView.kf.cancelDownloadTask()
            imageView.image = image
            placeholderIcon.isHidden = true
            imageView.backgroundColor = .clear
            return
        }
        if let urlString = payload.largeImageURL ?? payload.originalImageURL ?? payload.thumbImageURL,
           !urlString.isEmpty,
           let url = URL(string: urlString) {
            placeholderIcon.isHidden = true
            imageView.backgroundColor = TUIChatKitTheme.colors.bgColorBubbleReciprocal
            imageView.kf.setImage(with: url)
            return
        }
        showPlaceholder()
        triggerDownloadIfNeeded(message: message)
    }

    private func showPlaceholder() {
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        imageView.backgroundColor = TUIChatKitTheme.colors.bgColorBubbleReciprocal
        placeholderIcon.isHidden = false
    }

    private func triggerDownloadIfNeeded(message: MessageInfo) {
        guard !hasTriggeredDownload else { return }
        hasTriggeredDownload = true
        MessageActionStore.create(message: message).downloadMedia(quality: .standard) { _ in }
    }
}
