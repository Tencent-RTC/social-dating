import UIKit
import ObjectiveC

public protocol HostRemoteImageLoader: AnyObject {
    func load(url: URL, completion: @escaping (UIImage?) -> Void)
}

public enum HostImage {
    public static var remoteLoader: HostRemoteImageLoader = DefaultRemoteImageLoader()

    private static let maxRetryCount = 2
    private static let retryDelay: TimeInterval = 1.2

    private static var refKey: UInt8 = 0

    public static func isRemote(_ ref: String?) -> Bool {
        guard let ref else { return false }
        return ref.hasPrefix("http://") || ref.hasPrefix("https://")
    }

    public static func bind(_ view: UIImageView, ref: String?, completion: ((Bool) -> Void)? = nil) {
        bind(view, ref: ref, attempt: 0, completion: completion)
    }

    private static func bind(_ view: UIImageView, ref: String?, attempt: Int, completion: ((Bool) -> Void)?) {
        if attempt == 0 {
            objc_setAssociatedObject(view, &refKey, ref, .OBJC_ASSOCIATION_COPY_NONATOMIC)
            view.image = nil
        }
        guard let ref, !ref.isEmpty else { completion?(false); return }
        if isRemote(ref), let url = URL(string: ref) {
            remoteLoader.load(url: url) { [weak view] image in
                DispatchQueue.main.async {
                    guard let view, objc_getAssociatedObject(view, &refKey) as? String == ref else { return }
                    if let image {
                        view.image = image
                        completion?(true)
                        return
                    }
                    completion?(false)
                    guard attempt < maxRetryCount else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                        guard objc_getAssociatedObject(view, &refKey) as? String == ref else { return }
                        bind(view, ref: ref, attempt: attempt + 1, completion: nil)
                    }
                }
            }
            return
        }
        let image = Host.image(ref)
        view.image = image
        completion?(image != nil)
    }
}

private final class DefaultRemoteImageLoader: HostRemoteImageLoader {
    private let cache = NSCache<NSURL, UIImage>()

    func load(url: URL, completion: @escaping (UIImage?) -> Void) {
        if let cached = cache.object(forKey: url as NSURL) { completion(cached); return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap { UIImage(data: $0) }
            if let image { self?.cache.setObject(image, forKey: url as NSURL) }
            completion(image)
        }.resume()
    }
}

public extension Host {
    static func pin(_ child: UIView, to parent: UIView) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor), child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor), child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
        ])
    }

    static func photo(_ ref: String?, radius: CGFloat = 0) -> UIView {
        let container = UIView()
        container.backgroundColor = tokens.bgColorFunction
        container.clipsToBounds = true
        container.layer.cornerRadius = radius
        let image = UIImageView()
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.translatesAutoresizingMaskIntoConstraints = false
        HostImage.bind(image, ref: ref)
        container.addSubview(image)
        pin(image, to: container)
        return container
    }
}

public final class HostStateView: UIView {
    private let message = label("", 13, Host.tokens.textColorTertiary)
    private var retry: (() -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        message.textAlignment = .center
        message.translatesAutoresizingMaskIntoConstraints = false
        addSubview(message)
        NSLayoutConstraint.activate([
            message.centerXAnchor.constraint(equalTo: centerXAnchor),
            message.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            message.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isHidden = true
    }

    public required init?(coder: NSCoder) { fatalError() }

    public func showLoading() {
        message.text = DemoText.get("demo_loading")
        retry = nil
        isHidden = false
    }

    public func showError(retry: @escaping () -> Void) {
        message.text = DemoText.get("demo_load_failed_tap_to_retry")
        self.retry = retry
        isHidden = false
    }

    public func showEmpty() {
        message.text = DemoText.get("demo_nothing_here_yet")
        retry = nil
        isHidden = false
    }

    public func hide() {
        isHidden = true
    }

    @objc private func tapped() { retry?() }
}
