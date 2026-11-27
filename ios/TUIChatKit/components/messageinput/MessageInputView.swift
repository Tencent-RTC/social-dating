import AtomicXCore
import Combine
import SnapKit
import UIKit

public protocol MessageInputConfigProtocol {
    var isShowAudioRecorder: Bool { get }
    var isShowPhotoTaker: Bool { get }
    var isShowMore: Bool { get }
    var isShowSendButton: Bool { get }
    var isShowEmoji: Bool { get }
    var enableReadReceipt: Bool { get }
    var enableMention: Bool { get }
    var enableLongPressToTalk: Bool { get }
    var isShowVideoCall: Bool { get }
    var isShowAudioCall: Bool { get }
    var enableTyping: Bool { get }
    var audioMaxRecordDurationMs: Int { get }
    var actionCustomizer: MessageInputActionCustomizer? { get }
    var appearance: MessageInputAppearance? { get }
}

public enum MessageInputPanel {
    case none
    case keyboard
    case emoji
    case more
}

public struct MessageInputAppearance {
    public var fieldBackgroundColor: UIColor?
    public var fieldCornerRadius: CGFloat?
    public var fieldMinHeight: CGFloat?
    public var placeholder: String?
    public var placeholderAlignment: NSTextAlignment?
    public var audioButtonImage: UIImage?
    public var audioButtonActiveImage: UIImage?
    public var audioButtonTint: UIColor?
    public var audioButtonKeepsColors: Bool
    public var audioButtonSize: CGFloat?
    public var sendButtonTitle: String?
    public var sendButtonGradient: [UIColor]?
    public var sendButtonHeight: CGFloat?
    public var sendButtonFont: UIFont?

    public init(fieldBackgroundColor: UIColor? = nil,
                fieldCornerRadius: CGFloat? = nil,
                fieldMinHeight: CGFloat? = nil,
                placeholder: String? = nil,
                placeholderAlignment: NSTextAlignment? = nil,
                audioButtonImage: UIImage? = nil,
                audioButtonActiveImage: UIImage? = nil,
                audioButtonTint: UIColor? = nil,
                audioButtonKeepsColors: Bool = false,
                audioButtonSize: CGFloat? = nil,
                sendButtonTitle: String? = nil,
                sendButtonGradient: [UIColor]? = nil,
                sendButtonHeight: CGFloat? = nil,
                sendButtonFont: UIFont? = nil) {
        self.fieldBackgroundColor = fieldBackgroundColor
        self.fieldCornerRadius = fieldCornerRadius
        self.fieldMinHeight = fieldMinHeight
        self.placeholder = placeholder
        self.placeholderAlignment = placeholderAlignment
        self.audioButtonImage = audioButtonImage
        self.audioButtonActiveImage = audioButtonActiveImage
        self.audioButtonTint = audioButtonTint
        self.audioButtonKeepsColors = audioButtonKeepsColors
        self.audioButtonSize = audioButtonSize
        self.sendButtonTitle = sendButtonTitle
        self.sendButtonGradient = sendButtonGradient
        self.sendButtonHeight = sendButtonHeight
        self.sendButtonFont = sendButtonFont
    }
}

extension MessageInputConfigProtocol {
    public var isShowVideoCall: Bool { true }
    public var isShowAudioCall: Bool { true }
    public var enableTyping: Bool { true }
    public var audioMaxRecordDurationMs: Int { 60_000 }
    public var actionCustomizer: MessageInputActionCustomizer? { nil }
    public var appearance: MessageInputAppearance? { nil }
}

public struct ChatMessageInputConfig: MessageInputConfigProtocol {
    public var isShowAudioRecorder: Bool {
        return userIsShowAudioRecorder ?? true
    }

    public var isShowPhotoTaker: Bool {
        return userIsShowPhotoTaker ?? true
    }

    public var isShowMore: Bool {
        return userIsShowMore ?? true
    }

    public var isShowSendButton: Bool {
        if let userIsShowSendButton = userIsShowSendButton {
            return userIsShowSendButton
        } else {
            return !AppBuilderConfig.shared.hideSendButton
        }
    }

    public var isShowEmoji: Bool {
        return userIsShowEmoji ?? true
    }

    public var enableReadReceipt: Bool {
        if let userEnableReadReceipt = userEnableReadReceipt {
            return userEnableReadReceipt
        } else {
            return AppBuilderConfig.shared.enableReadReceipt
        }
    }

    public var enableMention: Bool {
        return userEnableMention ?? true
    }

    public var enableLongPressToTalk: Bool {
        return userEnableLongPressToTalk ?? true
    }

    public var isShowVideoCall: Bool {
        return userIsShowVideoCall ?? true
    }

    public var isShowAudioCall: Bool {
        return userIsShowAudioCall ?? true
    }

