import UIKit

/// Page container for second-level tabs (推荐 / 附近 / 新人, 消息 / 好友 / 通话). Behaves like the Android `HostSwipePager`.
///
/// - Every page is built the first time it is shown (`provider`) and kept afterwards: switching only hides / shows it,
///   so nothing is rebuilt or refetched and each page keeps its scroll position.
/// - A tab tap (`show(_:animate:)`) slides the old page out and the new one in from the side the tab lies on.
/// - A horizontal drag follows the finger; on release it commits to the neighbour page (travelled more than 35% or a
///   fast fling forward) or springs back, both with the same ease-out curve as a tap slide.
/// - `onProgress` reports the continuous position (1.5 = half way from page 1 to page 2) on every frame of a slide, a
///   drag and the settle after release, so the tab bar above can travel with the pages.
public final class HostSwipePager: UIView, UIGestureRecognizerDelegate {
    /// Builds the page of an index; called at most once per index until `invalidate` / `reset`.
    public var provider: (Int) -> UIView = { _ in UIView() }
    /// Called once a page has been added to the pager (it already has its frame), before it is first shown.
    public var didAddPage: (Int, UIView) -> Void = { _, _ in }
    /// Fired when a drag decides to move to another page (the tab bar follows right away).
    public var onSwiped: (Int) -> Void = { _ in }
    /// Continuous page position; called every frame while the pages move and once for a plain jump.
    public var onProgress: (CGFloat) -> Void = { _ in }
    public var swipeEnabled = true { didSet { updatePan() } }
    /// Lets a child keep its own horizontal gesture: the touch point (pager coordinates) and the drag direction
    /// (-1 = towards the next page). Return true to leave the drag to the child.
    public var yieldDrag: (CGPoint, Int) -> Bool = { _, _ in false }
    public var pageCount = 0 {
        didSet {
            updatePan()
            setNeedsLayout()
        }
    }
    public private(set) var index = -1

    private let pan = UIPanGestureRecognizer()
    private var pages: [Int: UIView] = [:]

    private var dragging = false
    private var absorbing = false
    private var dragFrom = 0
    private var dragTarget = -1
    private var dragOffset: CGFloat = 0

    private var link: CADisplayLink?
    private var animStart: CFTimeInterval = 0
    private var animDuration: CFTimeInterval = 0
    private var animStep: ((CGFloat) -> Void)?
    private var animDone: (() -> Void)?

    /// A tap slides a little longer than the generic base motion: the tab bar travels the same distance.
    private static let slideDuration: CFTimeInterval = 0.32
    private static let minFling: CGFloat = 400
    private static let commitRatio: CGFloat = 0.35

    public override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        pan.addTarget(self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        updatePan()
    }

    public required init?(coder: NSCoder) { fatalError() }

    deinit { link?.invalidate() }

    private func updatePan() { pan.isEnabled = swipeEnabled && pageCount > 1 }

    public func page(at position: Int) -> UIView? { pages[position] }

    /// Forgets (and removes) a page; the next `show` of that index builds it again.
    public func invalidate(_ position: Int) {
        finishAnimation()
        pages.removeValue(forKey: position)?.removeFromSuperview()
        if position == index { index = -1 }
    }

    public func reset() {
        finishAnimation()
        dragging = false
        absorbing = false
        pages.values.forEach { $0.removeFromSuperview() }
        pages = [:]
        index = -1
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        for view in pages.values { fit(view) }
    }

