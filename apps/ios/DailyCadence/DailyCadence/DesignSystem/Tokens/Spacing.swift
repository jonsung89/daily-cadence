import CoreGraphics

/// DailyCadence spacing scale.
///
/// 8-point grid with a 4-point half-step. Values mirror the `--space-*` tokens
/// in `project/colors_and_type.css`. Common gaps: `s2 / s3 / s4 / s5 / s6`.
enum Spacing {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let s7: CGFloat = 48
    static let s8: CGFloat = 64
    static let s9: CGFloat = 96
}