    public var enableTyping: Bool {
        return userEnableTyping ?? true
    }

    public var audioMaxRecordDurationMs: Int {
        return userAudioMaxRecordDurationMs ?? 60_000
    }

    public var actionCustomizer: MessageInputActionCustomizer? {
        return userActionCustomizer
    }

    public var appearance: MessageInputAppearance? {
        return userAppearance
    }

    private let userAppearance: MessageInputAppearance?

    private let userIsShowAudioRecorder: Bool?

    private let userIsShowPhotoTaker: Bool?

    private let userIsShowMore: Bool?

    private let userIsShowSendButton: Bool?

    private let userIsShowEmoji: Bool?

    private let userEnableReadReceipt: Bool?

    private let userEnableMention: Bool?

    private let userEnableLongPressToTalk: Bool?

    private let userIsShowVideoCall: Bool?

    private let userIsShowAudioCall: Bool?

    private let userEnableTyping: Bool?

    private let userAudioMaxRecordDurationMs: Int?

    private let userActionCustomizer: MessageInputActionCustomizer?

    public init() {
        self.userIsShowAudioRecorder = nil
        self.userIsShowPhotoTaker = nil
        self.userIsShowMore = nil
        self.userIsShowSendButton = nil
        self.userIsShowEmoji = nil
        self.userEnableReadReceipt = nil
        self.userEnableMention = nil
        self.userEnableLongPressToTalk = nil
        self.userIsShowVideoCall = nil
        self.userIsShowAudioCall = nil
        self.userEnableTyping = nil
        self.userAudioMaxRecordDurationMs = nil
        self.userActionCustomizer = nil
        self.userAppearance = nil
    }

    public init(
        isShowAudioRecorder: Bool? = nil,
        isShowPhotoTaker: Bool? = nil,
        isShowMore: Bool? = nil,
        isShowSendButton: Bool? = nil,
        isShowEmoji: Bool? = nil,
        enableReadReceipt: Bool? = nil,
        enableMention: Bool? = nil,
        enableLongPressToTalk: Bool? = nil,
        isShowVideoCall: Bool? = nil,
        isShowAudioCall: Bool? = nil,
        enableTyping: Bool? = nil,
        audioMaxRecordDurationMs: Int? = nil,
        actionCustomizer: MessageInputActionCustomizer? = nil,
        appearance: MessageInputAppearance? = nil
    ) {
        self.userIsShowAudioRecorder = isShowAudioRecorder
        self.userIsShowPhotoTaker = isShowPhotoTaker
        self.userIsShowMore = isShowMore
        self.userIsShowSendButton = isShowSendButton
        self.userIsShowEmoji = isShowEmoji
        self.userEnableReadReceipt = enableReadReceipt
        self.userEnableMention = enableMention
        self.userEnableLongPressToTalk = enableLongPressToTalk
        self.userIsShowVideoCall = isShowVideoCall
        self.userIsShowAudioCall = isShowAudioCall
        self.userEnableTyping = enableTyping
        self.userAudioMaxRecordDurationMs = audioMaxRecordDurationMs
        self.userActionCustomizer = actionCustomizer
        self.userAppearance = appearance
    }
}

public enum MessageInputActionIDs {
    public static let album = "messageInput.album"
    public static let takePhoto = "messageInput.takePhoto"
    public static let recordVideo = "messageInput.recordVideo"
    public static let file = "messageInput.file"
    public static let videoCall = "messageInput.videoCall"
    public static let audioCall = "messageInput.audioCall"
}

public typealias MessageInputActionCustomizer = (CustomEditor<MessageInputMenuAction>) -> Void

public struct MessageInputMenuAction: CustomItem {
    public var ID: String

    public let title: String

    public let iconName: String

    public let icon: UIImage?

    public var dangerous: Bool

    public var showRedDot: Bool

    /// The icon is a complete tile bitmap: fill the tile, no tint, no tile background.
    public var fullBleedIcon: Bool

    /// Short pill label (e.g. "NEW") on the tile's top edge; dismissed on tap like the red dot.
    public var badgeText: String?

    public var onClick: () -> Void

    public init(ID: String,
                title: String,
                iconName: String,
                icon: UIImage? = nil,
                dangerous: Bool = false,
                showRedDot: Bool = false,
                fullBleedIcon: Bool = false,
                badgeText: String? = nil,
                onClick: @escaping () -> Void) {
        self.ID = ID
        self.title = title
        self.iconName = iconName
        self.icon = icon
        self.dangerous = dangerous
        self.showRedDot = showRedDot
        self.fullBleedIcon = fullBleedIcon
        self.badgeText = badgeText
        self.onClick = onClick
    }
}

final class MessageInputView: UIView {
    private static let c2cConversationPrefix = "c2c_"

    static let inputInteractNotification = NSNotification.Name("MessageInputInteract")

