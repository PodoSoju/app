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
    var onHome: (() -> Void)? = nil

    @State private var shortcuts: [DesktopIcon] = []
    @State private var showAddProgram = false
    @State private var showWorkspaceSettings = false
    @State private var desktopWatcher = DesktopWatcher()

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

            // Bottom-right buttons (home, settings, +)
            HStack(spacing: 12) {
                // Home button (워크스페이스 선택 화면으로)
                if let onHome = onHome {
                    Button(action: onHome) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }

                // Settings button (워크스페이스 설정)
                Button(action: {
                    Logger.podoSojuKit.info("Settings button clicked for: \(workspace.settings.name)")
                    showWorkspaceSettings = true
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)

                // + button
                Button(action: { showAddProgram = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .onAppear {
            loadShortcuts()
            desktopWatcher.startWatching(prefixURL: workspace.winePrefixURL)
        }
        .onDisappear {
            desktopWatcher.stopWatching()
        }
        .onChange(of: workspace.settings.pinnedPrograms) { _, _ in
            // Reload when pinnedPrograms changes
            Logger.podoSojuKit.debug("pinnedPrograms changed, reloading shortcuts", category: "UI")
            loadShortcuts()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleFileDrop(providers)
        }
        // FIXME: Disabled due to recursive lock crash - fix hasRunningWineProcesses thread safety
        // .onReceive(cleanupTimer) { _ in
        //     workspace.cleanupStaleRunningPrograms()
        // }
        .onReceive(desktopWatcher.desktopChanged) { _ in
            // Reload shortcuts when desktop contents change
            Logger.podoSojuKit.debug("Desktop changed, reloading shortcuts", category: "UI")
            loadShortcuts()
        }
        .navigationTitle(workspace.settings.name)
        .sheet(isPresented: $showWorkspaceSettings) {
            WorkspaceSettingsView(workspace: workspace)
        }
        .sheet(isPresented: $showAddProgram, onDismiss: {
            Logger.podoSojuKit.debug("AddProgramView dismissed, reloading shortcuts", category: "UI")
            loadShortcuts()
        }) {
            AddProgramView(workspace: workspace)
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
        Logger.podoSojuKit.info("Loading shortcuts for workspace: \(workspace.settings.name)", category: "UI")

        Task {
            // 1. Scan .lnk files from Desktop folders
            let discoveredShortcuts = await scanDesktopFolders()
            Logger.podoSojuKit.debug("Found \(discoveredShortcuts.count) shortcuts from Desktop folders", category: "UI")

            // 2. Convert pinnedPrograms to DesktopIcon (with icon lookup/extraction)
            var pinnedIcons: [DesktopIcon] = []
            for pinned in workspace.settings.pinnedPrograms {
                guard let url = pinned.url else {
                    Logger.podoSojuKit.warning("Skipping pinned program '\(pinned.name)' - no URL", category: "UI")
                    continue
                }
                Logger.podoSojuKit.debug("Adding pinned program: \(pinned.name) -> \(url.path)", category: "UI")

                // Check for existing icon, extract if missing
                var iconURL = IconManager.shared.getIconURL(for: url, in: workspace.url)
                if iconURL == nil {
                    iconURL = await IconManager.shared.extractIcon(from: url, in: workspace.url)
                }

                pinnedIcons.append(DesktopIcon(
                    id: pinned.id,
                    name: pinned.name,
                    url: url,
                    iconImage: iconForProgram(name: pinned.name),
                    iconURL: iconURL
                ))
            }
            Logger.podoSojuKit.debug("Found \(pinnedIcons.count) pinned programs", category: "UI")

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
                Logger.podoSojuKit.info("Total shortcuts loaded: \(shortcuts.count) (pinned: \(pinnedIcons.count), discovered: \(discoveredShortcuts.count))", category: "UI")
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

        // First pass: collect all files and prioritize .app over .lnk
        var allFiles: [URL] = []
        for relativePath in allPaths {
            let directoryURL = prefixURL.appendingPathComponent(relativePath)

            // Skip if doesn't exist or is a symlink (avoid following to macOS folders)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
                continue
            }

            // Check if it's a symlink - skip to avoid accessing macOS folders
            if let attrs = try? fileManager.attributesOfItem(atPath: directoryURL.path),
               let fileType = attrs[.type] as? FileAttributeType,
               fileType == .typeSymbolicLink {
                Logger.podoSojuKit.debug("Skipping symlink: \(relativePath)", category: "UI")
                continue
            }

            allFiles.append(contentsOf: scanForLnkFiles(in: directoryURL, maxDepth: 3))
        }

        // Sort: .app files first (they take priority over .lnk with same name)
        let sortedFiles = allFiles.sorted { url1, url2 in
            let isApp1 = url1.pathExtension.lowercased() == "app"
            let isApp2 = url2.pathExtension.lowercased() == "app"
            if isApp1 && !isApp2 { return true }
            if !isApp1 && isApp2 { return false }
            return url1.lastPathComponent < url2.lastPathComponent
        }

        for fileURL in sortedFiles {
            let name = fileURL.deletingPathExtension().lastPathComponent
            let ext = fileURL.pathExtension.lowercased()

            // Skip duplicates, uninstallers, and Wine stubs
            guard !seenNames.contains(name.lowercased()) else { continue }
            guard !isUninstaller(name) else { continue }

            // For .lnk files, also check Wine stubs
            if ext == "lnk" {
                guard !InstallerDetector.isWineStub(fileURL) else { continue }
            }

            seenNames.insert(name.lowercased())

            // Get icon - for .app, use the app's icon; for .lnk, extract from exe
            var iconURL: URL? = nil
            if ext == "app" {
                // PodoJuice app - icon is in Resources/AppIcon.icns
                let appIconURL = fileURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
                if fileManager.fileExists(atPath: appIconURL.path) {
                    iconURL = appIconURL
                }
            } else {
                iconURL = IconManager.shared.getIconURL(for: fileURL, in: workspace.url)
                if iconURL == nil {
                    iconURL = await IconManager.shared.extractIcon(from: fileURL, in: workspace.url)
                }
            }

            let icon = DesktopIcon(
                name: name,
                url: fileURL,
                iconImage: ext == "app" ? "drop.fill" : iconForProgram(name: name),
                iconURL: iconURL
            )
            icons.append(icon)
        }

        return icons
    }

    /// Recursively scans directory for .lnk files and .app bundles (PodoJuice)
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

            let ext = url.pathExtension.lowercased()

            if resourceValues.isRegularFile == true {
                // Include .lnk shortcuts
                if ext == "lnk" {
                    results.append(url)
                }
            } else if resourceValues.isDirectory == true {
                // Include .app bundles (PodoJuice) - don't recurse into them
                if ext == "app" {
                    results.append(url)
                } else if currentDepth < maxDepth {
                    // Recurse into regular directories
                    let subResults = scanForLnkFiles(in: url, maxDepth: maxDepth, currentDepth: currentDepth + 1)
                    results.append(contentsOf: subResults)
                }
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
        Logger.podoSojuKit.info("File drop detected (\(providers.count) items)", category: "UI")

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                if let error = error {
                    Logger.podoSojuKit.error("Failed to load dropped file: \(error.localizedDescription)", category: "UI")
                    return
                }

                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    Logger.podoSojuKit.warning("Invalid file drop data", category: "UI")
                    return
                }

                // Only execute .exe files
                if url.pathExtension.lowercased() == "exe" {
                    Logger.podoSojuKit.info("Executing dropped .exe file: \(url.lastPathComponent)", category: "UI")

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
                            Logger.podoSojuKit.error("Failed to run dropped program: \(error.localizedDescription)", category: "UI")
                        }
                    }
                } else {
                    Logger.podoSojuKit.debug("Dropped file is not an .exe, ignoring: \(url.pathExtension)", category: "UI")
                }
            }
        }

        return true
    }
}

#Preview {
    ShortcutsGridView(workspace: Workspace.preview)
}
