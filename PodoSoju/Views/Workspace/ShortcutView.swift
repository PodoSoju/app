//
//  ShortcutView.swift
//  PodoSoju
//
//  Created on 2026-01-08.
//

import SwiftUI
import PodoSojuKit
import os.log

/// Individual shortcut card with double-tap to run
struct ShortcutView: View {
    var shortcut: DesktopIcon
    let workspace: Workspace
    @State private var opening = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showDeleteConfirmation = false
    @State private var isSelected = false
    @State private var showUpdateSuccess = false
    @State private var updatedVersion = ""

    var body: some View {
        VStack(spacing: 8) {
            iconView
                .frame(width: 45, height: 45)
                .scaleEffect(opening ? 2 : 1)
                .opacity(opening ? 0 : 1)
                .overlay(alignment: .topTrailing) {
                    extensionBadge
                }
                .overlay {
                    if isLoading {
                        ZStack {
                            Color.black.opacity(0.5)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                    }
                }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(shortcut.name)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
            }
        }
        .frame(width: 90, height: 90)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 1) {
            // Single click: select/focus
            isSelected = true
        }
        .onTapGesture(count: 2) {
            runProgram()
        }
        .contextMenu {
            Button("Run", systemImage: "play.fill") {
                runProgram()
            }
            Divider()
            if shortcut.url.pathExtension.lowercased() == "app" {
                // .app은 이미 포도주스 - 버전 표시
                let appVersion = getAppBundleVersion(shortcut.url)
                let currentVersion = getCurrentPodoJuiceVersion()

                if appVersion < currentVersion {
                    Button("포도주스 업데이트 (\(appVersion) → \(currentVersion))", systemImage: "arrow.up.circle") {
                        isLoading = true
                        Task {
                            await updateAppBundleAsync()
                        }
                    }
                } else {
                    Text("포도주스 v\(appVersion)")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("포도주스 만들기", systemImage: "drop.fill") {
                    createAppBundle()
                }
            }
            Button("Rename", systemImage: "pencil.line") {
                // TODO: Implement rename functionality
                Logger.podoSojuKit.debug("Rename requested for: \(shortcut.name)")
            }
            Divider()
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete \"\(shortcut.name)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteShortcut()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the shortcut from your workspace.")
        }
        .alert("실행 오류", isPresented: $showError) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("업데이트 완료", isPresented: $showUpdateSuccess) {
            Button("확인", role: .cancel) { }
        } message: {
            Text("포도주스 v\(updatedVersion)으로 업데이트되었습니다.")
        }
    }

    // MARK: - Views

    /// Icon view displaying actual exe icon or SF Symbol fallback
    @ViewBuilder
    private var iconView: some View {
        if let nsImage = shortcut.actualIcon {
            // Actual exe icon from .soju/apps/
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
        } else {
            // SF Symbol fallback
            Image(systemName: shortcut.iconImage)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
        }
    }

    /// Extension badge (top-right corner)
    @ViewBuilder
    private var extensionBadge: some View {
        let ext = shortcut.url.pathExtension.lowercased()
        if !ext.isEmpty {
            Text(ext)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .offset(x: 5, y: -5)
        }
    }

    // MARK: - Actions
    private func runProgram() {
        // 이미 실행 중이면 포커스만 주기
        if workspace.focusRunningProgram(shortcut.url) {
            Logger.podoSojuKit.info("Focused existing window: \(shortcut.name)")
            return
        }

        // .app 파일은 직접 실행 (PodoJuice) - 인디케이터는 PodoJuice 로딩창이 대체
        if shortcut.url.pathExtension.lowercased() == "app" {
            Logger.podoSojuKit.info("Opening PodoJuice app: \(shortcut.name)")
            isLoading = true
            NSWorkspace.shared.open(shortcut.url)

            // PodoJuice 로딩창이 처리하므로 1.5초 후 인디케이터 종료
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    isLoading = false
                }
            }
            return
        }

        Task {
            // .lnk 파일이면 실제 exe 경로 추출
            let exeName: String
            if shortcut.url.pathExtension.lowercased() == "lnk" {
                if let targetURL = try? await ShortcutParser.parseShortcut(shortcut.url, winePrefixURL: workspace.winePrefixURL) {
                    exeName = targetURL.lastPathComponent
                } else {
                    exeName = shortcut.url.lastPathComponent
                }
            } else {
                exeName = shortcut.url.lastPathComponent
            }

            // pgrep으로 실제 실행 중인지 확인
            if SojuManager.shared.isProcessRunning(exeName: exeName) {
                Logger.podoSojuKit.info("Program already running (pgrep): \(exeName)")

                // 이미 실행 중 -> 포커스만
                await MainActor.run {
                    if workspace.focusRunningProgram(shortcut.url) {
                        Logger.podoSojuKit.info("Successfully focused: \(shortcut.name)")
                    }
                }
                return
            }

            // 실행 중 아님 -> 새로 실행
            await MainActor.run {
                launchProgram()
            }
        }
    }

    private func launchProgram() {
        isLoading = true

        // Opening animation: scale up + fade out
        withAnimation(.easeIn(duration: 0.25)) {
            opening = true
        } completion: {
            withAnimation(.easeOut(duration: 0.1)) {
                opening = false
            }
        }

        // 대기 중인 프로그램 등록
        Self.pendingLaunches.insert(shortcut.url)
        let launchTime = Date()

        // Create program and run
        let program = Program(
            name: shortcut.name,
            url: shortcut.url
        )

        Task {
            do {
                Logger.podoSojuKit.info("Running program: \(shortcut.name)")
                try await program.run(in: workspace)
                Logger.podoSojuKit.info("Program started: \(shortcut.name)")

                // 새 Wine 창이 뜰 때까지 대기 (최대 30초, 0.5초 간격)
                for attempt in 1...60 {
                    try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s

                    // 내 프로그램의 창이 열렸는지 확인
                    let (found, shouldStop) = await MainActor.run {
                        checkMyWindowOpened(programURL: shortcut.url, launchTime: launchTime)
                    }

                    if found {
                        Logger.podoSojuKit.info("✅ Window detected after \(Double(attempt) * 0.5)s: \(shortcut.name)")
                        await MainActor.run {
                            workspace.focusRunningProgram(shortcut.url)
                            isLoading = false
                            Self.pendingLaunches.remove(shortcut.url)
                        }
                        return
                    }

                    if shouldStop {
                        // 프로세스가 종료됨
                        break
                    }
                }
                Logger.podoSojuKit.warning("No window after 60s: \(shortcut.name)")
                // 알럿 제거 - 백그라운드 실행 프로그램도 있으므로 경고만 로깅
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
                Logger.podoSojuKit.error("Failed to run program \(shortcut.name): \(error.localizedDescription)")
            }

            await MainActor.run {
                isLoading = false
                Self.pendingLaunches.remove(shortcut.url)
            }
        }
    }

    // 대기 중인 프로그램 추적 (static으로 공유)
    private static var pendingLaunches: Set<URL> = []
    // Stable window detection - require consecutive detections (0.5s * 3 = 1.5s)
    private static var windowStableCounts: [URL: Int] = [:]
    private static let requiredStableCount = 3  // 3 consecutive detections (1.5초)

    /// 내 프로그램의 창이 열렸는지 확인
    /// - Parameters:
    ///   - programURL: 프로그램 URL
    ///   - launchTime: 실행 시작 시간 (이 시간 이후 생성된 파일만 확인)
    /// - Returns: (found: 창 발견됨, shouldStop: 대기 중단해야 함)
    private func checkMyWindowOpened(programURL: URL, launchTime: Date) -> (found: Bool, shouldStop: Bool) {
        let exeName = programURL.lastPathComponent

        // 1. pgrep으로 프로세스 실행 중인지 확인
        let isRunning = SojuManager.shared.isProcessRunning(exeName: exeName)
        let runningApps = workspace.getRunningWineApps()

        if !isRunning && runningApps.isEmpty {
            // 프로세스가 종료됨 (설치 완료 등)
            return (false, true)
        }

        // 3. Wine 창 목록에서 내 프로그램 찾기 (stable detection - 연속 감지 필요)
        let programName = programURL.deletingPathExtension().lastPathComponent.lowercased()
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            Self.windowStableCounts[programURL] = 0
            return (false, false)
        }

        var foundWindow = false
        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String else {
                continue
            }

            if ownerName.lowercased().contains("wine") {
                // Check if window has actual size and is fully opaque
                if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                   let width = bounds["Width"], let height = bounds["Height"],
                   width > 100 && height > 100 {
                    let alpha = window[kCGWindowAlpha as String] as? CGFloat ?? 0
                    if alpha >= 1.0 {
                        foundWindow = true
                        break
                    }
                }
            }
        }

        if foundWindow {
            let count = (Self.windowStableCounts[programURL] ?? 0) + 1
            Self.windowStableCounts[programURL] = count

            if count >= Self.requiredStableCount {
                Logger.podoSojuKit.debug("Wine window stable for \(count) checks: \(programName)", category: "ShortcutView")
                Self.windowStableCounts.removeValue(forKey: programURL)
                return (true, false)
            }
            Logger.podoSojuKit.debug("Wine window found, stable count: \(count)/\(Self.requiredStableCount)", category: "ShortcutView")
        } else {
            Self.windowStableCounts[programURL] = 0
        }

        return (false, false)
    }

    private func deleteShortcut() {
        // 1. pinnedPrograms에서 제거 (전체 배열 재할당으로 didSet 트리거)
        workspace.settings.pinnedPrograms = workspace.settings.pinnedPrograms.filter { $0.url != shortcut.url }

        // 2. Desktop의 .lnk 파일이면 실제 파일도 삭제
        if shortcut.url.pathExtension.lowercased() == "lnk" {
            try? FileManager.default.removeItem(at: shortcut.url)
        }

        Logger.podoSojuKit.info("Deleted shortcut: \(shortcut.name)")
    }

    private func createAppBundle() {
        Task {
            do {
                // .lnk에서 실제 exe 경로 추출
                let exePath: String
                if shortcut.url.pathExtension.lowercased() == "lnk" {
                    if let targetURL = try? await ShortcutParser.parseShortcut(shortcut.url, winePrefixURL: workspace.winePrefixURL) {
                        // Windows 경로로 변환
                        exePath = convertToWindowsPath(unixPath: targetURL.path)
                    } else {
                        throw NSError(domain: "ShortcutView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse .lnk file"])
                    }
                } else {
                    // 직접 exe 경로
                    exePath = convertToWindowsPath(unixPath: shortcut.url.path)
                }

                // workspace ID 추출 (URL에서)
                let workspaceId = workspace.url.lastPathComponent

                // targetLnk: .lnk 파일이면 파일명, 아니면 앱 이름 + ".lnk"
                let targetLnk = shortcut.url.pathExtension.lowercased() == "lnk"
                    ? shortcut.url.lastPathComponent
                    : "\(shortcut.name).lnk"

                // 포도주스 앱 번들 생성
                let appURL = try AppBundleGenerator.createAppBundle(
                    name: shortcut.name,
                    workspaceId: workspaceId,
                    workspacePath: workspace.url.path,
                    targetLnk: targetLnk,
                    exePath: exePath,
                    icon: shortcut.actualIcon
                )

                // 성공 알럿
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "포도주스 생성 완료"
                    alert.informativeText = "'\(shortcut.name).app'이 바탕화면에 생성되었습니다.\n\n이 앱을 직접 실행하거나 Dock에 추가할 수 있습니다."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Finder에서 보기")
                    alert.addButton(withTitle: "확인")

                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        NSWorkspace.shared.activateFileViewerSelecting([appURL])
                    }
                }

                Logger.podoSojuKit.info("Created PodoJuice app for: \(shortcut.name)", category: "ShortcutView")
            } catch {
                await MainActor.run {
                    errorMessage = "포도주스 생성 실패: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    /// Unix 경로를 Windows 경로로 변환
    private func convertToWindowsPath(unixPath: String) -> String {
        // workspace 경로 기준으로 drive_c 이후 부분 추출
        let prefixPath = workspace.url.appendingPathComponent("drive_c").path

        if unixPath.hasPrefix(prefixPath) {
            let relativePath = String(unixPath.dropFirst(prefixPath.count))
            return "C:" + relativePath.replacingOccurrences(of: "/", with: "\\")
        }

        // drive_c 외의 경우 (drive_d 등)
        let workspacePath = workspace.url.path
        if unixPath.hasPrefix(workspacePath) {
            let afterWorkspace = String(unixPath.dropFirst(workspacePath.count + 1)) // +1 for "/"
            if afterWorkspace.hasPrefix("drive_") && afterWorkspace.count > 7 {
                let drive = afterWorkspace[afterWorkspace.index(afterWorkspace.startIndex, offsetBy: 6)].uppercased()
                let remainder = String(afterWorkspace.dropFirst(7))
                return "\(drive):" + remainder.replacingOccurrences(of: "/", with: "\\")
            }
        }

        // Fallback: workspace 경로 이후 부분을 C: 경로로 변환
        if unixPath.hasPrefix(workspacePath) {
            let afterWorkspace = String(unixPath.dropFirst(workspacePath.count))
            return "C:" + afterWorkspace.replacingOccurrences(of: "/", with: "\\")
        }

        // 최후 fallback: 그대로 백슬래시 변환
        return unixPath.replacingOccurrences(of: "/", with: "\\")
    }

    // MARK: - Version Helpers

    /// 앱 번들의 PodoJuice 버전 조회 (Info.plist에서)
    private func getAppBundleVersion(_ appURL: URL) -> String {
        let plistPath = appURL.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistPath),
              let version = plist["PodoJuiceVersion"] as? String else {
            return "0.0.0"
        }
        return version
    }

    /// 현재 PodoSoju에 포함된 PodoJuice 버전 (빌드 시 설정)
    private func getCurrentPodoJuiceVersion() -> String {
        // PodoSoju 빌드 시 Info.plist에 포함된 버전
        Bundle.main.object(forInfoDictionaryKey: "PodoJuiceVersion") as? String ?? "1.0.0"
    }

    /// 앱 번들의 PodoJuice 업데이트 (async)
    @MainActor
    private func updateAppBundleAsync() async {
        guard let podoJuiceURL = Bundle.main.url(forResource: "PodoJuice", withExtension: nil) else {
            isLoading = false
            errorMessage = "PodoJuice를 찾을 수 없습니다"
            showError = true
            return
        }

        let targetPath = shortcut.url.appendingPathComponent("Contents/MacOS/PodoJuice")
        let plistPath = shortcut.url.appendingPathComponent("Contents/Info.plist")
        let newVersion = AppBundleGenerator.getPodoJuiceVersion()

        do {
            // 1. PodoJuice 바이너리 업데이트
            try? FileManager.default.removeItem(at: targetPath)
            try FileManager.default.copyItem(at: podoJuiceURL, to: targetPath)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetPath.path)

            // 2. Info.plist 버전 업데이트
            if let plist = NSMutableDictionary(contentsOf: plistPath) {
                plist["PodoJuiceVersion"] = newVersion
                plist["CFBundleShortVersionString"] = newVersion
                plist.write(to: plistPath, atomically: true)
            }

            isLoading = false
            updatedVersion = newVersion
            showUpdateSuccess = true
            Logger.podoSojuKit.info("Updated PodoJuice to v\(newVersion) in \(shortcut.name)")
        } catch {
            isLoading = false
            errorMessage = "업데이트 실패: \(error.localizedDescription)"
            showError = true
        }
    }
}

#Preview {
    ShortcutView(
        shortcut: DesktopIcon(
            name: "Test Program",
            url: URL(fileURLWithPath: "/test.exe"),
            iconImage: "app.fill"
        ),
        workspace: Workspace.preview
    )
    .frame(width: 110, height: 110)
}
