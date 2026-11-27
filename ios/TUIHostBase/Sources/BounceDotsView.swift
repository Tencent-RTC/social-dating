import UIKit

public final class BounceDotsView: UIView {
    public var dotColor: UIColor {
        didSet { dots.forEach { $0.backgroundColor = dotColor.cgColor } }
    }

    private let dotSize: CGFloat
    private let gap: CGFloat
    private let lift: CGFloat
    private let dots: [CALayer]

    private static let period: CFTimeInterval = 1.2
    private static let stagger: CFTimeInterval = 0.15
    private static let minAlpha: Float = 0.4
    private static let animationKey = "bounceDots"

    public init(dotSize: CGFloat = 4, gap: CGFloat = 3, lift: CGFloat = 4, color: UIColor = Host.tokens.textColorLink) {
        self.dotSize = dotSize
        self.gap = gap
        self.lift = lift
        self.dotColor = color
        self.dots = (0..<3).map { _ in
            let layer = CALayer()
            layer.cornerRadius = dotSize / 2
            layer.backgroundColor = color.cgColor
            layer.opacity = BounceDotsView.minAlpha
            return layer
        }
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        dots.forEach { layer.addSublayer($0) }
        NotificationCenter.default.addObserver(self, selector: #selector(motionPreferenceChanged),
                                               name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: dotSize * 3 + gap * 2, height: dotSize + lift)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        for (index, dot) in dots.enumerated() {
            dot.frame = CGRect(x: CGFloat(index) * (dotSize + gap), y: bounds.height - dotSize, width: dotSize, height: dotSize)
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    public override var isHidden: Bool {
        didSet { if isHidden { stop() } else if window != nil { start() } }
    }

    @objc private func motionPreferenceChanged() {
        stop()
        if window != nil && !isHidden { start() }
    }

    private func start() {
        guard dots.first?.animation(forKey: Self.animationKey) == nil else { return }
        guard !UIAccessibility.isReduceMotionEnabled else {
            dots.first?.opacity = 1
            return
        }
        let now = CACurrentMediaTime()
        for (index, dot) in dots.enumerated() {
            let move = CAKeyframeAnimation(keyPath: "transform.translation.y")
            move.values = [0, -lift, 0, 0]
            move.keyTimes = [0, 0.25, 0.5, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [Self.minAlpha, 1, Self.minAlpha, Self.minAlpha]
            fade.keyTimes = [0, 0.25, 0.5, 1]
            let group = CAAnimationGroup()
            group.animations = [move, fade]
            group.duration = Self.period
            group.repeatCount = .infinity
            group.beginTime = now + Self.stagger * Double(index)
            group.fillMode = .backwards
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.add(group, forKey: Self.animationKey)
        }
    }

    private func stop() {
        dots.forEach {
            $0.removeAnimation(forKey: Self.animationKey)
            $0.opacity = Self.minAlpha
        }
    }
}
