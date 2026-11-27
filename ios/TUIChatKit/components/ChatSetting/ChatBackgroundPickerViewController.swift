import UIKit
import SnapKit
import Kingfisher
import AtomicX

final class ChatBackgroundPickerViewController: UIViewController {
    private static let panelHeightRatio: CGFloat = 0.65

    private static let panelCornerRadius: CGFloat = CGFloat(RadiusScheme.largeRadius)

    private static let headerHorizontalPadding: CGFloat = CGFloat(SpacingScheme.bubbleSpacing)

    private static let headerVerticalPadding: CGFloat = 14

    private static let closeButtonSize: CGFloat = 32

    private static let columnCount: CGFloat = 3

    private static let gridPadding: CGFloat = CGFloat(SpacingScheme.iconIconSpacing)

    private static let cellSpacing: CGFloat = CGFloat(SpacingScheme.smallSpacing)

    /// Thumbnails are phone-shaped (9:19.5) so the full-screen presets show uncropped.
    private static let previewAspect: CGFloat = 19.5 / 9

    private static let dimAlpha: CGFloat = 0.4

    private let conversationID: String

    private let onSelected: (String?) -> Void

    private let items = ChatBackgroundPresetProvider.presetItems()

    private let selectedURI: String?

    private let dimView = UIControl()

    private let panelView = UIView()

    private let titleLabel = UILabel()

    private let closeButton = UIButton(type: .custom)

    private var collectionView: UICollectionView?

    private var didPlayEnter = false

    private var isLeaving = false

    init(conversationID: String, onSelected: @escaping (String?) -> Void) {
        self.conversationID = conversationID
        self.onSelected = onSelected
        self.selectedURI = ChatBackgroundStore.shared.imageURI(forConversationID: conversationID)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        constructViewHierarchy()
        activateConstraints()
        bindInteraction()
        setupViewStyle()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        playEnterIfNeeded()
    }

    /// The dim fades in while the panel rises from the bottom edge (the system transition is a plain cross dissolve).
    private func playEnterIfNeeded() {
        guard !didPlayEnter else { return }
        didPlayEnter = true
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let hidden = UIScreen.main.bounds.height * Self.panelHeightRatio
        dimView.alpha = 0
        panelView.transform = CGAffineTransform(translationX: 0, y: hidden)
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            self.dimView.alpha = 1
            self.panelView.transform = .identity
        }
    }

    /// Slides the panel back down, then removes the controller without a second system animation.
    private func animateDismiss() {
        guard !isLeaving else { return }
        isLeaving = true
        guard !UIAccessibility.isReduceMotionEnabled else { return dismiss(animated: false) }
        let hidden = panelView.bounds.height
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn]) {
            self.dimView.alpha = 0
            self.panelView.transform = CGAffineTransform(translationX: 0, y: hidden)
        } completion: { _ in
            self.dismiss(animated: false)
        }
    }

    private func constructViewHierarchy() {
        view.addSubview(dimView)
        view.addSubview(panelView)
        panelView.addSubview(titleLabel)
        panelView.addSubview(closeButton)
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = Self.cellSpacing
        layout.minimumLineSpacing = Self.cellSpacing
        layout.sectionInset = UIEdgeInsets(
            top: 0,
            left: Self.gridPadding,
            bottom: Self.gridPadding,
            right: Self.gridPadding
        )
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.register(ChatBackgroundPreviewCell.self, forCellWithReuseIdentifier: ChatBackgroundPreviewCell.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        self.collectionView = collectionView
        panelView.addSubview(collectionView)
    }

    private func activateConstraints() {
        dimView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        panelView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(UIScreen.main.bounds.height * Self.panelHeightRatio)
        }
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(Self.headerVerticalPadding)
        }
        closeButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Self.headerHorizontalPadding)
            make.centerY.equalTo(titleLabel)
            make.width.height.equalTo(Self.closeButtonSize)
        }
        collectionView?.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(Self.headerVerticalPadding)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func bindInteraction() {
        dimView.addTarget(self, action: #selector(handleDismiss), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(handleDismiss), for: .touchUpInside)
    }

    private func setupViewStyle() {
        let colors = TUIChatKitTheme.colors
        view.backgroundColor = .clear
        dimView.backgroundColor = UIColor.black.withAlphaComponent(Self.dimAlpha)
        panelView.backgroundColor = colors.bgColorOperate
        panelView.layer.cornerRadius = Self.panelCornerRadius
        panelView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panelView.layer.masksToBounds = true
        titleLabel.text = LocalizedChatString("SelectChatBackground")
        titleLabel.font = FontScheme.caption1Bold
        titleLabel.textColor = colors.textColorPrimary
        closeButton.setTitle("×", for: .normal)
        closeButton.setTitleColor(colors.textColorSecondary, for: .normal)
        closeButton.titleLabel?.font = FontScheme.body3Regular
        collectionView?.backgroundColor = colors.bgColorOperate
    }

    @objc private func handleDismiss() {
        animateDismiss()
    }

    private func isItemSelected(_ item: ChatBackgroundPresetItem) -> Bool {
        if item.isDefault {
            return selectedURI == nil
        }
        return item.imageURI == selectedURI
    }
}

