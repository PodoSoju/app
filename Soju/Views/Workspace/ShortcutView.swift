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
    let shortcut: DesktopIcon
    let workspace: Workspace
    @State private var opening = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: shortcut.iconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 45, height: 45)
                .scaleEffect(opening ? 2 : 1)
                .opacity(opening ? 0 : 1)

            Text(shortcut.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
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
    }

    // MARK: - Actions
    private func runProgram() {
        Logger.sojuKit.logWithFile("Double-tap detected on shortcut: \(shortcut.name)", level: .info)

        // Opening animation: scale up + fade out
        withAnimation(.easeIn(duration: 0.25)) {
            opening = true
        } completion: {
            withAnimation(.easeOut(duration: 0.1)) {
                opening = false
            }
        }

        // Create program and run
        let program = Program(
            name: shortcut.name,
            url: shortcut.url
        )

        Task {
            do {
                Logger.sojuKit.logWithFile("Running program: \(shortcut.name)", level: .info)
                try await program.run(in: workspace)
                Logger.sojuKit.logWithFile("Program completed: \(shortcut.name)", level: .info)
            } catch {
                Logger.sojuKit.logWithFile("Failed to run program \(shortcut.name): \(error.localizedDescription)", level: .error)
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
