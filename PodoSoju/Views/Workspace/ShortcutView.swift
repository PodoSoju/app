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

    var body: some View {
        VStack(spacing: 8) {
            iconView
                .frame(width: 45, height: 45)
                .scaleEffect(opening ? 2 : 1)
                .opacity(opening ? 0 : 1)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.4)
                        .frame(width: 8, height: 8)
                }

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
            Button("Rename", systemImage: "pencil.line") {
                // TODO: Implement rename functionality
                Logger.podoSojuKit.debug("Rename requested for: \(shortcut.name)")
            }
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
    }

    // MARK: - Views

    /// Icon view displaying SF Symbol
    @ViewBuilder
    private var iconView: some View {
        Image(systemName: shortcut.iconImage)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
    }

    // MARK: - Actions
    private func runProgram() {
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

                // 새 Wine 창이 뜰 때까지 대기 (최대 60초)
                for attempt in 1...60 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)

                    // 내 프로그램의 창이 열렸는지 확인
                    let (found, shouldStop) = await MainActor.run {
                        checkMyWindowOpened(programURL: shortcut.url, launchTime: launchTime)
                    }

                    if found {
                        Logger.podoSojuKit.info("✅ Window detected after \(attempt)s: \(shortcut.name)")
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
                await MainActor.run {
                    errorMessage = "프로그램이 60초 내에 창을 열지 않았습니다.\n크래시했거나 백그라운드에서 실행 중일 수 있습니다.\n\nCmd+Option+L로 로그를 확인하세요."
                    showError = true
                }
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

    /// 내 프로그램의 창이 열렸는지 확인
    private func checkMyWindowOpened(programURL: URL, launchTime: Date) -> (found: Bool, shouldStop: Bool) {
        let programName = programURL.deletingPathExtension().lastPathComponent.lowercased()

        // pgrep으로 프로세스 실행 중인지 확인
        let isRunning = SojuManager.shared.isProcessRunning(exeName: programName + ".exe")

        if !isRunning {
            // 프로세스가 종료됨 (설치 완료 등)
            return (false, true)
        }

        // Wine 창 목록에서 내 프로그램 찾기
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return (false, false)
        }

        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String else {
                continue
            }

            if ownerName.lowercased().contains("wine") {
                // Wine 창이 있으면 성공으로 간주
                // (창 이름이 비어있어도 OK - macOS 권한 문제로 가져오지 못할 수 있음)
                return (true, false)
            }
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
