//
//  CallEffectsPanel.swift
//  Sound-effect / beauty sheet of the call page (same behaviour as Android `CallEffectsPanel`).
//
//  The choices go straight to TRTC (voice changer, reverb, basic beauty), so the peer hears / sees the result.
//  Every change is written to UserDefaults, so the next call opens with the same voice and picture.
//

import UIKit
import RTCRoomEngine
import AtomicX

#if canImport(TXLiteAVSDK_TRTC)
import TXLiteAVSDK_TRTC
#elseif canImport(TXLiteAVSDK_Professional)
import TXLiteAVSDK_Professional
#endif

enum CallEffectsState {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let voice = "callEffects.voice"
        static let reverb = "callEffects.reverb"
        static let beauty = "callEffects.beauty"
        static let whiteness = "callEffects.whiteness"
        static let ruddy = "callEffects.ruddy"
    }

    static var voice = defaults.integer(forKey: Key.voice) { didSet { defaults.set(voice, forKey: Key.voice) } }
    static var reverb = defaults.integer(forKey: Key.reverb) { didSet { defaults.set(reverb, forKey: Key.reverb) } }
    static var beauty = defaults.integer(forKey: Key.beauty) { didSet { defaults.set(beauty, forKey: Key.beauty) } }
    static var whiteness = defaults.integer(forKey: Key.whiteness) { didSet { defaults.set(whiteness, forKey: Key.whiteness) } }
    static var ruddy = defaults.integer(forKey: Key.ruddy) { didSet { defaults.set(ruddy, forKey: Key.ruddy) } }

    /// Pushes the saved levels to the live stream when the call page opens.
    static func apply(to engine: CallEffectsEngine) {
        engine.setVoiceChanger(voice)
        engine.setReverb(reverb)
        engine.setBeauty(beauty)
        engine.setWhiteness(whiteness)
        engine.setRuddy(ruddy)
    }
}

/// Engine calls behind the panel; the debug preview swaps in a no-op.
protocol CallEffectsEngine: AnyObject {
    func setVoiceChanger(_ index: Int)
    func setReverb(_ index: Int)
    func setBeauty(_ level: Int)
    func setWhiteness(_ level: Int)
    func setRuddy(_ level: Int)
}

final class TrtcCallEffectsEngine: CallEffectsEngine {
    private var trtc: TRTCCloud { TUICallEngine.createInstance().getTRTCCloudInstance() }

    func setVoiceChanger(_ index: Int) {
        guard let type = TXVoiceChangeType(rawValue: index) else { return }
        trtc.getAudioEffectManager().setVoiceChangerType(type)
    }

    func setReverb(_ index: Int) {
        guard let type = TXVoiceReverbType(rawValue: index) else { return }
        trtc.getAudioEffectManager().setVoiceReverbType(type)
    }

    func setBeauty(_ level: Int) {
        trtc.getBeautyManager().setBeautyStyle(.smooth)
        trtc.getBeautyManager().setBeautyLevel(Float(level))
    }

    func setWhiteness(_ level: Int) { trtc.getBeautyManager().setWhitenessLevel(Float(level)) }

    func setRuddy(_ level: Int) { trtc.getBeautyManager().setRuddyLevel(Float(level)) }
}

final class NoopCallEffectsEngine: CallEffectsEngine {
    func setVoiceChanger(_ index: Int) {}
    func setReverb(_ index: Int) {}
    func setBeauty(_ level: Int) {}
    func setWhiteness(_ level: Int) {}
    func setRuddy(_ level: Int) {}
}

/// One single-choice chip; the selected one carries the brand gradient.
private final class EffectChip: UIControl {
    private let gradient: CallSkinGradientView
    private let titleLabel: UILabel
    private let normalColor: UIColor
    private let selectedTextColor: UIColor
    private let plainTextColor: UIColor

    init(title: String, t: ColorTokens) {
        gradient = CallSkinGradientView(colors: [t.buttonColorPrimaryDefault, t.tagColorLevel4],
                                        start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 1, y: 0.5))
        titleLabel = CallSkin.label(title, size: 13, color: t.textColorPrimary)
        normalColor = UIColor(white: 1, alpha: 0.10)
        selectedTextColor = t.textColorButton
        plainTextColor = t.textColorPrimary
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 16
        clipsToBounds = true
        gradient.isUserInteractionEnabled = false
        titleLabel.layer.shadowOpacity = 0
        addSubview(gradient)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            gradient.leadingAnchor.constraint(equalTo: leadingAnchor),
            gradient.trailingAnchor.constraint(equalTo: trailingAnchor),
            gradient.topAnchor.constraint(equalTo: topAnchor),
            gradient.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setChosen(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setChosen(_ chosen: Bool) {
        gradient.isHidden = !chosen
        backgroundColor = chosen ? .clear : normalColor
        titleLabel.textColor = chosen ? selectedTextColor : plainTextColor
        accessibilityTraits = chosen ? [.button, .selected] : .button
        accessibilityLabel = titleLabel.text
        isAccessibilityElement = true
    }
}

/// Bottom sheet drawn in the call skin (dark tokens). `kind == .sound` = voice changer + reverb chips,
/// `.beauty` = three 0-9 sliders. It lives inside the call view, so it disappears with the call.
final class CallEffectsPanel: UIView {
    enum Kind { case sound, beauty }

    private let kind: Kind
    private let engine: CallEffectsEngine
    private let onClose: () -> Void
    private let t = CallSkin.tokens
    private let sheet = UIView()

