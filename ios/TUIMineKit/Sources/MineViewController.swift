import UIKit
import Combine
import AtomicXCore
import AtomicX
import TUIHostBase

/// Mine (design B4 `527:2525`): header 「我的」, profile card, diamond wallet card, an appearance / language
/// group and a menu group, each block on the list surface with an 8pt background band between them.
///
/// Exactly three fields are real IM data: avatar, nickname and userID. Everything else (signature,
/// tags, city, wallet, menu values) is loaded from MineKit's MineDataSource and never written back to the SDK.
/// With `previewIdentity` (no login) that sample identity is shown instead of the IM profile.
public final class MineViewController: DemoTabRootController {
    private let accountId: String
    private let previewIdentity: MineIdentity?
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let state = HostStateView()
    private var nameLabel: UILabel?
    private var uidLabel: UILabel?
    private var signLabel: UILabel?
    private var profileCancellable: AnyCancellable?
    private var avatarHolder: UIView?

    public init(accountId: String, previewIdentity: MineIdentity? = nil) {
        self.accountId = accountId
        self.previewIdentity = previewIdentity
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) { fatalError() }

    private var preview: Bool { previewIdentity != nil }

    public override func viewDidLoad() {
        super.viewDidLoad()
        let tokens = Host.tokens
        view.backgroundColor = tokens.bgColorTopBar

        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = tokens.bgColorDefault
        stack.axis = .vertical
        stack.spacing = HostMetrics.meBlockGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        let body = UIView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        state.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(scroll)
        body.addSubview(state)
        body.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(body)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            body.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.topAnchor.constraint(equalTo: body.topAnchor), scroll.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: body.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            state.topAnchor.constraint(equalTo: body.topAnchor), state.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            state.leadingAnchor.constraint(equalTo: body.leadingAnchor), state.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        load()
    }

