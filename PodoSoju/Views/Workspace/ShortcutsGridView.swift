//
//  ShortcutsGridView.swift
//  PodoSoju
//
//  Created on 2026-01-08.
//

import SwiftUI
import PodoSojuKit
import os.log
import UniformTypeIdentifiers

/// Grid-based shortcuts view with auto-sorting and file drop support
struct ShortcutsGridView: View {
    @ObservedObject var workspace: Workspace
    @State private var shortcuts: [DesktopIcon] = []
    @State private var showAddProgram = false

    /// Timer for periodic cleanup of stale running program entries
    private let cleanupTimer = Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()

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
            .sheet(isPresented: $showAddProgram, onDismiss: {
                // Reload shortcuts when AddProgramView is dismissed
                Logger.sojuKit.debug("AddProgramView dismissed, reloading shortcuts", category: "UI")
                loadShortcuts()
            }) {
                AddProgramView(workspace: workspace)
            }
        }
        .onAppear { loadShortcuts() }
        .onChange(of: workspace.settings.pinnedPrograms) { _, _ in
            // Reload when pinnedPrograms changes
            Logger.sojuKit.debug("pinnedPrograms changed, reloading shortcuts", category: "UI")
            loadShortcuts()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleFileDrop(providers)
        }
        .onReceive(cleanupTimer) { _ in
            // Periodically clean up stale running program entries
            workspace.cleanupStaleRunningPrograms()
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

        Task {
            // 1. Scan .lnk files from Desktop folders
            let discoveredShortcuts = await scanDesktopFolders()
            Logger.sojuKit.debug("Found \(discoveredShortcuts.count) shortcuts from Desktop folders", category: "UI")

            // 2. Convert pinnedPrograms to DesktopIcon (with icon extraction)
            let pinnedIcons = workspace.settings.pinnedPrograms.compactMap { pinned -> DesktopIcon? in
                guard let url = pinned.url else {
                    Logger.sojuKit.warning("Skipping pinned program '\(pinned.name)' - no URL", category: "UI")
                    return nil
                }
                Logger.sojuKit.debug("Adding pinned program: \(pinned.name) -> \(url.path)", category: "UI")
                return DesktopIcon(
                    id: pinned.id,
                    name: pinned.name,
                    url: url,
                    iconImage: iconForProgram(name: pinned.name)
                )
            }
            Logger.sojuKit.debug("Found \(pinnedIcons.count) pinned programs", category: "UI")

            // 3. Merge and deduplicate (pinned programs take priority)
            var seenURLs = Set<String>()
            var mergedShortcuts: [DesktopIcon] = []

            // Add pinned programs first (they take priority)
            for icon in pinnedIcons {
                let urlKey = icon.url.path.lowercased()
                if !seenURLs.contains(urlKey) {
                    seenURLs.insert(urlKey)
                    mergedShortcuts.append(icon)
                }
            }

            // Add discovered shortcuts (skip duplicates)
            for icon in discoveredShortcuts {
                let urlKey = icon.url.path.lowercased()
                if !seenURLs.contains(urlKey) {
                    seenURLs.insert(urlKey)
                    mergedShortcuts.append(icon)
                }
            }

            await MainActor.run {
                shortcuts = mergedShortcuts.sorted()
                Logger.sojuKit.info("Total shortcuts loaded: \(shortcuts.count) (pinned: \(pinnedIcons.count), discovered: \(discoveredShortcuts.count))", category: "UI")
            }
        }
    }

    /// Scans Desktop folders for .lnk files
    private func scanDesktopFolders() async -> [DesktopIcon] {
        let prefixURL = workspace.winePrefixURL
        let fileManager = FileManager.default

        // Desktop paths to scan (relative to drive_c)
        let desktopPaths = [
            "users/Public/Desktop",
            "ProgramData/Microsoft/Windows/Start Menu/Programs"
        ]

        // Also scan per-user Desktop folders
        let usersDir = prefixURL.appendingPathComponent("users")
        var allPaths = desktopPaths

        if let userDirs = try? fileManager.contentsOfDirectory(at: usersDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for userDir in userDirs {
                let username = userDir.lastPathComponent
                // Skip Public (already added) and system folders
                if username != "Public" && username != "crossover" {
                    allPaths.append("users/\(username)/Desktop")
                }
            }
        }

        var icons: [DesktopIcon] = []
        var seenNames = Set<String>()

        for relativePath in allPaths {
            let directoryURL = prefixURL.appendingPathComponent(relativePath)

            guard fileManager.fileExists(atPath: directoryURL.path) else {
                continue
            }

            let lnkFiles = scanForLnkFiles(in: directoryURL, maxDepth: 3)

            for lnkURL in lnkFiles {
                let name = lnkURL.deletingPathExtension().lastPathComponent

                // Skip duplicates, uninstallers, and Wine stubs
                guard !seenNames.contains(name.lowercased()) else { continue }
                guard !isUninstaller(name) else { continue }
                guard !InstallerDetector.isWineStub(lnkURL) else { continue }

                seenNames.insert(name.lowercased())

                let icon = DesktopIcon(
                    name: name,
                    url: lnkURL,
                    iconImage: iconForProgram(name: name)
                )
                icons.append(icon)
            }
        }

        return icons
    }

    /// Recursively scans directory for .lnk files
    private func scanForLnkFiles(in directory: URL, maxDepth: Int, currentDepth: Int = 0) -> [URL] {
        guard currentDepth <= maxDepth else { return [] }

        let fileManager = FileManager.default
        var results: [URL] = []

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for url in contents {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else {
                continue
            }

            if resourceValues.isRegularFile == true {
                if url.pathExtension.lowercased() == "lnk" {
                    results.append(url)
                }
            } else if resourceValues.isDirectory == true, currentDepth < maxDepth {
                let subResults = scanForLnkFiles(in: url, maxDepth: maxDepth, currentDepth: currentDepth + 1)
                results.append(contentsOf: subResults)
            }
        }

        return results
    }

    /// Checks if a shortcut name indicates an uninstaller
    private func isUninstaller(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased.contains("uninstall") ||
               lowercased.contains("삭제") ||
               lowercased.contains("제거")
    }

    /// Returns appropriate SF Symbol icon based on program name
    private func iconForProgram(name: String) -> String {
        let lowercaseName = name.lowercased()

        if lowercaseName.contains("game") || lowercaseName.contains("play") || lowercaseName.contains("게임") {
            return "gamecontroller.fill"
        } else if lowercaseName.contains("install") || lowercaseName.contains("setup") || lowercaseName.contains("설치") {
            return "arrow.down.circle.fill"
        } else if lowercaseName.contains("uninstall") || lowercaseName.contains("삭제") || lowercaseName.contains("제거") {
            return "trash.fill"
        } else if lowercaseName.contains("notepad") || lowercaseName.contains("edit") || lowercaseName.contains("메모") {
            return "doc.text.fill"
        } else if lowercaseName.contains("media") || lowercaseName.contains("player") || lowercaseName.contains("music") || lowercaseName.contains("접속기") {
            return "play.circle.fill"
        } else if lowercaseName.contains("browser") || lowercaseName.contains("chrome") || lowercaseName.contains("firefox") {
            return "globe"
        } else if lowercaseName.contains("넷파일") || lowercaseName.contains("net") {
            return "network"
        }

        return "app.fill"
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

                    Task { @MainActor in
                        // Create program and run
                        // Note: Program.run() handles duplicate detection, registration/unregistration internally
                        let program = Program(
                            name: url.deletingPathExtension().lastPathComponent,
                            url: url
                        )

                        do {
                            try await program.run(in: self.workspace)
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
