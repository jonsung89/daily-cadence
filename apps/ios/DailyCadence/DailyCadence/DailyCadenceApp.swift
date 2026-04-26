//
//  DailyCadenceApp.swift
//  DailyCadence
//
//  Created by Jon Sung on 4/24/26.
//

import SwiftUI
import TipKit

@main
struct DailyCadenceApp: App {
    init() {
        FontLoader.registerAll()
        // TipKit needs to be configured once, as early as possible.
        // `.immediate` means tips show as soon as their rules pass —
        // we already gate `CardActionsTip` on a "user has used the
        // menu" event, so per-tip rules drive frequency, not the
        // global rate limiter. `.applicationDefault` persists tip
        // state in the app's group container.
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault),
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
