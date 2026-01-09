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
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            runProgram()
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil.line") {
                // TODO: Implement rename functionality
                Logger.sojuKit.debug("Rename requested for: \(shortcut.name)")
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
                Logger.sojuKit.info("Program already running (pgrep): \(exeName)")

                // 이미 실행 중 -> 포커스만
                await MainActor.run {
                    if workspace.focusRunningProgram(shortcut.url) {
                        Logger.sojuKit.info("Successfully focused: \(shortcut.name)")
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

        // Create program and run
        // Note: Program.run() handles registration/unregistration internally
        let program = Program(
            name: shortcut.name,
            url: shortcut.url
        )

        Task {
            do {
                Logger.sojuKit.info("Running program: \(shortcut.name)")
                try await program.run(in: workspace)
                Logger.sojuKit.info("Program started: \(shortcut.name)")

                // Wine 창이 뜰 때까지 대기 후 포커스 (무제한 대기)
                var attempt = 0
                while true {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    attempt += 1
                    let focused = await MainActor.run {
                        workspace.focusRunningProgram(shortcut.url)
                    }
                    if focused {
                        Logger.sojuKit.info("✅ Auto-focused after \(attempt)s")
                        await MainActor.run { isLoading = false }
                        return
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
                Logger.sojuKit.error("Failed to run program \(shortcut.name): \(error.localizedDescription)")
            }

            await MainActor.run { isLoading = false }
        }
    }

    private func deleteShortcut() {
        // 1. pinnedPrograms에서 제거 (전체 배열 재할당으로 didSet 트리거)
        workspace.settings.pinnedPrograms = workspace.settings.pinnedPrograms.filter { $0.url != shortcut.url }

        // 2. Desktop의 .lnk 파일이면 실제 파일도 삭제
        if shortcut.url.pathExtension.lowercased() == "lnk" {
            try? FileManager.default.removeItem(at: shortcut.url)
        }

        Logger.sojuKit.info("Deleted shortcut: \(shortcut.name)")
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