    init(kind: Kind, engine: CallEffectsEngine, onClose: @escaping () -> Void) {
        self.kind = kind
        self.engine = engine
        self.onClose = onClose
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor(white: 0, alpha: 90.0 / 255.0)
        let dismiss = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        dismiss.delegate = self
        addGestureRecognizer(dismiss)
        buildSheet()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func closeTapped() { onClose() }

    private func buildSheet() {
        sheet.translatesAutoresizingMaskIntoConstraints = false
        sheet.backgroundColor = t.bgColorOperate.withAlphaComponent(0.96)
        sheet.layer.cornerRadius = 20
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(sheet)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(stack)
        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: leadingAnchor),
            sheet.trailingAnchor.constraint(equalTo: trailingAnchor),
            sheet.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: sheet.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])

        stack.addArrangedSubview(header())
        switch kind {
        case .sound:
            stack.addArrangedSubview(section("skin.voice_title"))
            stack.addArrangedSubview(chips(prefix: "voice", count: 8, selected: CallEffectsState.voice) { [weak self] index in
                CallEffectsState.voice = index
                self?.engine.setVoiceChanger(index)
            })
            stack.addArrangedSubview(section("skin.reverb_title"))
            stack.addArrangedSubview(chips(prefix: "reverb", count: 8, selected: CallEffectsState.reverb) { [weak self] index in
                CallEffectsState.reverb = index
                self?.engine.setReverb(index)
            })
        case .beauty:
            stack.addArrangedSubview(slider("skin.beauty_smooth", value: CallEffectsState.beauty) { [weak self] level in
                CallEffectsState.beauty = level
                self?.engine.setBeauty(level)
            })
            stack.addArrangedSubview(slider("skin.beauty_whiten", value: CallEffectsState.whiteness) { [weak self] level in
                CallEffectsState.whiteness = level
                self?.engine.setWhiteness(level)
            })
            stack.addArrangedSubview(slider("skin.beauty_ruddy", value: CallEffectsState.ruddy) { [weak self] level in
                CallEffectsState.ruddy = level
                self?.engine.setRuddy(level)
            })
        }
    }

    private func header() -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let title = CallSkin.label(CallSkin.loc(kind == .sound ? "skin.fun_sfx" : "skin.fun_beauty"), size: 16, color: t.textColorPrimary, bold: true)
        let done = UIButton(type: .system)
        done.translatesAutoresizingMaskIntoConstraints = false
        done.setTitle(CallSkin.loc("skin.panel_done"), for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 14)
        done.setTitleColor(t.textColorLink, for: .normal)
        done.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 0)
        done.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        row.addSubview(title)
        row.addSubview(done)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 32),
            title.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            title.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            done.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            done.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func section(_ key: String) -> UIView {
        let holder = UIView()
        let label = CallSkin.label(CallSkin.loc(key), size: 12, color: t.textColorSecondary)
        holder.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            label.topAnchor.constraint(equalTo: holder.topAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -8)
        ])
        return holder
    }

    /// One horizontally scrolling row of single-choice chips.
    private func chips(prefix: String, count: Int, selected: Int, onPick: @escaping (Int) -> Void) -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)
        var chips: [EffectChip] = []
        for index in 0..<count {
            let chip = EffectChip(title: CallSkin.loc("skin.\(prefix)_\(index)"), t: t)
            chip.setChosen(index == selected)
            chip.addAction(UIAction { _ in
                chips.enumerated().forEach { $0.element.setChosen($0.offset == index) }
                onPick(index)
            }, for: .touchUpInside)
            chips.append(chip)
            row.addArrangedSubview(chip)
        }
        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(equalToConstant: 32),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
        return scroll
    }

    /// 0-9 level slider with the current value on the right (TRTC takes 0-9).
    private func slider(_ key: String, value: Int, onChange: @escaping (Int) -> Void) -> UIView {
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        let name = CallSkin.label(CallSkin.loc(key), size: 14, color: t.textColorPrimary)
        let number = CallSkin.label("\(value)", size: 14, color: t.textColorSecondary)
        number.textAlignment = .right
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0
        slider.maximumValue = 9
        slider.value = Float(value)
        slider.minimumTrackTintColor = t.buttonColorPrimaryDefault
        slider.thumbTintColor = t.buttonColorPrimaryDefault
        slider.accessibilityLabel = CallSkin.loc(key)
        slider.addAction(UIAction { [weak slider, weak number] _ in
            guard let slider, let number else { return }
            let level = Int(slider.value.rounded())
            slider.value = Float(level)
            if number.text != "\(level)" {
                number.text = "\(level)"
                onChange(level)
            }
        }, for: .valueChanged)
        [name, slider, number].forEach(holder.addSubview)
        NSLayoutConstraint.activate([
            holder.heightAnchor.constraint(equalToConstant: 48),
            name.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            name.widthAnchor.constraint(equalToConstant: 56),
            name.centerYAnchor.constraint(equalTo: holder.centerYAnchor, constant: 7),
            slider.leadingAnchor.constraint(equalTo: name.trailingAnchor),
            slider.trailingAnchor.constraint(equalTo: number.leadingAnchor, constant: -8),
            slider.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            number.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            number.widthAnchor.constraint(equalToConstant: 28),
            number.centerYAnchor.constraint(equalTo: name.centerYAnchor)
        ])
        return holder
    }
}

extension CallEffectsPanel: UIGestureRecognizerDelegate {
    /// Only the dimmed area closes the panel; touches on the sheet go to its controls.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return true }
        return !view.isDescendant(of: sheet)
    }
}
