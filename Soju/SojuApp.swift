//
//  SojuApp.swift
//  Soju
//
//  Created on 2026-01-07.
//

import SwiftUI

@main
struct SojuApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Soju") {
                    // TODO: Show about window
                }
            }
        }
    }
}
