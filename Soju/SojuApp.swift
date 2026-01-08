//
//  SojuApp.swift
//  Soju
//
//  Created on 2026-01-07.
//

import SwiftUI
import SojuKit
import os.log

@main
struct SojuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Log app launch to file
        Logger.sojuKit.logWithFile("🍶 Soju app launched", level: .info)
        Logger.sojuKit.logWithFile("📋 Log file location: \(Logger.logFileURL.path)", level: .info)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    Logger.sojuKit.logWithFile("🪟 Main window appeared", level: .info)
                }
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

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        Logger.sojuKit.logWithFile("🛑 Soju app terminating, cleaning up Wine processes...", level: .info)
        PodoSojuManager.shared.killAllWineProcesses()
        Logger.sojuKit.logWithFile("👋 Soju app terminated", level: .info)
    }
}
