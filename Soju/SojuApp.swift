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

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var shouldTerminate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 메인 윈도우에 delegate 설정
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let window = NSApp.windows.first {
                window.delegate = self
            }
        }
    }

    /// 마지막 창이 닫히면 앱도 종료
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    /// 창 닫기 전에 가로채기 (X 버튼)
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Wine 프로세스 개수 확인
        let wineProcessCount = countWineProcesses()

        if wineProcessCount > 0 {
            // Wine 앱 실행 중 → 확인 알럿 (모달로 창 위에 표시)
            let alert = NSAlert()
            alert.messageText = "Wine 앱 종료"
            alert.informativeText = "\(wineProcessCount)개의 Wine 앱이 실행 중입니다.\n모두 종료하시겠습니까?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "종료")
            alert.addButton(withTitle: "취소")

            // 모달로 표시 (창 위에)
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // 종료 선택 → Wine 종료 후 창 닫기 허용
                Logger.sojuKit.logWithFile("User confirmed Wine process termination (window close)", level: .info)
                PodoSojuManager.shared.killAllWineProcesses()
                shouldTerminate = true
                return true  // 창 닫기 허용
            } else {
                // 취소 → 창 닫기 거부
                Logger.sojuKit.logWithFile("User cancelled window close", level: .info)
                return false  // 창 닫기 거부
            }
        }

        // Wine 앱 없으면 바로 닫기
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 이미 종료 동의한 경우 (windowShouldClose에서 처리됨)
        if shouldTerminate {
            return .terminateNow
        }

        // Cmd+Q로 직접 종료 시도한 경우
        let wineProcessCount = countWineProcesses()

        if wineProcessCount > 0 {
            let alert = NSAlert()
            alert.messageText = "Wine 앱 종료"
            alert.informativeText = "\(wineProcessCount)개의 Wine 앱이 실행 중입니다.\n모두 종료하시겠습니까?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "종료")
            alert.addButton(withTitle: "취소")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                Logger.sojuKit.logWithFile("User confirmed Wine process termination", level: .info)
                PodoSojuManager.shared.killAllWineProcesses()
                return .terminateNow
            } else {
                Logger.sojuKit.logWithFile("User cancelled app termination", level: .info)
                return .terminateCancel
            }
        }

        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.sojuKit.logWithFile("👋 Soju app terminated", level: .info)
    }

    /// Wine 프로세스 개수 확인
    private func countWineProcesses() -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "C:\\\\"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
                return lines.count
            }
        } catch {
            Logger.sojuKit.logWithFile("Failed to count Wine processes: \(error)", level: .error)
        }

        return 0
    }
}
