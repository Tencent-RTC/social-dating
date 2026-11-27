import UIKit
import ObjectiveC

private var transitionKey: UInt8 = 0

public final class HostNavigationTransition: NSObject, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
    private weak var navigation: UINavigationController?
    private var interaction: UIPercentDrivenInteractiveTransition?
    private let edgePan = UIScreenEdgePanGestureRecognizer()

    public static func install(on navigation: UINavigationController) {
        guard objc_getAssociatedObject(navigation, &transitionKey) == nil else { return }
        let transition = HostNavigationTransition()
        transition.navigation = navigation
        objc_setAssociatedObject(navigation, &transitionKey, transition, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        navigation.delegate = transition
        navigation.interactivePopGestureRecognizer?.isEnabled = false
        transition.edgePan.edges = .left
        transition.edgePan.delegate = transition
        transition.edgePan.addTarget(transition, action: #selector(handleEdgePan(_:)))
        navigation.view.addGestureRecognizer(transition.edgePan)
    }

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard let navigation, let view = gesture.view else { return }
        let progress = max(0, min(1, gesture.translation(in: view).x / view.bounds.width))
        switch gesture.state {
        case .began:
            interaction = UIPercentDrivenInteractiveTransition()
            navigation.popViewController(animated: true)
        case .changed:
            interaction?.update(progress)
        case .ended, .cancelled, .failed:
            let velocity = gesture.velocity(in: view).x
            if gesture.state == .ended && (progress > 0.4 || velocity > 600) {
                interaction?.finish()
            } else {
                interaction?.cancel()
            }
            interaction = nil
        default:
            break
        }
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigation, gestureRecognizer === edgePan else { return true }
        return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil && navigation.presentedViewController == nil
    }

    public func navigationController(_ navigationController: UINavigationController,
                                     animationControllerFor operation: UINavigationController.Operation,
                                     from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard Motion.enabled, operation != .none else { return nil }
        return HostPushAnimator(operation: operation)
    }

    public func navigationController(_ navigationController: UINavigationController,
                                     interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        interaction
    }
}

final class HostPushAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private static let parallax: CGFloat = 0.24
    private static let dimAlpha: CGFloat = 0.28
    fileprivate static var lastTabBarPicture: UIView?
    private let operation: UINavigationController.Operation

    init(operation: UINavigationController.Operation) {
        self.operation = operation
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { Motion.slow }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from), let toView = transitionContext.view(forKey: .to),
              let toController = transitionContext.viewController(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }
        let container = transitionContext.containerView
        let width = container.bounds.width
        let pushing = operation == .push
        toView.frame = transitionContext.finalFrame(for: toController).isEmpty ? container.bounds : transitionContext.finalFrame(for: toController)
        let dim = UIView(frame: container.bounds)
        dim.backgroundColor = .black
        dim.isUserInteractionEnabled = false
        let behind = pushing ? fromView : toView
        let front = pushing ? toView : fromView
        // Android slides the whole window, bottom navigation included. Here the tab bar belongs to the tab controller
        // and the system would delete it (push) or drop it in (pop) on the first frame, so a stand-in copy travels with
        // the page behind while the real bar stays out of sight until the transition ends.
        let tabBarStandIn = makeTabBarStandIn(pushing: pushing, from: transitionContext.viewController(forKey: .from),
                                              to: toController, container: container)
        if pushing {
            container.addSubview(toView)
            container.insertSubview(dim, belowSubview: toView)
            toView.transform = CGAffineTransform(translationX: width, y: 0)
            dim.alpha = 0
        } else {
            container.insertSubview(toView, belowSubview: fromView)
            container.insertSubview(dim, belowSubview: fromView)
            toView.transform = CGAffineTransform(translationX: -width * Self.parallax, y: 0)
            dim.alpha = Self.dimAlpha
        }
        if let standIn = tabBarStandIn {
            container.insertSubview(standIn.view, belowSubview: dim)
            standIn.view.transform = pushing ? .identity : CGAffineTransform(translationX: -width * Self.parallax, y: 0)
        }
        let apply = {
            front.transform = pushing ? .identity : CGAffineTransform(translationX: width, y: 0)
            behind.transform = pushing ? CGAffineTransform(translationX: -width * Self.parallax, y: 0) : .identity
            tabBarStandIn?.view.transform = pushing ? CGAffineTransform(translationX: -width * Self.parallax, y: 0) : .identity
            dim.alpha = pushing ? Self.dimAlpha : 0
        }
        let finish: (Bool) -> Void = { _ in
            let cancelled = transitionContext.transitionWasCancelled
            fromView.transform = .identity
            toView.transform = .identity
            dim.removeFromSuperview()
            tabBarStandIn?.view.removeFromSuperview()
            tabBarStandIn?.tabBar.layer.opacity = 1
            transitionContext.completeTransition(!cancelled)
        }
        if transitionContext.isInteractive {
            UIView.animate(withDuration: Motion.slow, delay: 0, options: [.curveLinear], animations: apply, completion: finish)
        } else {
            Motion.animate(Motion.slow, Motion.easeOut, animations: apply, completion: finish)
        }
    }
}

