//
//  ShortcutsGridView.swift
//  Soju
//
//  Created on 2026-01-08.
//

import SwiftUI
import SojuKit
import os.log
import UniformTypeIdentifiers

// MARK: - UTType Extension
extension UTType {
    static var exe: UTType {
        UTType(filenameExtension: "exe") ?? .data
    }
}

/// Grid-based shortcuts view with auto-sorting and file drop support
struct ShortcutsGridView: View {
    @ObservedObject var workspace: Workspace
    @State private var shortcuts: [DesktopIcon] = []
    @State private var showAddProgram = false

    private let gridLayout = [GridItem(.adaptive(minimum: 100, maximum: .infinity))]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVGrid(columns: gridLayout, alignment: .center, spacing: 20) {
                    ForEach(shortcuts) { shortcut in
                        ShortcutView(shortcut: shortcut, workspace: workspace)
                    }
                }
                .padding()
            }
            .background(desktopBackground)

            // + button (bottom-right)
            Button(action: { showAddProgram = true }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .padding(20)
            .sheet(isPresented: $showAddProgram) {
                AddProgramView(workspace: workspace)
            }
        }
        .onAppear { loadShortcuts() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleFileDrop(providers)
        }
    }

    // MARK: - Background
    private var desktopBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.2, green: 0.4, blue: 0.7),
                Color(red: 0.1, green: 0.3, blue: 0.6)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Actions
    private func loadShortcuts() {
        Logger.sojuKit.logWithFile("Loading shortcuts for workspace: \(workspace.settings.name)", level: .info)

        // Load from workspace.settings.pinnedPrograms and sort alphabetically
        shortcuts = workspace.settings.pinnedPrograms.map { program in
            DesktopIcon(
                id: program.id,
                name: program.name,
                url: program.url ?? workspace.winePrefixURL,
                iconImage: "app.fill"
            )
        }.sorted()

        Logger.sojuKit.logWithFile("Loaded \(shortcuts.count) shortcuts", level: .debug)
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        Logger.sojuKit.logWithFile("File drop detected (\(providers.count) items)", level: .info)

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                if let error = error {
                    Logger.sojuKit.logWithFile("Failed to load dropped file: \(error.localizedDescription)", level: .error)
                    return
                }

                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    Logger.sojuKit.logWithFile("Invalid file drop data", level: .warning)
                    return
                }

                // Only execute .exe files
                if url.pathExtension.lowercased() == "exe" {
                    Logger.sojuKit.logWithFile("Executing dropped .exe file: \(url.lastPathComponent)", level: .info)

                    let program = Program(
                        name: url.deletingPathExtension().lastPathComponent,
                        url: url
                    )

                    Task {
                        do {
                            try await program.run(in: workspace)
                        } catch {
                            Logger.sojuKit.logWithFile("Failed to run dropped program: \(error.localizedDescription)", level: .error)
                        }
                    }
                } else {
                    Logger.sojuKit.logWithFile("Dropped file is not an .exe, ignoring: \(url.pathExtension)", level: .debug)
                }
            }
        }

        return true
    }
}

#Preview {
    ShortcutsGridView(workspace: Workspace.preview)
}
