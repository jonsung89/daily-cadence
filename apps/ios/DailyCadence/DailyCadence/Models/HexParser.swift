import Foundation

/// Parses and formats 24-bit RGB hex literals used throughout the design
/// system's JSON config files.
///
/// JSON stores colors as human-readable strings (`"#5A7B6D"`) so a future
/// admin panel can edit them without touching code. Swift consumes them as
/// `UInt32` values feeding into `Color(hex:)`.
enum HexParser {

    /// Parse `"#5A7B6D"` or `"5A7B6D"` into a 24-bit RGB value. Returns `nil`
    /// for malformed input. Callers that want a graceful default can use
    /// `parseOrZero(_:)`.
    static func parse(_ string: String) -> UInt32? {
        let stripped: String
        if string.hasPrefix("#") {
            stripped = String(string.dropFirst())
        } else {
            stripped = string
        }
        guard stripped.count == 6 else { return nil }
        return UInt32(stripped, radix: 16)
    }

    /// Parse a hex string, returning 0 (black) on malformed input. Convenient
    /// inside view-layer computed properties where throwing would bubble up
    /// to view builders.
    static func parseOrZero(_ string: String) -> UInt32 {
        parse(string) ?? 0
    }

    /// Format a 24-bit RGB value back to `"#RRGGBB"`. Used when the admin
    /// panel (or tests) need to round-trip colors through JSON.
    static func format(_ value: UInt32) -> String {
        String(format: "#%06X", value & 0xFFFFFF)
    }
}
