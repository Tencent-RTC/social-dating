import UIKit
import Combine
import AtomicXCore
import AtomicX
import TUIHostBase
import TUIChatKit

/// Edit profile sub page of 「我的」. Same data path as the Chat View Demo's settings page: every field is the
/// real IM profile, read from `LoginStore.state.loginUserInfo` and written back with `LoginStore.setSelfInfo`
/// (incremental: only the changed field is set on a fresh `UserProfile`). The look follows the 1v1 host: a centred
/// 88pt avatar and one list surface with 52pt rows under the host title bar.
public final class EditProfileViewController: DemoSubPageController {
    private let avatarBox = UIStackView()
    private let rows = UIStackView()
    private var cancellables = Set<AnyCancellable>()
    private var profile: UserProfile?

    private var tokens: ColorTokens { Host.tokens }

    public init() {
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    public required init?(coder: NSCoder) { fatalError() }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = tokens.bgColorTopBar
        let header = HostHeaderView(title: DemoText.get("demo_edit_profile"), left: backButton())
        avatarBox.axis = .vertical
        avatarBox.alignment = .center
        avatarBox.spacing = 8
        avatarBox.isLayoutMarginsRelativeArrangement = true
        avatarBox.layoutMargins = UIEdgeInsets(top: 20, left: 0, bottom: 20, right: 0)
        avatarBox.backgroundColor = tokens.bgColorTopBar
        rows.axis = .vertical
        rows.backgroundColor = tokens.bgColorTopBar
        let body = UIStackView(arrangedSubviews: [avatarBox, rows])
        body.axis = .vertical
        body.spacing = HostMetrics.meBlockGap
        let scroll = UIScrollView()
        scroll.backgroundColor = tokens.bgColorDefault
        scroll.showsVerticalScrollIndicator = false
        for item in [header, scroll, body] { item.translatesAutoresizingMaskIntoConstraints = false }
        scroll.addSubview(body)
        view.addSubview(scroll)
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor), header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            body.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            body.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor)
        ])
        LoginStore.shared.state.subscribe(StatePublisherSelector(keyPath: \.loginUserInfo))
            .receive(on: RunLoop.main)
            .sink { [weak self] info in
                self?.profile = info
                self?.render()
            }
            .store(in: &cancellables)
    }

    private func render() {
        guard let data = profile else { return }
        let name = (data.nickname?.isEmpty == false ? data.nickname : nil) ?? data.userID
        avatarBox.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let face = DemoRemoteAvatar(name: name, url: data.avatarURL, size: 88)
        face.isUserInteractionEnabled = true
        face.accessibilityLabel = DemoText.get("demo_change_avatar")
        face.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pickAvatar)))
        avatarBox.addArrangedSubview(face)
        avatarBox.addArrangedSubview(label(DemoText.get("demo_change_avatar"), 14, tokens.textColorLink))

        rows.addArrangedSubview(row(DemoText.get("demo_account_id"), data.userID, last: false, action: nil))
        rows.addArrangedSubview(row(DemoText.get("demo_nickname"), data.nickname ?? "", last: false) { [weak self] in self?.editNickname(data.nickname ?? "") })
        let sign = (data.selfSignature?.isEmpty == false ? data.selfSignature : nil) ?? DemoText.get("demo_signature_empty")
        rows.addArrangedSubview(row(DemoText.get("demo_signature"), sign, last: false) { [weak self] in self?.editSignature(data.selfSignature ?? "") })
        rows.addArrangedSubview(row(DemoText.get("demo_gender"), genderText(data.gender), last: false) { [weak self] in self?.pickGender() })
        rows.addArrangedSubview(row(DemoText.get("demo_birthday"), birthdayText(data.birthday), last: true) { [weak self] in self?.pickBirthday(data.birthday) })
    }

    private func row(_ title: String, _ value: String, last: Bool, action: (() -> Void)?) -> UIView {
        let pad = HostMetrics.screenPaddingH
        let name = label(title, 17, tokens.textColorPrimary)
        name.translatesAutoresizingMaskIntoConstraints = false
        name.widthAnchor.constraint(equalToConstant: 100).isActive = true
        let text = label(value, 15, tokens.textColorSecondary)
        text.numberOfLines = 1
        text.textAlignment = .right
        text.lineBreakMode = .byTruncatingTail
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        var items: [UIView] = [name, text]
        if action != nil {
            let chevron = Host.icon("demo_ic_chevron", size: 12, tint: tokens.textColorDisable)
            items.append(chevron)
        }
        let line = UIStackView(arrangedSubviews: items)
        line.axis = .horizontal
        line.alignment = .center
        line.spacing = 8
        line.isLayoutMarginsRelativeArrangement = true
        line.layoutMargins = UIEdgeInsets(top: 0, left: pad, bottom: 0, right: pad)
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let container = UIStackView(arrangedSubviews: [line])
        container.axis = .vertical
        if !last {
            let divider = UIView()
            divider.backgroundColor = tokens.strokeColorPrimary
            divider.translatesAutoresizingMaskIntoConstraints = false
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
            let wrap = UIView()
            wrap.addSubview(divider)
            NSLayoutConstraint.activate([
                divider.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: pad),
                divider.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
                divider.topAnchor.constraint(equalTo: wrap.topAnchor), divider.bottomAnchor.constraint(equalTo: wrap.bottomAnchor)
            ])
            container.addArrangedSubview(wrap)
        }
        if let action {
            let tap = ClosureTap(action)
            container.addGestureRecognizer(tap)
        }
        return container
    }

    private func genderText(_ gender: Gender?) -> String {
        switch gender {
        case .male: return DemoText.get("demo_gender_male")
        case .female: return DemoText.get("demo_gender_female")
        default: return DemoText.get("demo_gender_secret")
        }
    }

    private func birthdayText(_ birthday: UInt32?) -> String {
        guard let birthday, birthday > 0, String(birthday).count == 8 else { return DemoText.get("demo_signature_empty") }
        let raw = String(birthday)
        return "\(raw.prefix(4))-\(raw.dropFirst(4).prefix(2))-\(raw.dropFirst(6).prefix(2))"
    }

    // MARK: edits (all written to the real IM profile)

    @objc private func pickAvatar() {
        let urls = (1...26).map { "https://im.sdk.qcloud.com/download/tuikit-resource/avatar/avatar_\($0).png" }
        let picker = AvatarPickerSheetController(title: DemoText.get("demo_pick_avatar"), imageUrlList: urls) { [weak self] url in
            guard let self, let id = self.profile?.userID else { return }
            self.save(UserProfile(userID: id, nickname: nil, avatarURL: url))
        }
        present(picker, animated: false)
    }

    private func editNickname(_ current: String) {
        let dialog = TextInputDialogViewController(title: DemoText.get("demo_edit_nickname"), initialText: current, maxLength: 32) { [weak self] text in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard let self, !trimmed.isEmpty, let id = self.profile?.userID else { return }
            self.save(UserProfile(userID: id, nickname: trimmed))
        }
        present(dialog, animated: true)
    }

    private func editSignature(_ current: String) {
        let dialog = TextInputDialogViewController(title: DemoText.get("demo_edit_signature"), initialText: current, maxLength: 60, multiline: true) { [weak self] text in
            guard let self, let id = self.profile?.userID else { return }
            var change = UserProfile(userID: id)
            change.selfSignature = text.trimmingCharacters(in: .whitespaces)
            self.save(change)
        }
        present(dialog, animated: true)
    }

    private func pickGender() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for (key, gender) in [("demo_gender_male", Gender.male), ("demo_gender_female", Gender.female), ("demo_gender_secret", Gender.unknown)] {
            sheet.addAction(UIAlertAction(title: DemoText.get(key), style: .default) { [weak self] _ in
                guard let self, let id = self.profile?.userID else { return }
                var change = UserProfile(userID: id)
                change.gender = gender
                self.save(change)
            })
        }
        sheet.addAction(UIAlertAction(title: DemoText.get("demo_cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func pickBirthday(_ birthday: UInt32?) {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .wheels
        picker.maximumDate = Date()
        var components = DateComponents(year: 2000, month: 1, day: 1)
        if let birthday, birthday > 0, String(birthday).count == 8 {
            let raw = String(birthday)
            components = DateComponents(year: Int(raw.prefix(4)), month: Int(raw.dropFirst(4).prefix(2)), day: Int(raw.dropFirst(6).prefix(2)))
        }
        picker.date = Calendar.current.date(from: components) ?? Date()
        let alert = UIAlertController(title: DemoText.get("demo_birthday"), message: "\n\n\n\n\n\n\n\n\n", preferredStyle: .alert)
        picker.translatesAutoresizingMaskIntoConstraints = false
        alert.view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            picker.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 54),
            picker.widthAnchor.constraint(equalToConstant: 250), picker.heightAnchor.constraint(equalToConstant: 160)
        ])
        alert.addAction(UIAlertAction(title: DemoText.get("demo_cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: DemoText.get("demo_confirm"), style: .default) { [weak self] _ in
            guard let self, let id = self.profile?.userID else { return }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            var change = UserProfile(userID: id)
            change.birthday = UInt32(formatter.string(from: picker.date))
            self.save(change)
        })
        present(alert, animated: true)
    }

    /// Incremental update: the fresh `UserProfile` only carries the field that changed (same as Chat View Demo).
    private func save(_ change: UserProfile) {
        LoginStore.shared.setSelfInfo(userProfile: change) { [weak self] result in
            guard case .failure = result else { return }
            DispatchQueue.main.async {
                SocialToast.show(DemoText.get("demo_profile_save_failed"), kind: .error)
            }
        }
    }
}

/// UITapGestureRecognizer that calls a closure.
private final class ClosureTap: UITapGestureRecognizer {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(fire))
    }

    @objc private func fire() { action() }
}
