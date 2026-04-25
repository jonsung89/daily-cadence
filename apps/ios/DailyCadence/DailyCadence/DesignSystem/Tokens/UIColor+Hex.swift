import UIKit

extension UIColor {
    /// Initialize a `UIColor` from a 24-bit RGB hex literal such as `0xF5F3F0`.
    ///
    /// Used internally when defining dynamic (light/dark) `Color` tokens via
    /// `UIColor { trait in … }`. For SwiftUI call sites, prefer `Color(hex:)`.
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8)  & 0xFF) / 255.0
        let b = CGFloat( hex        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