    static let voiceRecordStartNotification = NSNotification.Name("MessageInputVoiceRecordStart")

    static let typingMessageBusinessID = "user_typing_status"

    var bottomSafeAreaInset: CGFloat {
        get { impl.bottomSafeAreaInset }
        set { impl.bottomSafeAreaInset = newValue }
    }

    var onTypingContentChanged: ((Bool) -> Void)? {
        get { impl.onTypingContentChanged }
        set { impl.onTypingContentChanged = newValue }
    }

    var onMessageSent: (() -> Void)? {
        get { impl.onMessageSent }
        set { impl.onMessageSent = newValue }
    }

    /// Host entry points for a custom quick-action row (design S3): same behaviour as tapping
    /// the built-in emoji / "+" buttons (voice mode exits, keyboard closes, panels exclusive).
    func fillText(_ text: String) { impl.fillText(text) }

    func openEmojiPanel() { impl.showEmojiPanel() }

    func openMorePanel() { impl.showMorePanel() }

    var bottomAccessoryView: UIView? {
        get { impl.bottomAccessoryView }
        set { impl.bottomAccessoryView = newValue }
    }

    var onPanelChanged: ((MessageInputPanel) -> Void)? {
        get { impl.onPanelChanged }
        set { impl.onPanelChanged = newValue }
    }

    func toggleEmojiPanel() { impl.toggleEmojiPanel() }

    func toggleMorePanel() { impl.toggleMorePanel() }

    func collapsePanels() { impl.collapsePanels() }

    @discardableResult
    func performMenuAction(id: String) -> Bool { impl.performMenuAction(id: id) }
    func pickAlbumAndSend() { impl.pickAlbumAndSend() }

    var onSendFailure: ((String) -> Bool)? {
        get { impl.onSendFailure }
        set { impl.onSendFailure = newValue }
    }

    var typingPublisher: AnyPublisher<Bool, Never>? {
        typingController?.typingPublisher
    }

    private let impl: MessageInputViewImpl

    private let typingController: TypingIndicatorController?

    override var intrinsicContentSize: CGSize {
        impl.intrinsicContentSize
    }

    init(conversationID: String, config: MessageInputConfigProtocol = ChatMessageInputConfig()) {
        impl = MessageInputViewImpl(conversationID: conversationID, config: config)
        if config.enableTyping, conversationID.hasPrefix(Self.c2cConversationPrefix) {
            let currentUserID = LoginStore.shared.state.value.loginUserInfo?.userID
            typingController = TypingIndicatorController(conversationID: conversationID, currentUserID: currentUserID)
        } else {
            typingController = nil
        }
        super.init(frame: .zero)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(impl)
        impl.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        impl.onIntrinsicContentSizeInvalidated = { [weak self] in
            self?.invalidateIntrinsicContentSize()
        }
        impl.onAnimateSuperviewLayout = { [weak self] in
            self?.superview?.layoutIfNeeded()
        }
    }

    func sendTypingStatus(hasContent: Bool) {
        typingController?.sendTypingStatus(hasContent: hasContent)
    }

    func invalidateTypingIndicator() {
        typingController?.invalidate()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct MessagePlaceholderInfo {
    enum MediaKind {
        case image
        case video
    }

    let placeholderID: String

    let mediaKind: MediaKind

    let thumbnailPath: String?

    let thumbnailSize: CGSize

    let mediaPath: String?

    let videoDuration: Int

    let progress: Int

    init(placeholderID: String,
         mediaKind: MediaKind,
         thumbnailPath: String?,
         thumbnailSize: CGSize,
         mediaPath: String? = nil,
         videoDuration: Int = 0,
         progress: Int = 0) {
        self.placeholderID = placeholderID
        self.mediaKind = mediaKind
        self.thumbnailPath = thumbnailPath
        self.thumbnailSize = thumbnailSize
        self.mediaPath = mediaPath
        self.videoDuration = videoDuration
        self.progress = progress
    }
}

final class AlbumPickerPlaceholderStore {
    static let shared = AlbumPickerPlaceholderStore()

    var placeholdersByConversation: AnyPublisher<[String: [MessageInfo]], Never> {
        impl.$placeholdersByConversation.eraseToAnyPublisher()
    }

    private let impl = AlbumPickerPlaceholderStoreImpl.shared

    func upsert(conversationID: String, info: MessagePlaceholderInfo) {
        impl.upsert(conversationID: conversationID, info: info)
    }

    func remove(conversationID: String, placeholderID: String) {
        impl.remove(conversationID: conversationID, placeholderID: placeholderID)
    }

    static func localMediaPath(of message: MessageInfo) -> String? {
        return AlbumPickerPlaceholderStoreImpl.localMediaPath(of: message)
    }

    private init() {}
}
