import Testing
import SwiftUI
import UIKit
@testable import DailyCadence

/// Verifies that the bundled TTFs actually register with Core Text at the
/// PostScript names `Font.DS` expects. If these fail, the app silently falls
/// back to system fonts and the design breaks — catch it in tests, not visually.
struct FontLoaderTests {

    @Test func registerAllSucceeds() {
        // Idempotent — may have been registered by a prior test.
        FontLoader.registerAll()
    }

    @Test func interIsAvailable() {
        FontLoader.registerAll()
        #expect(UIFont(name: "Inter-Regular", size: 16) != nil,
                "Inter-Regular PS name must resolve after registration")
        #expect(UIFont.fontNames(forFamilyName: "Inter").isEmpty == false,
                "Inter family must expose at least one face")
    }

    @Test func playfairDisplayIsAvailable() {
        FontLoader.registerAll()
        #expect(UIFont(name: "PlayfairDisplay-Regular", size: 32) != nil,
                "PlayfairDisplay-Regular PS name must resolve after registration")
        #expect(UIFont.fontNames(forFamilyName: "Playfair Display").isEmpty == false,
                "Playfair Display family must expose at least one face")
    }

    @Test func manropeExtraBoldIsAvailable() {
        FontLoader.registerAll()
        // Named instance PS name — verified via fontTools against Manrope.ttf.
        // If the font file changes, this expectation protects the logomark
        // from silently falling back to the default Manrope weight.
        #expect(UIFont(name: "Manrope-ExtraBold", size: 72) != nil,
                "Manrope-ExtraBold named instance must resolve (used by DailyCadenceLogomark)")
    }

    @Test func interVariableFontAcceptsWeightAxis() {
        FontLoader.registerAll()
        // Inter's variable TTF lacks PS-named instances, so we rely on
        // Font.custom("Inter-Regular").weight(_) traversing the wght axis.
        // Verify the underlying UIFont lookup still works with symbolic trait
        // application — this is what Font.DS.label depends on.
        guard let base = UIFont(name: "Inter-Regular", size: 14) else {
            Issue.record("Inter-Regular base font missing")
            return
        }
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.medium.rawValue]
        ])
        let medium = UIFont(descriptor: descriptor, size: 14)
        #expect(medium.familyName == "Inter",
                "Weighted Inter must still resolve to the Inter family, not a fallback")
    }
}
