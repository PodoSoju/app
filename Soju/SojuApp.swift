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
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Soju") {
                    // TODO: Show about window
                }
            }
        }
    }
}
