import UIKit
import AtomicXCore
import AtomicX
import TUIChatKit
import TUIHostBase

/// Login page copy. The text itself lives in `Resources/Localization/*.lproj` (same keys as Android `res/values*`);
/// this struct only names the entries the login screens use.
struct LoginStrings {
    var slogan: String { DemoText.get("demo_1v1_social_chat_meet_the_one") }
    var presetAccounts: String { DemoText.get("demo_preset_accounts") }
    var userIdTitle: String { DemoText.get("demo_user_id") }
    var hint: String { DemoText.get("demo_enter_your_user_id_to_get_started") }
    var placeholder: String { DemoText.get("demo_enter_user_id") }
    var login: String { DemoText.get("demo_log_in") }
    var loggingIn: String { DemoText.get("demo_logging_in") }
    var devConfigMissing: String { DemoText.get("demo_fill_sdkappid_and_secretkey_in_generatetestusersig") }
    var signFailed: String { DemoText.get("demo_local_signing_is_not_configured_check_the") }
    func loginFailed(_ code: Int32) -> String { DemoText.get("demo_im_login_failed_check_the_account_and", "\(code)") }
    var callTimeout: String { DemoText.get("demo_call_component_timed_out_calls_are_unavailable") }
    var gotIt: String { DemoText.get("demo_ok") }
    var languageTitle: String { DemoText.get("demo_choose_language") }
    var followSystem: String { DemoText.get("demo_follow_system") }
    var languageLabel: String { DemoText.get("demo_language") }
    var appearanceTitle: String { DemoText.get("demo_appearance") }
    var modeTitle: String { DemoText.get("demo_mode") }
    var light: String { DemoText.get("demo_light") }
    var dark: String { DemoText.get("demo_dark") }
    var paletteTitle: String { DemoText.get("demo_theme_color") }
    var appName: String { DemoText.get("app_name") }
}

/// Bottom sheet shell shared by the language and appearance sheets: dimmed backdrop, 24-radius top corners,
/// grabber. Subclasses fill `content` in `buildContent()`; the sheet rebuilds itself on every theme change.
class LoginSheetController: UIViewController {
    let panel = UIView()
    let content = UIStackView()
    var strings: LoginStrings { LoginStrings() }
    /// Called after a choice was applied so the login page behind can rebuild with the new locale / palette.
    var onApplied: (() -> Void)?

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    func buildContent() {}

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        let backdropTap = UITapGestureRecognizer(target: self, action: #selector(close))
        backdropTap.delegate = self
        view.addGestureRecognizer(backdropTap)
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.layer.cornerRadius = 24
        panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.layer.borderWidth = 1
        content.axis = .vertical
        content.spacing = 4
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(content)
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
        reload()
        NotificationCenter.default.addObserver(forName: DemoThemeCoordinator.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    @objc func close() { dismiss(animated: true) }

    func reload() {
        let tokens = Host.tokens
        panel.backgroundColor = tokens.bgColorDialog
        panel.layer.borderColor = (Host.isDark ? UIColor.white.withAlphaComponent(0.08) : .clear).cgColor
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let grabber = UIView()
        grabber.backgroundColor = tokens.textColorTertiary.withAlphaComponent(0.6)
        grabber.layer.cornerRadius = 2
        grabber.translatesAutoresizingMaskIntoConstraints = false
        let grabberRow = UIView()
        grabberRow.addSubview(grabber)
        NSLayoutConstraint.activate([
            grabber.widthAnchor.constraint(equalToConstant: 36), grabber.heightAnchor.constraint(equalToConstant: 4),
            grabber.centerXAnchor.constraint(equalTo: grabberRow.centerXAnchor),
            grabber.topAnchor.constraint(equalTo: grabberRow.topAnchor),
            grabber.bottomAnchor.constraint(equalTo: grabberRow.bottomAnchor)
        ])
        content.addArrangedSubview(grabberRow)
        buildContent()
    }

    func titleLabel(_ text: String) -> UILabel {
        let label = padded(text, size: 17, weight: .bold, color: Host.tokens.textColorPrimary)
        label.layoutMargins = .zero
        return label
    }

    func sectionLabel(_ text: String) -> UILabel {
        padded(text, size: 12, weight: .regular, color: Host.tokens.textColorSecondary)
    }

    private func padded(_ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) -> UILabel {
        let label = InsetLabel()
        label.text = text
        label.font = .adaptiveSystemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }
}

extension LoginSheetController: UIGestureRecognizerDelegate {
    /// Only taps on the dimmed backdrop close the sheet; taps inside the panel go to its controls.
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view === view
    }
}

/// Label with the 8pt start inset and vertical breathing room of the sheet headings.
final class InsetLabel: UILabel {
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: UIEdgeInsets(top: 10, left: 8, bottom: 6, right: 0)))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 8, height: size.height + 16)
    }
}

