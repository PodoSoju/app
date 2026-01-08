//
//  ShortcutView.swift
//  Soju
//
//  Created on 2026-01-08.
//

import SwiftUI
import SojuKit
import os.log

/// Individual shortcut card with double-tap to run
struct ShortcutView: View {
    var shortcut: DesktopIcon
    let workspace: Workspace
    @State private var opening = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                iconView
                    .frame(width: 45, height: 45)
                    .scaleEffect(opening ? 2 : 1)
                    .opacity(opening ? 0 : 1)

                // Loading indicator
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                        .frame(width: 45, height: 45)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                }
            }

            Text(shortcut.name)
                .font(.caption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
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
                Logger.sojuKit.logWithFile("Rename requested for: \(shortcut.name)", level: .debug)
            }
            Button("Remove", systemImage: "trash") {
                // TODO: Implement remove functionality
                Logger.sojuKit.logWithFile("Remove requested for: \(shortcut.name)", level: .debug)
            }
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
        Logger.sojuKit.logWithFile("Double-tap detected on shortcut: \(shortcut.name)", level: .info)

        // Check if program is already running
        if workspace.isProgramRunning(shortcut.url) {
            Logger.sojuKit.logWithFile("Program already running, focusing: \(shortcut.name)", level: .info)

            // Focus the existing window
            if workspace.focusRunningProgram(shortcut.url) {
                Logger.sojuKit.logWithFile("Successfully focused: \(shortcut.name)", level: .info)
            } else {
                Logger.sojuKit.logWithFile("Failed to focus, launching new instance: \(shortcut.name)", level: .info)
                // Fall through to launch if focus failed
                launchProgram()
            }
            return
        }

        launchProgram()
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
                Logger.sojuKit.logWithFile("Running program: \(shortcut.name)", level: .info)
                try await program.run(in: workspace)
                Logger.sojuKit.logWithFile("Program started: \(shortcut.name)", level: .info)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
                Logger.sojuKit.logWithFile("Failed to run program \(shortcut.name): \(error.localizedDescription)", level: .error)
            }

            await MainActor.run {
                isLoading = false
            }
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
