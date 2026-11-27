import UIKit

public enum ScreenAdaptation {
    public static let designWidth: CGFloat = 393
    public static let maxFactor: CGFloat = 1.1

    public static let factor: CGFloat = {
        let bounds = UIScreen.main.bounds
        return min(max(min(bounds.width, bounds.height) / designWidth, 1), maxFactor)
    }()

    public static func scaled(_ value: CGFloat) -> CGFloat {
        (value * factor * 2).rounded() / 2
    }
}

extension CGFloat {
    public var adapted: CGFloat { ScreenAdaptation.scaled(self) }
}

extension UIFont {
    public static func adaptiveSystemFont(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: ScreenAdaptation.scaled(size), weight: weight)
    }

    public static func adaptiveBoldSystemFont(ofSize size: CGFloat) -> UIFont {
        .boldSystemFont(ofSize: ScreenAdaptation.scaled(size))
    }
}
