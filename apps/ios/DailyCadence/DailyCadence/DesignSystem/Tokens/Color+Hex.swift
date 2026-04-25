import SwiftUI

extension Color {
    /// Initialize a `Color` from a 24-bit RGB hex literal such as `0xF5F3F0`.
    /// Uses the sRGB color space to match CSS hex values exactly.
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
