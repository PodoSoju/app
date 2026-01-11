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
        // URL scheme 호출 시 새 창 열지 않음 (AppDelegate에서 처리)
        .handlesExternalEvents(matching: [])
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

        // 로그 창 (별도 윈도우) - Cmd+Option+L로 열기
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
    private var lastHandledURL: String = ""
    private var lastHandledTime: Date = .distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 탭 기능 비활성화
        NSWindow.allowsAutomaticWindowTabbing = false

        // Wine 앱 모니터 시작
        Task { @MainActor in
            WineAppMonitor.shared.startMonitoring()
        }

        // 메인 윈도우에 delegate 설정
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.title != "Wine Logs" }) {
                window.delegate = self
            }
        }

        // SIGTERM 핸들러 - kill -15로 종료 시 Wine도 정리
        signal(SIGTERM) { _ in
            SojuManager.shared.killAllWineProcesses()
            exit(0)
        }
    }

    /// URL scheme 핸들러: podosoju://run/{workspace-id}/{encoded-exe-path}
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handlePodoSojuURL(url)
        }
    }

    private func handlePodoSojuURL(_ url: URL) {
        guard url.scheme == "podosoju" else { return }

        // 중복 호출 방지 (같은 URL이 1초 내에 다시 오면 무시)
        let urlString = url.absoluteString
        let now = Date()
        if urlString == lastHandledURL && now.timeIntervalSince(lastHandledTime) < 1.0 {
            Logger.podoSojuKit.debug("Ignoring duplicate URL: \(urlString)", category: "URLHandler")
            return
        }
        lastHandledURL = urlString
        lastHandledTime = now

        Logger.podoSojuKit.info("Received URL: \(url.absoluteString)", category: "URLHandler")

        // podosoju://run/{workspace-id}/{encoded-exe-path}
        // URL 구조: scheme://host/path → host가 "run", path가 나머지
        guard url.host == "run" else {
            Logger.podoSojuKit.warning("Invalid URL host (expected 'run'): \(url.absoluteString)", category: "URLHandler")
            return
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }

        guard pathComponents.count >= 1 else {
            Logger.podoSojuKit.warning("Invalid URL format (missing workspace-id): \(url.absoluteString)", category: "URLHandler")
            return
        }

        let workspaceId = pathComponents[0]
        let encodedPath = pathComponents.dropFirst(1).joined(separator: "/")

        guard let exePath = encodedPath.removingPercentEncoding else {
            Logger.podoSojuKit.warning("Failed to decode exe path: \(encodedPath)", category: "URLHandler")
            return
        }

        Logger.podoSojuKit.info("Running: workspace=\(workspaceId), exe=\(exePath)", category: "URLHandler")

        // Workspace 찾기 및 실행 (inline)
        // ~/Library/Containers/com.podosoju.app/Workspaces/
        let workspacesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.podosoju.app/Workspaces")

        let workspaceURL = workspacesDir.appendingPathComponent(workspaceId)

        guard FileManager.default.fileExists(atPath: workspaceURL.path) else {
            Logger.podoSojuKit.error("Workspace not found: \(workspaceId)", category: "URLHandler")
            showAlert(title: "Workspace Not Found", message: "The workspace '\(workspaceId)' does not exist.")
            return
        }

        let workspace = Workspace(workspaceUrl: workspaceURL)

        do {
            let stream = try SojuManager.shared.runWine(
                args: [exePath],
                workspace: workspace,
                captureOutput: false
            )
            // GUI 모드 - 출력 무시
            Task.detached {
                for await _ in stream { }
            }
            Logger.podoSojuKit.info("Program launched via URL scheme: \(exePath)", category: "URLHandler")
        } catch {
            Logger.podoSojuKit.error("Failed to run program: \(error.localizedDescription)", category: "URLHandler")
            showAlert(title: "Launch Failed", message: error.localizedDescription)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
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