    private func load() {
        state.showLoading()
        MineKit.dataSource.loadContent { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let content):
                    self.state.hide()
                    self.render(content)
                case .failure:
                    self.state.showError { [weak self] in self?.load() }
                }
            }
        }
    }

    private func render(_ mine: MineContent) {
        let tokens = Host.tokens
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.addArrangedSubview(block(profileCard(mine)))
        stack.addArrangedSubview(block(walletBlock(mine)))
        stack.addArrangedSubview(block(preferenceGroup()))
        for group in mine.menuGroups { stack.addArrangedSubview(block(menuGroup(group))) }
        if MineKit.actions.isLogoutAvailable() { stack.addArrangedSubview(block(logoutRow())) }
        if !preview { loadProfile() }
    }

    private func block(_ child: UIView) -> UIView {
        let wrap = UIView()
        wrap.backgroundColor = Host.tokens.bgColorTopBar
        child.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(child)
        NSLayoutConstraint.activate([child.topAnchor.constraint(equalTo: wrap.topAnchor), child.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
                                     child.leadingAnchor.constraint(equalTo: wrap.leadingAnchor), child.trailingAnchor.constraint(equalTo: wrap.trailingAnchor)])
        return wrap
    }

    // MARK: profile card

    private func profileCard(_ mine: MineContent) -> UIView {
        let tokens = Host.tokens
        let pad = HostMetrics.screenPaddingH
        let name = label(previewIdentity?.nickname ?? accountId, 20, tokens.textColorPrimary, bold: true)
        name.numberOfLines = 1
        nameLabel = name
        let uid = label(previewIdentity?.idText ?? DemoText.get("demo_id_city", accountId, mine.city), 14, tokens.textColorSecondary)
        uid.numberOfLines = 1
        uidLabel = uid
        let tags = UIStackView(arrangedSubviews: mine.tags.map { Host.verifiedTag($0.text) } + [UIView()])
        tags.axis = .horizontal
        tags.spacing = 6
        let id = UIStackView(arrangedSubviews: [name, uid, tags])
        id.axis = .vertical
        id.spacing = 4
        id.alignment = .leading

        let edit = UIButton(type: .custom)
        edit.setTitle(mine.editLabel, for: .normal)
        edit.setTitleColor(tokens.textColorPrimary, for: .normal)
        edit.titleLabel?.font = .adaptiveSystemFont(ofSize: 14)
        edit.backgroundColor = tokens.bgColorFunction
        edit.layer.cornerRadius = 16
        edit.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        edit.translatesAutoresizingMaskIntoConstraints = false
        edit.heightAnchor.constraint(equalToConstant: 32).isActive = true
        edit.setContentHuggingPriority(.required, for: .horizontal)
        edit.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            guard MineKit.actions.editProfileTapped(from: self) else { return }
            self.navigationController?.pushViewController(EditProfileViewController(), animated: true)
        }, for: .touchUpInside)

        let avatar = avatarView()
        let top = UIStackView(arrangedSubviews: [avatar, id, UIView(), edit])
        top.axis = .horizontal
        top.alignment = .center
        top.spacing = 12

        // Real signature once the user has set one; until then the design sample line stays as the placeholder.
        let sign = label(mine.signature, 15, tokens.textColorSecondary)
        sign.numberOfLines = 0
        signLabel = sign
        let card = UIStackView(arrangedSubviews: [top, sign])
        card.axis = .vertical
        card.spacing = 12
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: pad, left: pad, bottom: pad, right: pad)
        return card
    }

    /// Avatar 72.
    private func avatarView() -> UIView {
        let size = HostMetrics.meAvatar
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.widthAnchor.constraint(equalToConstant: size).isActive = true
        holder.heightAnchor.constraint(equalToConstant: size).isActive = true
        let face: UIView = previewIdentity.map { Host.sampleAvatar($0.avatar, name: $0.nickname, size: size) }
            ?? DemoRemoteAvatar(name: accountId, url: nil, size: size)
        avatarHolder = holder
        face.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(face)
        NSLayoutConstraint.activate([
            face.topAnchor.constraint(equalTo: holder.topAnchor), face.leadingAnchor.constraint(equalTo: holder.leadingAnchor)
        ])
        return holder
    }

    // MARK: wallet

    /// `.wallet`: h72 r14, brand glow on the left, 1px primary 22% stroke; balance | promo | 充值.
    private func walletBlock(_ mine: MineContent) -> UIView {
        let tokens = Host.tokens
        let wallet = mine.wallet
        let card = HostWalletCard()
        let diamond = UIImageView(image: Host.image("demo_me_diamond"))
        diamond.contentMode = .scaleAspectFit
        diamond.translatesAutoresizingMaskIntoConstraints = false
        diamond.widthAnchor.constraint(equalToConstant: 28).isActive = true
        diamond.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let num = UIStackView(arrangedSubviews: [label(wallet.label, 12, tokens.textColorTertiary),
                                                 label(wallet.balance, 22, tokens.textColorPrimary, bold: true)])
        num.axis = .vertical
        num.spacing = 1
        let bal = UIStackView(arrangedSubviews: [diamond, num])
        bal.axis = .horizontal
        bal.alignment = .center
        bal.spacing = 10
        bal.setContentHuggingPriority(.required, for: .horizontal)

        let sep = UIView()
        sep.backgroundColor = tokens.strokeColorPrimary
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let pill = HostBrandPill(text: wallet.promo)
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let bonus = UIStackView(arrangedSubviews: [label(wallet.promoPre, 12, tokens.textColorSecondary),
                                                   UIImageView(image: Host.image("demo_me_diamond_sm")),
                                                   label(wallet.promoBonus, 12, tokens.textColorWarning, bold: true)])
        bonus.axis = .horizontal
        bonus.alignment = .center
        bonus.spacing = 2
        let promo = UIStackView(arrangedSubviews: [pill, bonus])
        promo.axis = .vertical
        promo.alignment = .leading
        promo.spacing = 4

        let action = DemoGradientButton(type: .custom)
        action.setTitle(wallet.action, for: .normal)
        action.setTitleColor(tokens.textColorButton, for: .normal)
        action.titleLabel?.font = .adaptiveSystemFont(ofSize: 14, weight: .bold)
        action.contentEdgeInsets = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        action.translatesAutoresizingMaskIntoConstraints = false
        action.heightAnchor.constraint(equalToConstant: 32).isActive = true
        action.setContentHuggingPriority(.required, for: .horizontal)
        action.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            MineKit.actions.walletTapped(from: self)
        }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [bal, sep, promo, UIView(), action])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14), row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            card.heightAnchor.constraint(equalToConstant: HostMetrics.walletH)
        ])
        card.isAccessibilityElement = false
        card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(rechargeTapped)))

        let wrap = UIStackView(arrangedSubviews: [card])
        wrap.isLayoutMarginsRelativeArrangement = true
        wrap.layoutMargins = UIEdgeInsets(top: 12, left: HostMetrics.screenPaddingH, bottom: 12, right: HostMetrics.screenPaddingH)
        return wrap
    }

    @objc private func rechargeTapped() { MineKit.actions.walletTapped(from: self) }

    // MARK: logout

    /// Full-width row on the list surface; the caption uses the error colour. Confirms before signing out.
    private func logoutRow() -> UIView {
        let title = DemoText.get("demo_log_out")
        let caption = label(title, 17, Host.tokens.textColorError, bold: true)
        caption.textAlignment = .center
        caption.translatesAutoresizingMaskIntoConstraints = false
        caption.heightAnchor.constraint(equalToConstant: HostMetrics.menuRowH).isActive = true
        caption.isAccessibilityElement = true
        caption.accessibilityLabel = title
        caption.accessibilityTraits = .button
        caption.onTap { [weak self] in self?.confirmLogout() }
        return caption
    }

    private func confirmLogout() {
        let alert = UIAlertController(title: DemoText.get("demo_log_out_title"),
                                      message: DemoText.get("demo_log_out_message"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: DemoText.get("demo_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: DemoText.get("demo_log_out"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            MineKit.actions.logoutConfirmed(from: self)
        })
        present(alert, animated: true)
    }

    // MARK: menu

    private func menuGroup(_ group: [MineMenuItem]) -> UIView {
        rowGroup(group.map { item in
            MineRow(title: item.title, icon: item.icon, value: item.value) { [weak self] in
                guard let self else { return }
                MineKit.actions.menuItemTapped(from: self, item: item)
            }
        })
    }

    private struct MineRow {
        let title: String
        let icon: String
        let value: String
        let action: () -> Void
    }

    private func rowGroup(_ rows: [MineRow]) -> UIView {
        let tokens = Host.tokens
        let list = UIStackView()
        list.axis = .vertical
        list.isLayoutMarginsRelativeArrangement = true
        list.layoutMargins = UIEdgeInsets(top: 4, left: HostMetrics.screenPaddingH, bottom: 4, right: HostMetrics.screenPaddingH)
        for item in rows {
            var parts: [UIView] = []
            if !item.icon.isEmpty {
                let icon = UIImageView()
                HostImage.bind(icon, ref: item.icon)
                icon.contentMode = .scaleAspectFit
                icon.translatesAutoresizingMaskIntoConstraints = false
                icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
                icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
                parts.append(icon)
            }
            parts.append(label(item.title, 17, tokens.textColorPrimary))
            parts.append(UIView())
            if !item.value.isEmpty { parts.append(label(item.value, 14, tokens.textColorTertiary)) }
            parts.append(Host.icon("demo_ic_chevron", size: 12, tint: tokens.textColorDisable))
            let row = UIStackView(arrangedSubviews: parts)
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 12
            if !item.value.isEmpty, parts.count >= 2 { row.setCustomSpacing(8, after: parts[parts.count - 2]) }
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: HostMetrics.menuRowH).isActive = true
            row.isAccessibilityElement = true
            row.accessibilityLabel = item.title
            row.accessibilityTraits = .button
            row.onTap(item.action)
            list.addArrangedSubview(row)
        }
        return list
    }

    // MARK: appearance / language

    private func preferenceGroup() -> UIView {
        rowGroup([
            MineRow(title: DemoText.get("demo_appearance"), icon: "", value: appearanceValue()) { [weak self] in
                guard let self else { return }
                MineKit.actions.showAppearancePicker(from: self)
            },
            MineRow(title: DemoText.get("demo_language"), icon: "", value: languageValue()) { [weak self] in
                guard let self else { return }
                MineKit.actions.showLanguagePicker(from: self)
            },
            MineRow(title: DemoText.get("demo_friend_add_rule"), icon: "", value: friendAddRuleValue()) { [weak self] in
                guard let self else { return }
                MineKit.actions.showFriendAddRulePicker(from: self) { [weak self] in self?.load() }
            }
        ])
    }

    /// Who may add me: read from the real IM profile, never from fixtures.
    private func friendAddRuleValue() -> String {
        switch LoginStore.shared.state.value.loginUserInfo?.allowType {
        case .allowAny: return DemoText.get("demo_allow_any")
        case .denyAny: return DemoText.get("demo_deny_any")
        default: return DemoText.get("demo_need_confirm")
        }
    }

    private func appearanceValue() -> String {
        "\(DemoThemeCoordinator.mode.title) · \(DemoText.get("demo_palette_\(DemoThemeCoordinator.palette)"))"
    }

    private func languageValue() -> String {
        switch DemoLanguage.choice {
        case DemoLanguage.system: return DemoText.get("demo_follow_system")
        case DemoLanguage.zhTW: return DemoText.get("demo_language_zh_hant")
        case DemoLanguage.en: return DemoText.get("demo_language_english")
        default: return DemoText.get("demo_language_zh_hans")
        }
    }

    /// Real nickname / avatar / signature from the IM profile (`LoginStore`, the source the edit page writes to);
    /// fixtures never supply identity. An edit made on the edit page shows up here straight away.
    private func loadProfile() {
        profileCancellable = LoginStore.shared.state.subscribe(StatePublisherSelector(keyPath: \.loginUserInfo))
            .receive(on: RunLoop.main)
            .sink { [weak self] info in
                guard let self, let info else { return }
                let display = (info.nickname?.isEmpty == false ? info.nickname : nil) ?? self.accountId
                self.nameLabel?.text = display
                if let signature = info.selfSignature, !signature.isEmpty { self.signLabel?.text = signature }
                guard let holder = self.avatarHolder else { return }
                let replacement = DemoRemoteAvatar(name: display, url: info.avatarURL, size: HostMetrics.meAvatar)
                replacement.translatesAutoresizingMaskIntoConstraints = false
                holder.subviews.first?.removeFromSuperview()
                holder.insertSubview(replacement, at: 0)
                NSLayoutConstraint.activate([replacement.topAnchor.constraint(equalTo: holder.topAnchor),
                                             replacement.leadingAnchor.constraint(equalTo: holder.leadingAnchor)])
            }
    }
}