    /// Sets the size through bounds / center so it stays valid while a page carries a slide transform.
    private func fit(_ view: UIView) {
        view.bounds = CGRect(origin: .zero, size: bounds.size)
        view.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    @discardableResult
    private func ensure(_ position: Int) -> UIView {
        if let view = pages[position] { return view }
        let view = provider(position)
        view.translatesAutoresizingMaskIntoConstraints = true
        addSubview(view)
        fit(view)
        pages[position] = view
        didAddPage(position, view)
        return view
    }

    private func place(current: UIView, other: UIView, offset: CGFloat, side: CGFloat) {
        current.transform = CGAffineTransform(translationX: offset, y: 0)
        other.transform = CGAffineTransform(translationX: offset + side * bounds.width, y: 0)
    }

    /// Position implied by a pair offset, relative to the page the movement started on.
    private func report(_ offset: CGFloat) {
        guard bounds.width > 0 else { return }
        onProgress(CGFloat(dragFrom) + CGFloat(dragTarget - dragFrom) * min(1, abs(offset) / bounds.width))
    }

    // MARK: - Tap slide

    /// Shows page `position`; with `animate` it slides in from the side of the tab that was tapped.
    public func show(_ position: Int, animate: Bool) {
        guard position >= 0, position < pageCount else { return }
        finishAnimation()
        dragging = false
        // The pager's own size comes from its ancestors; settle them first so the new page gets a real frame.
        var root: UIView = self
        while let parent = root.superview { root = parent }
        root.layoutIfNeeded()
        let from = index
        let old = pages[from]
        let next = ensure(position)
        index = position
        if next === old {
            next.isHidden = false
            next.transform = .identity
            onProgress(CGFloat(position))
            return
        }
        guard animate, Motion.enabled, from >= 0, bounds.width > 0, let old else {
            for page in pages.values {
                page.isHidden = page !== next
                page.transform = .identity
            }
            onProgress(CGFloat(position))
            return
        }
        let direction: CGFloat = position > from ? 1 : -1
        for page in pages.values where page !== old && page !== next { page.isHidden = true }
        next.isHidden = false
        dragFrom = from
        dragTarget = position
        place(current: old, other: next, offset: 0, side: direction)
        settle(current: old, other: next, side: direction, from: 0, to: -direction * bounds.width,
               duration: Self.slideDuration, commit: true)
    }

    // MARK: - Drag

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        guard swipeEnabled, pageCount > 1, index >= 0 else { return false }
        let velocity = pan.velocity(in: self)
        // Only a clearly horizontal drag pages; anything else belongs to the list inside the page.
        guard abs(velocity.x) > abs(velocity.y) * 1.2 else { return false }
        let direction = velocity.x < 0 ? -1 : 1
        if yieldDrag(pan.location(in: self), direction) { return false }
        finishAnimation()
        return true
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            let dx = gesture.translation(in: self).x
            let towardsNext = dx == 0 ? gesture.velocity(in: self).x < 0 : dx < 0
            let target = index + (towardsNext ? 1 : -1)
            guard index >= 0, target >= 0, target < pageCount, pages[index] != nil else {
                // First / last page dragged outwards: nothing to move to, but the gesture is still taken (which cancels
                // the press of the row under the finger) and simply swallowed.
                absorbing = true
                return
            }
            absorbing = false
            beginDrag(target)
            dragTo(gesture.translation(in: self).x)
        case .changed:
            if dragging { dragTo(gesture.translation(in: self).x) }
        case .ended, .cancelled, .failed:
            absorbing = false
            if dragging { release(velocity: gesture.velocity(in: self).x, cancelled: gesture.state != .ended) }
        default:
            break
        }
    }

    private func beginDrag(_ target: Int) {
        guard let current = pages[index] else { return }
        dragging = true
        dragFrom = index
        dragTarget = target
        dragOffset = 0
        let next = ensure(target)
        for (position, page) in pages where position != index && position != target { page.isHidden = true }
        current.isHidden = false
        next.isHidden = false
        place(current: current, other: next, offset: 0, side: target > index ? 1 : -1)
    }

    private func dragTo(_ raw: CGFloat) {
        guard let current = pages[dragFrom], let next = pages[dragTarget] else { return }
        let width = bounds.width
        // Towards the next page the offset is negative, towards the previous one positive; never past the origin.
        let towardsNext = dragTarget > dragFrom
        dragOffset = towardsNext ? max(-width, min(0, raw)) : max(0, min(width, raw))
        place(current: current, other: next, offset: dragOffset, side: towardsNext ? 1 : -1)
        report(dragOffset)
    }

    private func release(velocity vx: CGFloat, cancelled: Bool) {
        dragging = false
        let width = bounds.width
        guard width > 0, let current = pages[dragFrom], let next = pages[dragTarget] else { return }
        let towardsNext = dragTarget > dragFrom
        let travelled = abs(dragOffset) / width
        let flingForward = towardsNext ? vx < -Self.minFling : vx > Self.minFling
        let flingBack = towardsNext ? vx > Self.minFling : vx < -Self.minFling
        let commit = !cancelled && !flingBack && (travelled > Self.commitRatio || flingForward)
        let to: CGFloat = commit ? (towardsNext ? -width : width) : 0
        let start = dragOffset
        let target = dragTarget
        if commit {
            index = target
            onSwiped(target)
        }
        let share = min(1, max(0.35, abs(to - start) / width))
        let duration = max(0.09, Motion.base * Double(share))
        settle(current: current, other: next, side: towardsNext ? 1 : -1, from: start, to: to,
               duration: duration, commit: commit)
    }

    // MARK: - Animation

    /// Moves a page pair from offset `from` to `to` on the shared ease-out curve; the tab bar follows every frame.
    private func settle(current: UIView, other: UIView, side: CGFloat, from: CGFloat, to: CGFloat,
                        duration: CFTimeInterval, commit: Bool) {
        run(duration, step: { [weak self] eased in
            guard let self else { return }
            let offset = from + (to - from) * eased
            self.place(current: current, other: other, offset: offset, side: side)
            self.report(offset)
        }, done: {
            (commit ? current : other).isHidden = true
            current.transform = .identity
            other.transform = .identity
        })
    }

    private func run(_ duration: CFTimeInterval, step: @escaping (CGFloat) -> Void, done: @escaping () -> Void) {
        finishAnimation()
        animStep = step
        animDone = done
        animStart = CACurrentMediaTime()
        animDuration = duration
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        let t = CGFloat(min(1, (CACurrentMediaTime() - animStart) / animDuration))
        if t >= 1 {
            finishAnimation()
        } else {
            animStep?(Motion.ease(Motion.easeOut, t))
        }
    }

    /// Jumps a running animation to its end so the next change starts from a clean state.
    private func finishAnimation() {
        guard let step = animStep, let done = animDone else { return }
        link?.invalidate()
        link = nil
        animStep = nil
        animDone = nil
        step(1)
        done()
    }
}