extension HostPushAnimator {
    /// A picture of the tab bar when this push / pop shows or hides it; nil when the bar is not involved.
    private func makeTabBarStandIn(pushing: Bool, from: UIViewController?, to: UIViewController,
                                   container: UIView) -> (view: UIView, tabBar: UITabBar, restoreAlpha: CGFloat)? {
        // iOS 26 draws the tab bar as a floating glass capsule that the system hides and shows on its own layer;
        // faking it there leaves a ghost behind, so only the classic bar gets a stand-in.
        if #available(iOS 26.0, *) { return nil }
        guard let from, let tabBar = to.tabBarController?.tabBar ?? from.tabBarController?.tabBar else { return nil }
        let hidingNow = pushing && to.hidesBottomBarWhenPushed && !from.hidesBottomBarWhenPushed
        let showingNow = !pushing && from.hidesBottomBarWhenPushed && !to.hidesBottomBarWhenPushed
        guard hidingNow || showingNow else { return nil }
        let wasHidden = tabBar.isHidden
        if showingNow, wasHidden { tabBar.isHidden = false }
        // Coming back, the system has only just re-shown the bar and has not drawn its items yet, so the picture taken
        // when the page was pushed (the bar was fully drawn then) is reused; badges rarely change in between.
        let picture: UIView
        if showingNow, let cached = HostPushAnimator.lastTabBarPicture {
            picture = cached
        } else {
            guard let live = tabBar.snapshotView(afterScreenUpdates: showingNow) else { return nil }
            picture = live
            if hidingNow { HostPushAnimator.lastTabBarPicture = live }
        }
        // The system parks a hidden bar below the screen, so place the copy where the bar sits when shown.
        let barHeight = tabBar.bounds.height
        picture.transform = .identity
        picture.frame = CGRect(x: 0, y: container.bounds.height - barHeight, width: container.bounds.width, height: barHeight)
        picture.isUserInteractionEnabled = false
        let restore: CGFloat = 1
        // The system slides the real bar around while it hides / shows it; layer opacity keeps it out of sight meanwhile.
        tabBar.layer.opacity = 0
        return (picture, tabBar, restore)
    }
}

public final class HostTabFadeAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    public func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { Motion.base }

    public func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from), let toView = transitionContext.view(forKey: .to),
              let toController = transitionContext.viewController(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }
        let container = transitionContext.containerView
        toView.frame = transitionContext.finalFrame(for: toController).isEmpty ? container.bounds : transitionContext.finalFrame(for: toController)
        container.addSubview(toView)
        toView.alpha = 0
        toView.transform = CGAffineTransform(translationX: 0, y: 10).scaledBy(x: 0.99, y: 0.99)
        Motion.animate(Motion.base, Motion.easeOut, animations: {
            toView.alpha = 1
            toView.transform = .identity
            fromView.alpha = 0
            fromView.transform = CGAffineTransform(translationX: 0, y: 6)
        }, completion: { _ in
            fromView.alpha = 1
            fromView.transform = .identity
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        })
    }
}
