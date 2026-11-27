import UIKit
import SnapKit
import AtomicXCore
import AtomicX

/// Call record bubble (design `callbubble`, board F / S3): 10x14 padding, 10 gap, a 20pt phone / video
/// glyph and a two-line meta block (title 14/20, sub 10/14 "tap to call back"). Own = `brandGradient`
/// with `textColorButton` painted inside the bubble (the SDK bubble mask clips it); peer = the normal
/// reciprocal bubble with a primary-coloured glyph.
///
/// Only presentation changed: the title is still the SDK's fixed-format display string and the message
/// payload / businessID / call-back behaviour are untouched.
final class MessageCallContentView: UIView, MessageContentView {
    private static let horizontalInset: CGFloat = 14

    private static let verticalInset: CGFloat = 10

    private static let iconTextSpacing: CGFloat = 10

    private static let iconSize: CGFloat = 20

    private static let textMaxLines = 2

    private let fillGradientLayer = CAGradientLayer()

    private let iconImageView = UIImageView()

    private let titleLabel = UILabel()

    private let subLabel = UILabel()

    private var currentMessage: MessageInfo?

    private var currentCallModel: CallMessageModel?

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        constructViewHierarchy()
        activateConstraints()
        setupViewStyle()
        bindInteraction()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fillGradientLayer.frame = bounds
    }

    // MARK: - MessageContentView

    func bind(message: MessageInfo, context: MessageContentContext) {
        guard let callModel = CallMessageParser.parse(message) else {
            currentMessage = nil
            currentCallModel = nil
            titleLabel.text = ""
            subLabel.isHidden = true
            iconImageView.isHidden = true
            fillGradientLayer.isHidden = true
            return
        }
        currentMessage = message
        currentCallModel = callModel

        let colors = TUIChatKitTheme.colors
        let isSelf = context.isSelf
        fillGradientLayer.isHidden = !isSelf
        if isSelf {
            fillGradientLayer.colors = [colors.buttonColorPrimaryDefault.cgColor, colors.tagColorLevel4.cgColor]
        }

        titleLabel.text = callModel.displayString(senderShowName: MessageListHelper.senderShowName(of: message))
        let missed = !isSelf && !callModel.isCaller
            && (callModel.protocolType == .cancel || callModel.protocolType == .timeout)
        if isSelf {
            titleLabel.textColor = colors.textColorButton
        } else {
            titleLabel.textColor = missed ? colors.textColorError : colors.textColorPrimary
        }

        let iconName: String?
        switch callModel.streamMediaType {
        case .voice: iconName = "message_callbubble_phone"
        case .video: iconName = "message_callbubble_video"
        default: iconName = nil
        }
        if let iconName {
            iconImageView.isHidden = false
            iconImageView.image = AtomicXChatResources.image(named: iconName)?.withRenderingMode(.alwaysTemplate)
            iconImageView.tintColor = isSelf ? colors.textColorButton : colors.buttonColorPrimaryDefault
        } else {
            iconImageView.isHidden = true
        }

        let canReCall = callModel.streamMediaType == .voice || callModel.streamMediaType == .video
        subLabel.isHidden = !canReCall
        subLabel.text = LocalizedChatString("CallTapToCallback")
        subLabel.textColor = isSelf ? colors.textColorButton.withAlphaComponent(0.88) : colors.textColorSecondary
        applyLayout(iconVisible: !iconImageView.isHidden)
    }

    // MARK: - Layout

    private func constructViewHierarchy() {
        layer.insertSublayer(fillGradientLayer, at: 0)
        addSubview(iconImageView)
        addSubview(titleLabel)
        addSubview(subLabel)
    }

    private func activateConstraints() {
        applyLayout(iconVisible: true)
    }

    private func applyLayout(iconVisible: Bool) {
        iconImageView.snp.remakeConstraints { make in
            make.leading.equalToSuperview().offset(Self.horizontalInset)
            make.centerY.equalToSuperview()
            make.size.equalTo(iconVisible ? Self.iconSize : 0)
        }
        titleLabel.snp.remakeConstraints { make in
            make.top.equalToSuperview().offset(Self.verticalInset)
            make.leading.equalTo(iconImageView.snp.trailing).offset(iconVisible ? Self.iconTextSpacing : 0)
            make.trailing.lessThanOrEqualToSuperview().offset(-Self.horizontalInset)
            if subLabel.isHidden { make.bottom.equalToSuperview().offset(-Self.verticalInset) }
        }
        subLabel.snp.remakeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(2)
            make.leading.equalTo(titleLabel)
            make.trailing.lessThanOrEqualToSuperview().offset(-Self.horizontalInset)
            make.bottom.equalToSuperview().offset(-Self.verticalInset)
        }
    }

    private func setupViewStyle() {
        fillGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fillGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        fillGradientLayer.isHidden = true
        titleLabel.font = .adaptiveSystemFont(ofSize: 14)
        titleLabel.numberOfLines = Self.textMaxLines
        subLabel.font = .adaptiveSystemFont(ofSize: 10)
        iconImageView.contentMode = .scaleAspectFit
    }

    private func bindInteraction() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    @objc private func handleTap() {
        guard let message = currentMessage, let callModel = currentCallModel else { return }
        let targetUserID: String
        if callModel.isCaller {
            targetUserID = callModel.inviteeList.first ?? message.to.trimmingCharacters(in: .whitespaces)
        } else {
            targetUserID = callModel.caller.trimmingCharacters(in: .whitespaces)
        }
        guard !targetUserID.isEmpty else { return }
        let mediaType: ChatCallEventPublisher.MediaType = callModel.streamMediaType == .video ? .video : .audio
        DataReport.reportInteractionMetrics(.chatInvokeCall)
        ChatCallEventPublisher.publishStartCall(participantIDs: [targetUserID], mediaType: mediaType)
    }
}
