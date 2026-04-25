import CoreText
import Foundation
import OSLog

/// Registers DailyCadence's bundled font files with Core Text so `Font.custom`
/// and `UIFont(name:size:)` can resolve them.
///
/// Called automatically on first access to any `Font.DS` token (see
/// `Font+DS.swift`) and explicitly from `DailyCadenceApp.init()` so app-launch
/// surfaces see real type before any view reads the tokens.
///
/// Idempotent: calling `registerAll()` more than once is a no-op after the
/// first successful registration.
enum FontLoader {

    /// File basenames (without `.ttf`) for every bundled typeface.
    /// Each entry must exist at `Resources/Fonts/<name>.ttf`.
    private static let fontFileNames: [String] = [
        "Inter",
        "PlayfairDisplay",
        "Manrope",
    ]

    private static let log = Logger(subsystem: "com.jonsung.DailyCadence", category: "FontLoader")
    private static var hasRegistered = false
    private static let lock = NSLock()

    /// Register every bundled font file with Core Text. Safe to call from any
    /// thread; safe to call repeatedly.
    static func registerAll(bundle: Bundle = .main) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasRegistered else { return }

        for name in fontFileNames {
            guard let url = bundle.url(forResource: name, withExtension: "ttf") else {
                log.error("Font file missing from bundle: \(name).ttf")
                continue
            }
            var cfError: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &cfError)
            if ok {
                log.info("Registered font: \(name)")
            } else if let err = cfError?.takeRetainedValue() {
                // CTFontManagerError.alreadyRegistered (code 105) is fine — it
                // means another entry point (e.g. tests) already loaded the file.
                let code = CFErrorGetCode(err)
                if code == 105 {
                    log.debug("Font already registered: \(name)")
                } else {
                    log.error("Font registration failed for \(name): \(err.localizedDescription)")
                }
            }
        }

        hasRegistered = true
    }
}
