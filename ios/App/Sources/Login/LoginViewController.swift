import UIKit
import AtomicXCore
import AtomicX
import TUICallKit
import RTCRoomEngine
import TUIHostBase

private enum LoginNetworkWarmUp {
    private static var started = false

    static func trigger() {
        guard !started else { return }
        started = true
        let target = PresetAccount.load().first?.avatar
        guard let target, let url = URL(string: target) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }
}

private struct PresetAvatarRef {
    weak var view: UIImageView?
    let ref: String
}

private struct PresetAccount: Decodable {
    let userId: String
    let name: String
    let avatar: String

    private struct File: Decodable { let presets: [PresetAccount] }

    static func load() -> [PresetAccount] {
        DemoFixtures.load(File.self, "login-presets")?.presets ?? []
    }
}

private final class PresetOverlayView: UIView, UIGestureRecognizerDelegate {
    var onOutsideTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() { onOutsideTap?() }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view === self
    }
}

/// Radial light behind the login hero (design L1: brand violet / pink glows).
private final class LoginGlowView: UIView {
    private let gradient = CAGradientLayer()

    init(color: UIColor, alpha: CGFloat) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        translatesAutoresizingMaskIntoConstraints = false
        gradient.type = .radial
        gradient.colors = [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

/// Views that own their brand gradient and size it in their own layout pass (a parent-driven frame is still 0x0 on the
/// first layout of nested constraints, which left the logo tile and the login pill without a fill).
private final class LoginGradientView: UIView {
    let gradient: CAGradientLayer

    init(gradient: CAGradientLayer) {
        self.gradient = gradient
        super.init(frame: .zero)
        layer.insertSublayer(gradient, at: 0)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

private final class LoginGradientButton: UIButton {
    let gradient: CAGradientLayer

    init(gradient: CAGradientLayer) {
        self.gradient = gradient
        super.init(frame: .zero)
        layer.insertSublayer(gradient, at: 0)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

final class LoginViewController: UIViewController, UITextFieldDelegate {

    // Recreated by `rebuild()` so a language / palette / mode change repaints the whole page.
    private var userField = LoginViewController.makeField()
    private static func makeField() -> UITextField { UITextField() }
    private var inputFrame = UIView()
    private var loginGradient = Host.brandGradientLayer()
    private lazy var loginButton = LoginGradientButton(gradient: loginGradient)
    private var logoGradient = Host.brandGradientLayer(startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 1, y: 1))
    private lazy var logoTile = LoginGradientView(gradient: logoGradient)
    private var card = UIView()
    private var strings = LoginStrings()
    private var contentTop: NSLayoutConstraint?
    private var loginInProgress = false
    private var presetOverlay: PresetOverlayView?
    private var selectedPreset: PresetAccount?
    private var inputRow = UIStackView()
    private var userIcon = UIView()
    private var presetChip: UIView?
    private var presetAvatars: [PresetAvatarRef] = []
    private var activeObserver: NSObjectProtocol?
    private var loggedIn = false
    private var resuming: Bool
    private var splashOverlay: UIView?
    private var resumeToken = 0

    init(resuming: Bool = false) {
        self.resuming = resuming
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    static var hasResumableLogin: Bool {
        guard GenerateTestUserSig.isConfigured, let saved = DemoLoginStore.load() else { return false }
        return saved.sdkAppID == GenerateTestUserSig.SDKAPPID
    }

    private static let contentTopInset: CGFloat = 74

    deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildPage()
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reloadMissingPresetAvatars()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard)))
        if resuming { showSplashOverlay() }
    }

    /// Same violet page and logo as the launch screen, so a saved login goes straight from launch to the home page.
    private func showSplashOverlay() {
        let overlay = UIView()
        overlay.backgroundColor = UIColor(named: "LaunchBackground") ?? UIColor(hex: 0x7C4DFF)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        let logo = UIImageView(image: UIImage(named: "LaunchLogo"))
        logo.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(logo)
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor), overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor), overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            logo.centerXAnchor.constraint(equalTo: overlay.centerXAnchor), logo.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
        ])
        splashOverlay = overlay
        setNeedsStatusBarAppearanceUpdate()
    }

    private func hideSplashOverlay() {
        resuming = false
        guard let overlay = splashOverlay else { return }
        splashOverlay = nil
        UIView.animate(withDuration: 0.2, animations: { overlay.alpha = 0 }, completion: { _ in overlay.removeFromSuperview() })
        setNeedsStatusBarAppearanceUpdate()
    }

    /// (Re)builds glows, hero, card and the floating language / appearance bar from the current locale and palette.
    private func buildPage() {
        strings = LoginStrings()
        view.backgroundColor = Host.tokens.bgColorDefault
        buildGlows()
        buildContent()
        buildTopEntries()
    }

    /// Called after a sheet applied a choice: keeps the typed ID and login state, rebuilds everything else.
    private func rebuild() {
        let typed = userField.text
        let focused = userField.isFirstResponder
        view.subviews.forEach { $0.removeFromSuperview() }
        userField = Self.makeField()
        presetOverlay = nil
        inputFrame = UIView()
        loginGradient = Host.brandGradientLayer()
        loginButton = LoginGradientButton(gradient: loginGradient)
        logoGradient = Host.brandGradientLayer(startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 1, y: 1))
        logoTile = LoginGradientView(gradient: logoGradient)
        card = UIView()
        contentTop = nil
        buildPage()
        if let typed { userField.text = typed }
        applyButtonState()
        if loginInProgress { loginButton.setTitle(strings.loggingIn, for: .normal) }
        if focused { userField.becomeFirstResponder() }
        setNeedsStatusBarAppearanceUpdate()
    }

    /// Top-right pair of round glass buttons (design L1): translate = language, palette = appearance.
    private func buildTopEntries() {
        let tokens = Host.tokens
        let dark = Host.isDark
        let bar = UIStackView()
        bar.axis = .horizontal
        bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false
        func button(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> UIView {
            // UIButton (not a bare UIControl) so the page-level dismiss-keyboard tap does not swallow the touch.
            let item = UIButton(type: .custom)
            item.accessibilityLabel = label
            item.backgroundColor = dark ? UIColor.white.withAlphaComponent(0.08) : UIColor.white.withAlphaComponent(0.72)
            item.layer.cornerRadius = 18
            item.layer.borderWidth = 1
            item.layer.borderColor = (dark ? UIColor.white.withAlphaComponent(0.16) : tokens.strokeColorPrimary).cgColor
            let glyph = Host.icon(icon, size: 20, tint: tokens.textColorPrimary)
            glyph.isUserInteractionEnabled = false
            item.addSubview(glyph)
            NSLayoutConstraint.activate([
                item.widthAnchor.constraint(equalToConstant: 36), item.heightAnchor.constraint(equalToConstant: 36),
                glyph.centerXAnchor.constraint(equalTo: item.centerXAnchor), glyph.centerYAnchor.constraint(equalTo: item.centerYAnchor)
            ])
            item.addAction(UIAction { _ in action() }, for: .touchUpInside)
            return item
        }
        bar.addArrangedSubview(button("demo_login_globe", strings.languageLabel) { [weak self] in self?.showSheet(LoginLanguageSheet()) })
        bar.addArrangedSubview(button("demo_login_palette", strings.appearanceTitle) { [weak self] in self?.showSheet(LoginAppearanceSheet()) })
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)
        ])
    }

    private func showSheet(_ sheet: LoginSheetController) {
        view.endEditing(true)
        sheet.onApplied = { [weak self] in self?.rebuild() }
        present(sheet, animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        LoginNetworkWarmUp.trigger()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        if resuming { return .lightContent }
        return Host.isDark ? .lightContent : .darkContent
    }

    private func buildGlows() {
        let tokens = Host.tokens
        let dark = Host.isDark
        let violet = LoginGlowView(color: tokens.buttonColorPrimaryDefault, alpha: dark ? 0.62 : 0.32)
        let pink = LoginGlowView(color: tokens.tagColorLevel4, alpha: dark ? 0.46 : 0.26)
        let base = LoginGlowView(color: tokens.buttonColorPrimaryDefault, alpha: dark ? 0.22 : 0.12)
        for glow in [violet, pink, base] { view.addSubview(glow) }
        NSLayoutConstraint.activate([
            violet.widthAnchor.constraint(equalToConstant: 460), violet.heightAnchor.constraint(equalToConstant: 460),
            violet.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -110),
            violet.topAnchor.constraint(equalTo: view.topAnchor, constant: -150),
            pink.widthAnchor.constraint(equalToConstant: 360), pink.heightAnchor.constraint(equalToConstant: 360),
            pink.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 120),
            pink.topAnchor.constraint(equalTo: view.topAnchor, constant: -20),
            base.widthAnchor.constraint(equalToConstant: 520), base.heightAnchor.constraint(equalToConstant: 520),
            base.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -80),
            base.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 200)
        ])
    }

    /// 96pt gradient logo tile (bubble + heart glyph) with three twinkles; 10pt headroom above for the stars.
    private func makeLogoZone() -> UIView {
        let tokens = Host.tokens
        let dark = Host.isDark
        let zone = UIView()
        zone.translatesAutoresizingMaskIntoConstraints = false

        let shadow = UIView()
        shadow.translatesAutoresizingMaskIntoConstraints = false
        shadow.layer.shadowColor = tokens.tagColorLevel4.cgColor
        shadow.layer.shadowOpacity = 0.45
        shadow.layer.shadowRadius = 14
        shadow.layer.shadowOffset = CGSize(width: 0, height: 12)
        shadow.layer.shadowPath = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 96, height: 96), cornerRadius: 26).cgPath
        zone.addSubview(shadow)

        logoTile.translatesAutoresizingMaskIntoConstraints = false
        logoTile.layer.cornerRadius = 26
        logoTile.layer.masksToBounds = true
        logoTile.layer.borderWidth = 1
        logoTile.layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
        shadow.addSubview(logoTile)
        let glyph = UIImageView(image: Host.image("demo_login_glyph"))
        glyph.translatesAutoresizingMaskIntoConstraints = false
        logoTile.addSubview(glyph)

        NSLayoutConstraint.activate([
            zone.heightAnchor.constraint(equalToConstant: 106),
            shadow.widthAnchor.constraint(equalToConstant: 96), shadow.heightAnchor.constraint(equalToConstant: 96),
            shadow.centerXAnchor.constraint(equalTo: zone.centerXAnchor),
            shadow.topAnchor.constraint(equalTo: zone.topAnchor, constant: 10),
            logoTile.leadingAnchor.constraint(equalTo: shadow.leadingAnchor), logoTile.trailingAnchor.constraint(equalTo: shadow.trailingAnchor),
            logoTile.topAnchor.constraint(equalTo: shadow.topAnchor), logoTile.bottomAnchor.constraint(equalTo: shadow.bottomAnchor),
            glyph.leadingAnchor.constraint(equalTo: logoTile.leadingAnchor), glyph.trailingAnchor.constraint(equalTo: logoTile.trailingAnchor),
            glyph.topAnchor.constraint(equalTo: logoTile.topAnchor), glyph.bottomAnchor.constraint(equalTo: logoTile.bottomAnchor)
        ])

        func star(_ name: String, size: CGFloat, dx: CGFloat, dy: CGFloat, tint: UIColor, alpha: CGFloat) {
            let icon = Host.icon(name, size: size, tint: tint)
            icon.alpha = alpha
            zone.addSubview(icon)
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: zone.centerXAnchor, constant: dx + size / 2),
                icon.topAnchor.constraint(equalTo: zone.topAnchor, constant: dy)
            ])
        }
        star("demo_login_star_big", size: 22, dx: 93, dy: 0, tint: dark ? .white : tokens.buttonColorPrimaryDefault, alpha: dark ? 0.85 : 0.9)
        star("demo_login_star_small", size: 10, dx: 113, dy: 38, tint: dark ? .white : tokens.tagColorLevel4, alpha: dark ? 0.6 : 0.8)
        star("demo_login_star_left", size: 12, dx: -112, dy: 78, tint: dark ? .white : tokens.buttonColorPrimaryDefault, alpha: dark ? 0.5 : 0.8)
        return zone
    }

    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .adaptiveSystemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func buildContent() {
        let tokens = Host.tokens
        let dark = Host.isDark

        let title = label(DemoText.get("app_name"), size: 34, weight: .bold, color: tokens.textColorPrimary)
        let slogan = label(strings.slogan, size: 14, color: tokens.textColorSecondary)
        let zone = makeLogoZone()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 26
        card.layer.borderWidth = 1
        card.backgroundColor = dark ? tokens.bgColorOperate.withAlphaComponent(0.86) : tokens.bgColorDialog.withAlphaComponent(0.92)
        card.layer.borderColor = (dark ? UIColor.white.withAlphaComponent(0.10) : tokens.strokeColorPrimary).cgColor

        let column = UIStackView(arrangedSubviews: [zone, title, slogan, card])
        column.axis = .vertical
        column.alignment = .center
        column.setCustomSpacing(20, after: zone)
        column.setCustomSpacing(6, after: title)
        column.setCustomSpacing(48, after: slogan)
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        let top = column.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Self.contentTopInset)
        contentTop = top
        NSLayoutConstraint.activate([
            top,
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            zone.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            zone.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            card.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -20)
        ])

        guard GenerateTestUserSig.isConfigured else {
            let text = label(strings.devConfigMissing, size: 15, color: tokens.textColorSecondary)
            text.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(text)
            NSLayoutConstraint.activate([
                text.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
                text.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
                text.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
                text.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22)
            ])
            return
        }

        let heading = label(strings.userIdTitle, size: 15, weight: .bold, color: tokens.textColorPrimary)
        let hint = label(strings.hint, size: 12, color: tokens.textColorSecondary)

        inputFrame.layer.cornerRadius = 14
        inputFrame.backgroundColor = tokens.bgColorInput
        styleInput(focused: false)
        userIcon = Host.icon("demo_login_user", size: 20, tint: tokens.textColorSecondary)
        userField.attributedPlaceholder = NSAttributedString(string: strings.placeholder,
                                                             attributes: [.foregroundColor: tokens.textColorTertiary])
        userField.font = .adaptiveSystemFont(ofSize: 16)
        userField.textColor = tokens.textColorPrimary
        userField.autocorrectionType = .no
        userField.autocapitalizationType = .none
        userField.spellCheckingType = .no
        userField.returnKeyType = .done
        userField.clearButtonMode = .whileEditing
        userField.delegate = self
        userField.addTarget(self, action: #selector(inputChanged), for: .editingChanged)
        userField.text = DemoLoginStore.load()?.userID
        let presetButton = UIButton(type: .system)
        presetButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        presetButton.tintColor = tokens.textColorSecondary
        presetButton.accessibilityLabel = strings.presetAccounts
        presetButton.translatesAutoresizingMaskIntoConstraints = false
        presetButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        presetButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        presetButton.addAction(UIAction { [weak self] _ in self?.togglePresetMenu() }, for: .touchUpInside)
        presetButton.addAction(UIAction { [weak self] _ in self?.view.endEditing(true) }, for: .touchDown)
        inputRow = UIStackView(arrangedSubviews: [userIcon, userField, presetButton])
        presetChip = nil
        inputRow.axis = .horizontal
        inputRow.spacing = 8
        inputRow.alignment = .center
        inputRow.translatesAutoresizingMaskIntoConstraints = false
        inputFrame.addSubview(inputRow)
        NSLayoutConstraint.activate([
            inputRow.leadingAnchor.constraint(equalTo: inputFrame.leadingAnchor, constant: 16),
            inputRow.trailingAnchor.constraint(equalTo: inputFrame.trailingAnchor, constant: -16),
            inputRow.topAnchor.constraint(equalTo: inputFrame.topAnchor),
            inputRow.bottomAnchor.constraint(equalTo: inputFrame.bottomAnchor)
        ])

        loginButton.setTitle(strings.login, for: .normal)
        loginButton.setTitleColor(tokens.textColorButton, for: .normal)
        loginButton.setTitleColor(tokens.textColorButtonDisabled, for: .disabled)
        loginButton.titleLabel?.font = .adaptiveSystemFont(ofSize: 17, weight: .bold)
        loginButton.layer.cornerRadius = 26
        loginButton.clipsToBounds = true
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        loginButton.addAction(UIAction { [weak self] _ in self?.loginButton.alpha = 0.85 }, for: .touchDown)
        loginButton.addAction(UIAction { [weak self] _ in self?.loginButton.alpha = 1 },
                              for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let form = UIStackView(arrangedSubviews: [heading, hint, inputFrame, loginButton])
        form.axis = .vertical
        form.spacing = 16
        form.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(form)
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            form.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
            form.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            form.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            inputFrame.heightAnchor.constraint(equalToConstant: 52),
            loginButton.heightAnchor.constraint(equalToConstant: 52)
        ])
        refreshPresetChip()
        applyButtonState()
    }

    private func refreshPresetChip() {
        presetChip?.removeFromSuperview()
        presetChip = nil
        guard let entry = selectedPreset else {
            userIcon.isHidden = false
            userField.isHidden = false
            return
        }
        let chip = presetChipView(entry)
        inputRow.insertArrangedSubview(chip, at: 1)
        presetChip = chip
        userField.text = entry.userId
        userIcon.isHidden = true
        userField.isHidden = true
    }

    private func presetChipView(_ entry: PresetAccount) -> UIView {
        let tokens = Host.tokens
        let avatar = presetAvatar(entry, size: 32)
        let nameLabel = label(entry.name, size: 15, weight: .bold, color: tokens.textColorPrimary)
        nameLabel.numberOfLines = 1
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        let idLabel = label(entry.userId, size: 12, color: tokens.textColorSecondary)
        idLabel.numberOfLines = 1
        idLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [avatar, nameLabel, idLabel])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        let chip = UIButton(type: .custom)
        chip.accessibilityLabel = "\(entry.name) \(entry.userId)"
        chip.setContentHuggingPriority(.defaultLow, for: .horizontal)
        chip.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: chip.topAnchor),
            stack.bottomAnchor.constraint(equalTo: chip.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: chip.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: chip.trailingAnchor)
        ])
        chip.addAction(UIAction { [weak self] _ in self?.editSelectedPreset() }, for: .touchUpInside)
        return chip
    }

    private func editSelectedPreset() {
        guard !loginInProgress else { return }
        selectedPreset = nil
        refreshPresetChip()
        userField.becomeFirstResponder()
    }

    private func presetAvatar(_ entry: PresetAccount, size: CGFloat) -> UIImageView {
        let avatar = UIImageView()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = size / 2
        avatar.backgroundColor = Host.tokens.bgColorFunction
        avatar.isUserInteractionEnabled = false
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: size),
            avatar.heightAnchor.constraint(equalToConstant: size)
        ])
        HostImage.bind(avatar, ref: entry.avatar)
        presetAvatars.append(PresetAvatarRef(view: avatar, ref: entry.avatar))
        return avatar
    }

    private func reloadMissingPresetAvatars() {
        guard !loggedIn, !presetAvatars.isEmpty else { return }
        presetAvatars = presetAvatars.filter { $0.view != nil }
        for item in presetAvatars where item.view?.image == nil {
            guard let view = item.view else { continue }
            HostImage.bind(view, ref: item.ref)
        }
    }

    private func togglePresetMenu() {
        if presetOverlay != nil { closePresetMenu(); return }
        guard !loginInProgress else { return }
        let tokens = Host.tokens
        let overlay = PresetOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.onOutsideTap = { [weak self] in self?.closePresetMenu() }
        view.addSubview(overlay)
        Host.pin(overlay, to: view)

        let menu = UIView()
        menu.translatesAutoresizingMaskIntoConstraints = false
        menu.backgroundColor = Host.isDark ? tokens.bgColorOperate : tokens.bgColorDialog
        menu.layer.cornerRadius = 14
        menu.layer.borderWidth = 1
        menu.layer.borderColor = (Host.isDark ? UIColor.white.withAlphaComponent(0.10) : tokens.strokeColorPrimary).cgColor
        menu.layer.shadowColor = UIColor.black.cgColor
        menu.layer.shadowOpacity = 0.18
        menu.layer.shadowRadius = 12
        menu.layer.shadowOffset = CGSize(width: 0, height: 4)

        let title = UIView()
        let titleLabel = label(strings.presetAccounts, size: 12, color: tokens.textColorSecondary)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        title.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: title.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: title.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: title.trailingAnchor)
        ])
        let rows = UIStackView(arrangedSubviews: [title] + PresetAccount.load().map(presetRow))
        rows.axis = .vertical
        rows.spacing = 0
        rows.setCustomSpacing(4, after: title)
        rows.isLayoutMarginsRelativeArrangement = true
        rows.layoutMargins = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        rows.translatesAutoresizingMaskIntoConstraints = false
        menu.addSubview(rows)
        overlay.addSubview(menu)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: menu.topAnchor),
            rows.bottomAnchor.constraint(equalTo: menu.bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: menu.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: menu.trailingAnchor),
            menu.leadingAnchor.constraint(equalTo: inputFrame.leadingAnchor),
            menu.trailingAnchor.constraint(equalTo: inputFrame.trailingAnchor)
        ])
        let below = menu.topAnchor.constraint(equalTo: inputFrame.bottomAnchor, constant: 6)
        below.isActive = true
        view.layoutIfNeeded()
        if menu.convert(menu.bounds, to: view).maxY > view.bounds.height - 8 {
            below.isActive = false
            menu.bottomAnchor.constraint(equalTo: inputFrame.topAnchor, constant: -6).isActive = true
        }
        presetOverlay = overlay
    }

    private func closePresetMenu() {
        presetOverlay?.removeFromSuperview()
        presetOverlay = nil
    }

    private func presetRow(_ entry: PresetAccount) -> UIView {
        let tokens = Host.tokens
        let name = entry.name
        let avatar = presetAvatar(entry, size: 36)
        let nameLabel = label(name, size: 15, weight: .bold, color: tokens.textColorPrimary)
        nameLabel.numberOfLines = 1
        let idLabel = label(entry.userId, size: 12, color: tokens.textColorSecondary)
        idLabel.numberOfLines = 1
        idLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [avatar, nameLabel, idLabel])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        let row = UIButton(type: .custom)
        row.layer.cornerRadius = 10
        row.accessibilityLabel = "\(name) \(entry.userId)"
        row.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -12)
        ])
        row.addAction(UIAction { [weak row] _ in row?.backgroundColor = tokens.bgColorFunction }, for: .touchDown)
        row.addAction(UIAction { [weak row] _ in row?.backgroundColor = .clear }, for: [.touchUpOutside, .touchCancel])
        row.addAction(UIAction { [weak self] _ in
            guard let self, !self.loginInProgress else { return }
            self.closePresetMenu()
            self.selectedPreset = entry
            self.userField.text = entry.userId
            self.refreshPresetChip()
            self.applyButtonState()
        }, for: .touchUpInside)
        return row
    }

    /// Design L2: the focused field gets a brand-violet 1.5pt outline.
    private func styleInput(focused: Bool) {
        let tokens = Host.tokens
        inputFrame.layer.borderWidth = focused ? 1.5 : 1
        inputFrame.layer.borderColor = (focused ? tokens.buttonColorPrimaryDefault : tokens.strokeColorPrimary).cgColor
    }

    func textFieldDidBeginEditing(_ textField: UITextField) { styleInput(focused: true) }

    func textFieldDidEndEditing(_ textField: UITextField) { styleInput(focused: false) }

    private var typedUserID: String {
        userField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func applyButtonState() {
        loginButton.isEnabled = !typedUserID.isEmpty && !loginInProgress
        loginGradient.isHidden = !loginButton.isEnabled
        loginButton.backgroundColor = loginButton.isEnabled ? .clear : Host.tokens.buttonColorPrimaryDisabled
    }

    @objc private func inputChanged() { applyButtonState() }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    @objc private func loginTapped() {
        performLogin(userID: typedUserID)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if loginButton.isEnabled { loginTapped() }
        return true
    }

    /// Lifts the whole hero + card just enough for the card to clear the keyboard.
    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardTop = view.convert(frame, from: nil).minY
        let hidden = keyboardTop >= view.bounds.maxY - 1
        view.layoutIfNeeded()
        let cardBottom = card.convert(card.bounds, to: view).maxY - (contentTop?.constant ?? 0) + Self.contentTopInset
        let shift = hidden ? 0 : max(0, cardBottom + 16 - keyboardTop)
        contentTop?.constant = Self.contentTopInset - shift
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    func autoLoginIfSaved() {
        guard GenerateTestUserSig.isConfigured, !loggedIn, !loginInProgress, let saved = DemoLoginStore.load() else { return }
        guard saved.sdkAppID == GenerateTestUserSig.SDKAPPID else {
            DemoLoginStore.clear()
            return
        }
        selectedPreset = nil
        userField.text = saved.userID
        refreshPresetChip()
        applyButtonState()
        if resuming {
            resumeToken += 1
            let token = resumeToken
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.silentLoginTimeout) { [weak self] in
                guard let self, self.resuming, token == self.resumeToken, !self.loggedIn else { return }
                HostDiagnostics.record("login.silent", message: "timed out")
                self.hideSplashOverlay()
                self.showError(DemoText.get("demo_login_timed_out"))
            }
        }
        performLogin(userID: saved.userID)
    }

    private static let silentLoginTimeout: TimeInterval = 10

    func performLogin(userID input: String) {
        guard GenerateTestUserSig.isConfigured, !loggedIn, !loginInProgress else { return }
        let ticket: LoginTicket
        do {
            ticket = try GenerateTestUserSig.genTicket(userID: input)
        } catch {
            hideSplashOverlay()
            showError(strings.signFailed)
            return
        }
        let silent = resuming
        loginInProgress = true
        loginButton.setTitle(strings.loggingIn, for: .normal)
        applyButtonState()
        LoginStore.shared.login(sdkAppID: ticket.sdkAppID, userID: ticket.userID, userSig: ticket.userSig) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loginInProgress = false
                switch result {
                case .success:
                    self.loggedIn = true
                    DemoLoginStore.save(sdkAppID: ticket.sdkAppID, userID: ticket.userID)
                    self.initializeCall(sdk: ticket.sdkAppID, user: ticket.userID, sig: ticket.userSig)
                    self.navigationController?.setViewControllers([MainViewController(accountId: ticket.userID)], animated: !silent)
                case .failure(let error):
                    HostDiagnostics.record("login.silent", code: Int(error.code), message: error.message)
                    self.hideSplashOverlay()
                    self.loginButton.setTitle(self.strings.login, for: .normal)
                    self.applyButtonState()
                    self.showError(self.strings.loginFailed(Int32(error.code)))
                }
            }
        }
    }

    private func initializeCall(sdk: Int32, user: String, sig: String) {
        TUICallEngine.createInstance().`init`(sdk, userId: user, userSig: sig) {
            // CallKit already created its singleton when LoginStore reported `.logined` (CallKitLoginBridge),
            // so incoming calls are observed before the engine is ready; this call is only an idempotent
            // fallback. The incoming banner stays off, so an incoming call opens the full-screen call page
            // directly (same as Android).
            DispatchQueue.main.async { _ = TUICallKit.createInstance() }
            TUICallEngine.createInstance().enableMultiDeviceAbility(enable: true) {
                HostDiagnostics.record("call.multiDevice", message: "enabled")
            } fail: { code, message in
                HostDiagnostics.record("call.multiDevice", code: Int(code), message: message ?? "")
            }
        } fail: { code, _ in
            DispatchQueue.main.async { NSLog("Call init failed: %d", code) }
        }
    }

    private func showError(_ text: String) {
        SocialToast.show(text, kind: .error, duration: .long)
    }
}
