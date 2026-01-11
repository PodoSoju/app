//
//  PodoSojuApp.swift
//  PodoSoju
//
//  Created on 2026-01-07.
//

import SwiftUI
import PodoSojuKit
import os.log

@main
struct PodoSojuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showAbout = false
    @State private var showSettings = false

    init() {
        // Log app launch to file
        Logger.podoSojuKit.info("🍇 PodoSoju app launched")
        Logger.podoSojuKit.info("📋 Log file location: \(Logger.logFileURL.path)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
                .sheet(isPresented: $showAbout) {
                    AboutView()
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1280, height: 800)
        .commands {
            // Cmd+N, Cmd+T 비활성화
            CommandGroup(replacing: .newItem) { }

            CommandGroup(replacing: .appInfo) {
                Button("About PodoSoju") {
                    showAbout = true
                }
            }
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Settings...") {
                    showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // 로그 창 (별도 윈도우)
        Window("Wine Logs", id: "log-window") {
            LogWindowView()
        }
        .defaultSize(width: 800, height: 600)
        .keyboardShortcut("l", modifiers: [.command, .option])
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var shouldTerminate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 탭 기능 비활성화
        NSWindow.allowsAutomaticWindowTabbing = false

        // Wine 앱 모니터 시작
        Task { @MainActor in
            WineAppMonitor.shared.startMonitoring()
        }

        // 메인 윈도우에 delegate 설정
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let window = NSApp.windows.first {
                window.delegate = self
            }
        }

        // SIGTERM 핸들러 - kill -15로 종료 시 Wine도 정리
        signal(SIGTERM) { _ in
            SojuManager.shared.killAllWineProcesses()
            exit(0)
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
                Logger.podoSojuKit.info("User confirmed Wine process termination (window close)")
                SojuManager.shared.killAllWineProcesses()
                shouldTerminate = true
                return true  // 창 닫기 허용
            } else {
                // 취소 → 창 닫기 거부
                Logger.podoSojuKit.info("User cancelled window close")
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
                Logger.podoSojuKit.info("User confirmed Wine process termination")
                SojuManager.shared.killAllWineProcesses()
                return .terminateNow
            } else {
                Logger.podoSojuKit.info("User cancelled app termination")
                return .terminateCancel
            }
        }

        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 탭 복원을 위해 isTerminating 설정 (onDisappear에서 remove 방지)
        MainActor.assumeIsolated {
            OpenWorkspacesStore.shared.isTerminating = true
            OpenWorkspacesStore.shared.persist()
        }
        Logger.podoSojuKit.info("👋 PodoSoju app terminated")
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
            Logger.podoSojuKit.error("Failed to count Wine processes: \(error)")
        }

        return 0
    }
}
