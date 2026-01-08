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
        Logger.sojuKit.info("Loading shortcuts for workspace: \(workspace.settings.name)", category: "UI")

        // Load from workspace.settings.pinnedPrograms and sort alphabetically
        shortcuts = workspace.settings.pinnedPrograms.map { program in
            DesktopIcon(
                id: program.id,
                name: program.name,
                url: program.url ?? workspace.winePrefixURL,
                iconImage: "app.fill"
            )
        }.sorted()

        Logger.sojuKit.debug("Loaded \(shortcuts.count) shortcuts", category: "UI")
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        Logger.sojuKit.info("File drop detected (\(providers.count) items)", category: "UI")

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                if let error = error {
                    Logger.sojuKit.error("Failed to load dropped file: \(error.localizedDescription)", category: "UI")
                    return
                }

                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    Logger.sojuKit.warning("Invalid file drop data", category: "UI")
                    return
                }

                // Only execute .exe files
                if url.pathExtension.lowercased() == "exe" {
                    Logger.sojuKit.info("Executing dropped .exe file: \(url.lastPathComponent)", category: "UI")

                    let program = Program(
                        name: url.deletingPathExtension().lastPathComponent,
                        url: url
                    )

                    Task { @MainActor in
                        do {
                            try await program.run(in: workspace)
                        } catch {
                            Logger.sojuKit.error("Failed to run dropped program: \(error.localizedDescription)", category: "UI")
                        }
                    }
                } else {
                    Logger.sojuKit.debug("Dropped file is not an .exe, ignoring: \(url.pathExtension)", category: "UI")
                }
            }
        }

        return true
    }
}

#Preview {
    ShortcutsGridView(workspace: Workspace.preview)
}