final class LoginLanguageSheet: LoginSheetController {
    override func buildContent() {
        let tokens = Host.tokens
        let text = strings
        content.addArrangedSubview(titleLabel(text.languageTitle))
        let options: [(String, String)] = [
            (DemoLanguage.system, text.followSystem), (DemoLanguage.zhCN, DemoText.get("demo_language_zh_hans")),
            (DemoLanguage.zhTW, DemoText.get("demo_language_zh_hant")), (DemoLanguage.en, DemoText.get("demo_language_english"))
        ]
        for (key, name) in options {
            let active = key == DemoLanguage.choice
            let row = UIControl()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 48).isActive = true
            row.layer.cornerRadius = 14
            row.backgroundColor = active ? tokens.buttonColorPrimaryDefault.withAlphaComponent(0.22) : .clear
            row.isAccessibilityElement = true
            row.accessibilityTraits = active ? [.button, .selected] : .button
            row.accessibilityLabel = name
            let label = UILabel()
            label.text = name
            label.font = .adaptiveSystemFont(ofSize: 15, weight: active ? .bold : .regular)
            label.textColor = tokens.textColorPrimary
            label.isUserInteractionEnabled = false
            label.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
                label.centerYAnchor.constraint(equalTo: row.centerYAnchor)
            ])
            if active {
                let check = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)))
                check.tintColor = tokens.buttonColorPrimaryDefault
                check.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(check)
                NSLayoutConstraint.activate([
                    check.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
                    check.centerYAnchor.constraint(equalTo: row.centerYAnchor)
                ])
            }
            row.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                if !active { DemoLanguage.choice = key }
                self.dismiss(animated: true) { if !active { self.onApplied?() } }
            }, for: .touchUpInside)
            content.addArrangedSubview(row)
        }
    }
}

/// Gradient swatch that keeps its gradient layer in sync with its bounds.
private final class PaletteSwatch: UIView {
    private let gradient = CAGradientLayer()

    init(colors: [UIColor]) {
        super.init(frame: .zero)
        gradient.colors = colors.map { $0.cgColor }
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradient)
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        layer.cornerRadius = bounds.height / 2
    }
}

/// Mode (follow system / light / dark) and the 8 palettes. Choices apply at once; the sheet stays open so
/// several palettes can be compared, and the login page behind it is rebuilt through `onApplied`.
final class LoginAppearanceSheet: LoginSheetController {
    override func buildContent() {
        let text = strings
        content.addArrangedSubview(titleLabel(text.appearanceTitle))
        content.addArrangedSubview(sectionLabel(text.modeTitle))
        content.addArrangedSubview(modeRow())
        content.addArrangedSubview(sectionLabel(text.paletteTitle))
        let infos = SocialPalettes.all
        let selected = DemoThemeCoordinator.palette
        for start in stride(from: 0, to: infos.count, by: 4) {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            for info in infos[start..<min(start + 4, infos.count)] {
                row.addArrangedSubview(paletteCell(info, active: info.key == selected))
            }
            content.addArrangedSubview(row)
        }
    }

    private func modeTitle(_ mode: DemoThemeCoordinator.Mode) -> String {
        switch mode {
        case .system: return strings.followSystem
        case .light: return strings.light
        case .dark: return strings.dark
        }
    }

    private func modeRow() -> UIView {
        let tokens = Host.tokens
        let container = UIStackView()
        container.axis = .horizontal
        container.distribution = .fillEqually
        container.spacing = 0
        container.isLayoutMarginsRelativeArrangement = true
        container.layoutMargins = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        container.backgroundColor = tokens.bgColorInput
        container.layer.cornerRadius = 14
        for mode in DemoThemeCoordinator.Mode.allCases {
            let active = mode == DemoThemeCoordinator.mode
            let button = UIButton(type: .custom)
            button.setTitle(modeTitle(mode), for: .normal)
            button.setTitleColor(active ? tokens.textColorButton : tokens.textColorPrimary, for: .normal)
            button.titleLabel?.font = .adaptiveSystemFont(ofSize: 14, weight: active ? .bold : .regular)
            button.layer.cornerRadius = 11
            button.clipsToBounds = true
            button.backgroundColor = active ? tokens.buttonColorPrimaryDefault : .clear
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            button.addAction(UIAction { [weak self] _ in
                guard !active else { return }
                DemoThemeCoordinator.setMode(mode)
                self?.onApplied?()
            }, for: .touchUpInside)
            container.addArrangedSubview(button)
        }
        return container
    }

