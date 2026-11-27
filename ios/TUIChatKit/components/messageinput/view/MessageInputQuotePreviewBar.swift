import UIKit
import SnapKit
import AtomicX

final class MessageInputQuotePreviewBar: UIView {
    private static let senderNameFontSize: CGFloat = 12

    private static let summaryFontSize: CGFloat = 12

    private static let capsuleInsets = UIEdgeInsets(top: 8, left: 8, bottom: 0, right: 8)

    private static let capsuleRadius: CGFloat = 8

    private static let contentLeadingInset: CGFloat = 10

    private static let contentTrailingGap: CGFloat = 8

    private static let closeButtonSize: CGFloat = 20

    private static let closeButtonTitleFontSize: CGFloat = 18

    private static let closeButtonTrailingInset: CGFloat = 6

    var onClose: (() -> Void)?

    private let contentLabel = UILabel()

    private let closeButton = UIButton(type: .system)

    private let capsule = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        constructViewHierarchy()
        activateConstraints()
        setupViewStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(senderName: String, summary: String) {
        let colors = TUIChatKitTheme.colors
        let attributedText = NSMutableAttributedString()
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.adaptiveSystemFont(ofSize: Self.senderNameFontSize, weight: .bold),
            .foregroundColor: colors.textColorSecondary
        ]
        let summaryAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.adaptiveSystemFont(ofSize: Self.summaryFontSize, weight: .regular),
            .foregroundColor: colors.textColorSecondary
        ]
        attributedText.append(NSAttributedString(string: senderName, attributes: nameAttributes))
        if !summary.isEmpty {
            attributedText.append(NSAttributedString(string: "：", attributes: nameAttributes))
            attributedText.append(NSAttributedString(string: summary, attributes: summaryAttributes))
        }
        contentLabel.attributedText = attributedText
    }

    private func constructViewHierarchy() {
        addSubview(capsule)
        capsule.addSubview(contentLabel)
        capsule.addSubview(closeButton)
    }

    private func activateConstraints() {
        capsule.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(Self.capsuleInsets)
        }

        closeButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Self.closeButtonTrailingInset)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Self.closeButtonSize)
        }

        contentLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.contentLeadingInset)
            make.trailing.equalTo(closeButton.snp.leading).offset(-Self.contentTrailingGap)
            make.centerY.equalToSuperview()
        }
    }

    private func setupViewStyle() {
        let colors = TUIChatKitTheme.colors
        // Design draft strip: r8 capsule on bgColorInput inside an 8pt margin.
        backgroundColor = .clear
        clipsToBounds = true
        isHidden = true
        capsule.backgroundColor = colors.bgColorInput
        capsule.layer.cornerRadius = Self.capsuleRadius
        capsule.clipsToBounds = true

        contentLabel.numberOfLines = 1
        contentLabel.lineBreakMode = .byTruncatingTail
        contentLabel.textAlignment = .natural

        closeButton.setTitle("×", for: .normal)
        closeButton.titleLabel?.font = UIFont.adaptiveSystemFont(ofSize: Self.closeButtonTitleFontSize)
        closeButton.setTitleColor(colors.textColorTertiary, for: .normal)
        closeButton.addTarget(self, action: #selector(handleCloseTapped), for: .touchUpInside)
    }

    @objc private func handleCloseTapped() {
        onClose?()
    }
}