/// Brand-gradient capsule with a bold button-coloured caption (wallet promo pill).
final class HostBrandPill: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    init(text: String) {
        super.init(frame: .zero)
        let tokens = Host.tokens
        let gradient = layer as! CAGradientLayer
        gradient.colors = [tokens.buttonColorPrimaryDefault.cgColor, tokens.tagColorLevel4.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer.cornerRadius = 8
        clipsToBounds = true
        let caption = UILabel()
        caption.text = text
        caption.font = .adaptiveSystemFont(ofSize: 10, weight: .bold)
        caption.textColor = tokens.textColorButton
        caption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(caption)
        NSLayoutConstraint.activate([
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            caption.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Wallet card surface: bgColorOperate with a soft brand glow on the left and a 1px brand stroke.
final class HostWalletCard: UIView {
    private let glow = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let tokens = Host.tokens
        backgroundColor = tokens.bgColorOperate
        layer.cornerRadius = HostMetrics.walletRadius
        clipsToBounds = true
        layer.borderWidth = 1 / UIScreen.main.scale
        layer.borderColor = tokens.buttonColorPrimaryDefault.withAlphaComponent(0.22).cgColor
        glow.type = .radial
        glow.colors = [tokens.buttonColorPrimaryDefault.withAlphaComponent(0.30).cgColor, UIColor.clear.cgColor]
        glow.startPoint = CGPoint(x: 0.105, y: 0.5)
        layer.insertSublayer(glow, at: 0)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        glow.frame = bounds
        // Radial end point = start + radius (90 x 80 in the design), as fractions of the bounds.
        glow.endPoint = CGPoint(x: 0.105 + 90 / max(bounds.width, 1), y: 0.5 + 80 / max(bounds.height, 1))
    }
}