    private func paletteCell(_ info: SocialPaletteInfo, active: Bool) -> UIView {
        let tokens = Host.tokens
        let cell = UIControl()
        cell.isAccessibilityElement = true
        cell.accessibilityTraits = active ? [.button, .selected] : .button
        cell.accessibilityLabel = DemoText.get("demo_palette_\(info.key)")
        let swatch = PaletteSwatch(colors: [Host.isDark ? info.gradStart : info.swatchLight, info.gradEnd])
        swatch.isUserInteractionEnabled = false
        swatch.layer.borderWidth = active ? 2 : 0
        swatch.layer.borderColor = tokens.textColorPrimary.cgColor
        let name = UILabel()
        name.text = DemoText.get("demo_palette_\(info.key)")
        name.font = .adaptiveSystemFont(ofSize: 11, weight: active ? .bold : .regular)
        name.textColor = active ? tokens.textColorPrimary : tokens.textColorSecondary
        name.textAlignment = .center
        name.isUserInteractionEnabled = false
        for item in [swatch, name] {
            item.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(item)
        }
        NSLayoutConstraint.activate([
            swatch.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6),
            swatch.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            swatch.widthAnchor.constraint(equalToConstant: 44),
            swatch.heightAnchor.constraint(equalToConstant: 44),
            name.topAnchor.constraint(equalTo: swatch.bottomAnchor, constant: 6),
            name.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            name.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            name.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -6)
        ])
        cell.addAction(UIAction { [weak self] _ in
            guard !active else { return }
            DemoThemeCoordinator.setPalette(info.key)
            self?.onApplied?()
        }, for: .touchUpInside)
        return cell
    }
}

/// 「我的 → 加好友」: who may add me (`allowType` of the IM profile). The choice is written to
/// `LoginStore.setSelfInfo` and the Mine row refreshes through `onApplied`.
final class FriendAddRuleSheet: LoginSheetController {
    override func buildContent() {
        let tokens = Host.tokens
        content.addArrangedSubview(titleLabel(DemoText.get("demo_friend_add_rule")))
        let current = LoginStore.shared.state.value.loginUserInfo?.allowType ?? .needConfirm
        let options: [(AllowType, String)] = [
            (.allowAny, DemoText.get("demo_allow_any")),
            (.needConfirm, DemoText.get("demo_need_confirm")),
            (.denyAny, DemoText.get("demo_deny_any"))
        ]
        for (type, name) in options {
            let active = type == current
            let row = UIControl()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 48).isActive = true
            row.layer.cornerRadius = 14
            row.backgroundColor = active ? tokens.buttonColorPrimaryDefault.withAlphaComponent(0.22) : .clear
            row.isAccessibilityElement = true
            row.accessibilityTraits = active ? [.button, .selected] : .button
            row.accessibilityLabel = name
            let label = UILabel()
            label.text = name
            label.font = .adaptiveSystemFont(ofSize: 15, weight: active ? .bold : .regular)
            label.textColor = tokens.textColorPrimary
            label.isUserInteractionEnabled = false
            label.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
                label.centerYAnchor.constraint(equalTo: row.centerYAnchor)
            ])
            if active {
                let check = UIImageView(image: UIImage(systemName: "checkmark",
                                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)))
                check.tintColor = tokens.buttonColorPrimaryDefault
                check.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(check)
                NSLayoutConstraint.activate([
                    check.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
                    check.centerYAnchor.constraint(equalTo: row.centerYAnchor)
                ])
            }
            row.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.dismiss(animated: true) {
                    guard !active else { return }
                    self.save(type)
                }
            }, for: .touchUpInside)
            content.addArrangedSubview(row)
        }
    }

    private func save(_ type: AllowType) {
        guard var info = LoginStore.shared.state.value.loginUserInfo else {
            SocialToast.show(DemoText.get("demo_setting_update_failed"), kind: .error)
            return
        }
        info.allowType = type
        LoginStore.shared.setSelfInfo(userProfile: info) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.onApplied?()
                case .failure(let error):
                    HostDiagnostics.record("mine.friendRule", code: error.code, message: error.message)
                    SocialToast.show(DemoText.get("demo_setting_update_failed"), kind: .error)
                }
            }
        }
    }
}
