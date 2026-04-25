//
//  DailyCadenceApp.swift
//  DailyCadence
//
//  Created by Jon Sung on 4/24/26.
//

import SwiftUI

@main
struct DailyCadenceApp: App {
    init() {
        FontLoader.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