extension ChatBackgroundPickerViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ChatBackgroundPreviewCell.reuseIdentifier,
            for: indexPath
        ) as? ChatBackgroundPreviewCell else {
            return UICollectionViewCell()
        }
        cell.configure(with: items[indexPath.item], isSelected: isItemSelected(items[indexPath.item]))
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let totalSpacing = Self.gridPadding * 2 + Self.cellSpacing * (Self.columnCount - 1)
        let width = (collectionView.bounds.width - totalSpacing) / Self.columnCount
        return CGSize(width: width, height: (width * Self.previewAspect).rounded())
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelected(items[indexPath.item].imageURI)
        animateDismiss()
    }
}

final class ChatBackgroundPreviewCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatBackgroundPreviewCell"

    private static let contentCornerRadius: CGFloat = CGFloat(RadiusScheme.smallRadius)

    private static let selectedBorderWidth: CGFloat = 2

    private let previewImageView = UIImageView()

    private let defaultLabel = UILabel()

    private let nameLabel = UILabel()

    private let nameScrim = CAGradientLayer()

    private let checkBadge = UIView()

    private let checkIcon = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(previewImageView)
        contentView.addSubview(defaultLabel)
        contentView.layer.addSublayer(nameScrim)
        contentView.addSubview(nameLabel)
        contentView.addSubview(checkBadge)
        checkBadge.addSubview(checkIcon)
        nameScrim.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.5).cgColor]
        nameLabel.font = .adaptiveSystemFont(ofSize: 12, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.layer.shadowColor = UIColor.black.cgColor
        nameLabel.layer.shadowOpacity = 0.4
        nameLabel.layer.shadowRadius = 3
        nameLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        nameLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(6)
            make.bottom.equalToSuperview().offset(-8)
        }
        checkBadge.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(6)
            make.trailing.equalToSuperview().offset(-6)
            make.width.height.equalTo(20)
        }
        checkIcon.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        checkBadge.layer.cornerRadius = 10
        checkBadge.isHidden = true
        checkIcon.image = UIImage(
            systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        )
        checkIcon.tintColor = .white
        previewImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        defaultLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        let colors = TUIChatKitTheme.colors
        contentView.backgroundColor = colors.bgColorTopBar
        contentView.layer.cornerRadius = Self.contentCornerRadius
        contentView.layer.masksToBounds = true
        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
        defaultLabel.font = FontScheme.caption2Regular
        defaultLabel.textColor = colors.textColorSecondary
        defaultLabel.text = LocalizedChatString("ChatBackgroundDefault")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height: CGFloat = 46
        nameScrim.frame = CGRect(x: 0, y: contentView.bounds.height - height, width: contentView.bounds.width, height: height)
    }

    func configure(with item: ChatBackgroundPresetItem, isSelected: Bool) {
        let showsName = item.nameKey != nil
        nameLabel.isHidden = !showsName
        nameScrim.isHidden = !showsName
        nameLabel.text = item.nameKey.map { LocalizedChatString($0) }
        let colors = TUIChatKitTheme.colors
        contentView.layer.borderWidth = isSelected ? Self.selectedBorderWidth : 0
        contentView.layer.borderColor = isSelected ? colors.buttonColorPrimaryDefault.cgColor : nil
        checkBadge.isHidden = !isSelected
        checkBadge.backgroundColor = colors.buttonColorPrimaryDefault
        if item.isDefault {
            previewImageView.isHidden = true
            previewImageView.image = nil
            defaultLabel.isHidden = false
        } else {
            defaultLabel.isHidden = true
            previewImageView.isHidden = false
            if let thumbnail = item.thumbnailURI {
                if let local = ChatBackgroundPresetProvider.thumbnailImage(for: thumbnail) {
                    previewImageView.image = local
                } else {
                    previewImageView.kf.setImage(with: URL(string: thumbnail))
                }
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        previewImageView.kf.cancelDownloadTask()
        previewImageView.image = nil
        contentView.layer.borderWidth = 0
    }
}
