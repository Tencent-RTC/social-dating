import UIKit

final class SelectionCheckBox: UIView {
    private static let iconRadiusRatio: CGFloat = 0.375

    private static let checkmarkHorizontalRatio: CGFloat = 0.5

    private static let checkmarkJointXRatio: CGFloat = 0.1

    private static let checkmarkVerticalRatio: CGFloat = 0.35

    private static let strokeLineWidth: CGFloat = 1.5

    private static let crossRadiusRatio: CGFloat = 0.4

    var isChecked: Bool = false {
        didSet { setNeedsDisplay() }
    }

    var isLocked: Bool = false {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        let colors = TUIChatKitTheme.colors
        let centerX = bounds.width / 2
        let centerY = bounds.height / 2
        let radius = bounds.width / 2
        let iconRadius = bounds.width * Self.iconRadiusRatio

        if isChecked {
            (isLocked ? colors.textColorLinkDisabled : colors.textColorLink).setFill()
            UIBezierPath(ovalIn: bounds).fill()

            let checkPath = UIBezierPath()
            checkPath.move(to: CGPoint(x: centerX - iconRadius * Self.checkmarkHorizontalRatio, y: centerY))
            checkPath.addLine(to: CGPoint(x: centerX - iconRadius * Self.checkmarkJointXRatio, y: centerY + iconRadius * Self.checkmarkVerticalRatio))
            checkPath.addLine(to: CGPoint(x: centerX + iconRadius * Self.checkmarkHorizontalRatio, y: centerY - iconRadius * Self.checkmarkVerticalRatio))
            checkPath.lineWidth = Self.strokeLineWidth
            checkPath.lineCapStyle = .round
            checkPath.lineJoinStyle = .round
            (isLocked ? colors.textColorButtonDisabled : colors.textColorButton).setStroke()
            checkPath.stroke()
        } else {
            let strokeWidth: CGFloat = 1
            let ringRect = bounds.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
            let ringPath = UIBezierPath(ovalIn: ringRect)
            ringPath.lineWidth = strokeWidth
            colors.scrollbarColorDefault.setStroke()
            ringPath.stroke()

            if isLocked {
                let crossRadius = iconRadius * Self.crossRadiusRatio
                let crossPath = UIBezierPath()
                crossPath.move(to: CGPoint(x: centerX - crossRadius, y: centerY - crossRadius))
                crossPath.addLine(to: CGPoint(x: centerX + crossRadius, y: centerY + crossRadius))
                crossPath.move(to: CGPoint(x: centerX + crossRadius, y: centerY - crossRadius))
                crossPath.addLine(to: CGPoint(x: centerX - crossRadius, y: centerY + crossRadius))
                crossPath.lineWidth = Self.strokeLineWidth
                crossPath.lineCapStyle = .round
                colors.textColorButtonDisabled.setStroke()
                crossPath.stroke()
            }
        }
    }
}

final class MessageSendingSpinnerView: UIView {
    static let size: CGFloat = 12

    private static let innerRadiusRatio: CGFloat = 3.2

    private static let thicknessRatio: CGFloat = 10

    private static let rotationKey = "messageSendingSpin"

    private static let rotationDuration: CFTimeInterval = 0.8

    private static let ringRGB: CGFloat = 0x88 / 255

    private static let gradientAlphas: [CGFloat] = [0x1F / 255, 0x66 / 255, 1]

    private let ringGradient = CAGradientLayer()

    private let ringMask = CAShapeLayer()

    private(set) var isAnimating = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        isUserInteractionEnabled = false
        ringGradient.type = .conic
        ringGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        ringGradient.endPoint = CGPoint(x: 1, y: 0.5)
        ringGradient.locations = [0, 0.5, 1]
        ringGradient.colors = Self.gradientAlphas.map {
            UIColor(white: Self.ringRGB, alpha: $0).cgColor
        }
        ringMask.fillColor = UIColor.clear.cgColor
        ringMask.strokeColor = UIColor.black.cgColor
        ringGradient.mask = ringMask
        layer.addSublayer(ringGradient)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resumeAnimationIfNeeded),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.size, height: Self.size)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ringGradient.frame = bounds
        ringMask.frame = bounds
        let side = min(bounds.width, bounds.height)
        let thickness = side / Self.thicknessRatio
        let middleRadius = side / Self.innerRadiusRatio + thickness / 2
        ringMask.lineWidth = thickness
        ringMask.path = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: middleRadius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        ).cgPath
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resumeAnimationIfNeeded()
    }

    func startAnimating() {
        isAnimating = true
        isHidden = false
        resumeAnimationIfNeeded()
    }

    func stopAnimating() {
        isAnimating = false
        isHidden = true
        layer.removeAnimation(forKey: Self.rotationKey)
    }

    @objc private func resumeAnimationIfNeeded() {
        guard isAnimating, window != nil else { return }
        guard layer.animation(forKey: Self.rotationKey) == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = CGFloat.pi * 2
        spin.duration = Self.rotationDuration
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        spin.isRemovedOnCompletion = false
        layer.add(spin, forKey: Self.rotationKey)
    }
}

final class MessageSendFailBadgeView: UIView {
    static let size: CGFloat = 14

    private static let glyphFontSize: CGFloat = 10

    private let glyphLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        glyphLabel.text = "!"
        glyphLabel.font = .adaptiveSystemFont(ofSize: Self.glyphFontSize, weight: .bold)
        glyphLabel.textAlignment = .center
        addSubview(glyphLabel)
        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.size, height: Self.size)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        glyphLabel.frame = bounds
    }

    func applyTheme() {
        let colors = TUIChatKitTheme.colors
        backgroundColor = colors.textColorError
        glyphLabel.textColor = colors.textColorButton
    }
}
