import UIKit

public enum Motion {
    public static let fast: TimeInterval = 0.14
    public static let base: TimeInterval = 0.22
    public static let slow: TimeInterval = 0.36
    public static let theme: TimeInterval = 0.42

    public static let easeOut = CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1)
    public static let easeInOut = CAMediaTimingFunction(controlPoints: 0.45, 0.05, 0.55, 0.95)
    public static let spring = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)

    public static var enabled: Bool { !UIAccessibility.isReduceMotionEnabled }

    public static func gridDelay(_ index: Int) -> TimeInterval { min(0.06 + Double(index) * 0.045, 0.52) }

    public static func rowDelay(_ index: Int) -> TimeInterval { min(Double(index) * 0.026, 0.43) }

    public static func cubicParameters(_ function: CAMediaTimingFunction) -> UICubicTimingParameters {
        var first: [Float] = [0, 0]
        var second: [Float] = [0, 0]
        function.getControlPoint(at: 1, values: &first)
        function.getControlPoint(at: 2, values: &second)
        return UICubicTimingParameters(controlPoint1: CGPoint(x: CGFloat(first[0]), y: CGFloat(first[1])),
                                       controlPoint2: CGPoint(x: CGFloat(second[0]), y: CGFloat(second[1])))
    }

    /// Eased value of a timing function at linear time `t` (0...1), for animations driven frame by frame.
    public static func ease(_ function: CAMediaTimingFunction, _ t: CGFloat) -> CGFloat {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        var p1: [Float] = [0, 0]
        var p2: [Float] = [0, 0]
        function.getControlPoint(at: 1, values: &p1)
        function.getControlPoint(at: 2, values: &p2)
        let x1 = CGFloat(p1[0]), y1 = CGFloat(p1[1]), x2 = CGFloat(p2[0]), y2 = CGFloat(p2[1])
        func bezier(_ a: CGFloat, _ b: CGFloat, _ s: CGFloat) -> CGFloat {
            let u = 1 - s
            return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
        }
        // Solve x(s) = t by bisection (x is monotonic for the control points used here), then read y(s).
        var low: CGFloat = 0
        var high: CGFloat = 1
        var s = t
        for _ in 0..<24 {
            s = (low + high) / 2
            if bezier(x1, x2, s) < t { low = s } else { high = s }
        }
        return bezier(y1, y2, s)
    }

    public static func animate(_ duration: TimeInterval, _ function: CAMediaTimingFunction = easeOut,
                               animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: cubicParameters(function))
        animator.addAnimations(animations)
        if let completion { animator.addCompletion { completion($0 == .end) } }
        animator.startAnimation()
    }

    public static func fadeUp(_ view: UIView) {
        guard enabled else { return }
        view.layer.removeAnimation(forKey: "motion.enter")
        let group = CAAnimationGroup()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let rise = CABasicAnimation(keyPath: "transform")
        rise.fromValue = CATransform3DScale(CATransform3DMakeTranslation(0, 10, 0), 0.99, 0.99, 1)
        rise.toValue = CATransform3DIdentity
        group.animations = [fade, rise]
        group.duration = base
        group.timingFunction = easeOut
        group.fillMode = .backwards
        view.layer.add(group, forKey: "motion.enter")
    }

    public static func rowIn(_ view: UIView, delay: TimeInterval, duration: TimeInterval = base) {
        guard enabled else { return }
        view.layer.removeAnimation(forKey: "motion.enter")
        let group = CAAnimationGroup()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = 8
        rise.toValue = 0
        group.animations = [fade, rise]
        group.duration = duration
        group.beginTime = CACurrentMediaTime() + delay
        group.timingFunction = easeOut
        group.fillMode = .backwards
        view.layer.add(group, forKey: "motion.enter")
    }

    public static func stagger(_ views: [UIView], grid: Bool) {
        for (index, view) in views.enumerated() {
            if grid {
                rowIn(view, delay: gridDelay(index), duration: slow)
            } else {
                rowIn(view, delay: rowDelay(index))
            }
        }
    }

    public static func cardLeave(_ view: UIView) {
        guard enabled else { return }
        animate(0.2, easeOut) {
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: 6).scaledBy(x: 0.94, y: 0.94)
        }
    }

    public static func bump(_ view: UIView) {
        guard enabled else { return }
        view.layer.removeAnimation(forKey: "motion.bump")
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1, 1.45, 1]
        animation.keyTimes = [0, 0.4, 1]
        animation.timingFunctions = [spring, spring]
        animation.duration = slow
        view.layer.add(animation, forKey: "motion.bump")
    }

    public static func bubblePop(_ view: UIView, fromTrailing: Bool) {
        guard enabled else { return }
        view.layoutIfNeeded()
        view.layer.removeAnimation(forKey: "motion.pop")
        view.layer.removeAnimation(forKey: "motion.popFade")
        let scale: CGFloat = 0.72
        let dx = (fromTrailing ? 1 : -1) * view.bounds.width / 2
        let dy = view.bounds.height / 2
        var start = CATransform3DMakeTranslation((1 - scale) * dx, (1 - scale) * dy + 10, 0)
        start = CATransform3DScale(start, scale, scale, 1)
        let pop = CABasicAnimation(keyPath: "transform")
        pop.fromValue = start
        pop.toValue = CATransform3DIdentity
        pop.duration = slow
        pop.timingFunction = spring
        view.layer.add(pop, forKey: "motion.pop")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = slow * 0.6
        fade.timingFunction = easeOut
        view.layer.add(fade, forKey: "motion.popFade")
    }

    public static func kenBurns(_ view: UIView) {
        guard enabled else { return }
        view.layer.removeAnimation(forKey: "motion.kenBurns")
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 1
        animation.toValue = 1.06
        animation.duration = 6
        animation.timingFunction = easeOut
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        view.layer.add(animation, forKey: "motion.kenBurns")
    }
}
