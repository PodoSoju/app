//
//  DesktopView.swift
//  Soju
//
//  Created on 2026-01-07.
//

import SwiftUI
import SojuKit
import os.log

/// Main desktop view mimicking Windows desktop UX
struct DesktopView: View {
    @ObservedObject var workspace: Workspace
    @State private var icons: [DesktopIcon] = []
    @State private var selectedIconId: UUID?
    @State private var backgroundImage: String = "DefaultBackground"

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Background
                desktopBackground
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()

                // Desktop Icons Grid
                ForEach(icons) { icon in
                    DesktopIconView(
                        icon: icon,
                        isSelected: selectedIconId == icon.id,
                        onTap: {
                            handleIconTap(icon)
                        },
                        onDoubleTap: {
                            handleIconDoubleTap(icon)
                        },
                        onPositionChanged: { newPosition in
                            handleIconPositionChanged(icon, newPosition: newPosition)
                        }
                    )
                }

                // Program Status View (bottom-right corner)
                // TODO: Add ProgramStatusView to Xcode project
                // VStack {
                //     Spacer()
                //     HStack {
                //         Spacer()
                //         ProgramStatusView(workspace: workspace)
                //             .frame(width: 400)
                //             .padding()
                //     }
                // }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
            .onTapGesture {
                // Deselect when clicking on empty space
                selectedIconId = nil
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadWorkspaceIcons()
        }
    }

    // MARK: - Background
    private var desktopBackground: some View {
        Group {
            // Try to load custom background, fallback to gradient
            if let nsImage = NSImage(named: backgroundImage) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Default gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.2, green: 0.4, blue: 0.7),
                        Color(red: 0.1, green: 0.3, blue: 0.6)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    // MARK: - Actions
    private func loadWorkspaceIcons() {
        // Load icons from workspace's drive_c
        var loadedIcons: [DesktopIcon] = []

        // Desktop folder
        let desktopPath = workspace.winePrefixURL
            .appending(path: "users")
            .appending(path: "crossover")
            .appending(path: "Desktop")

        // My Computer
        let myComputerIcon = DesktopIcon(
            name: workspace.settings.name,
            url: workspace.winePrefixURL,
            position: loadSavedPosition(for: "mycomputer") ?? CGPoint(x: 20, y: 20),
            iconImage: workspace.settings.icon
        )
        loadedIcons.append(myComputerIcon)

        // Desktop folder
        if FileManager.default.fileExists(atPath: desktopPath.path(percentEncoded: false)) {
            let desktopIcon = DesktopIcon(
                name: "Desktop",
                url: desktopPath,
                position: loadSavedPosition(for: "desktop") ?? CGPoint(x: 20, y: 120),
                iconImage: "folder.fill"
            )
            loadedIcons.append(desktopIcon)
        }

        // Documents
        let documentsPath = workspace.winePrefixURL
            .appending(path: "users")
            .appending(path: "crossover")
            .appending(path: "Documents")

        if FileManager.default.fileExists(atPath: documentsPath.path(percentEncoded: false)) {
            let documentsIcon = DesktopIcon(
                name: "Documents",
                url: documentsPath,
                position: loadSavedPosition(for: "documents") ?? CGPoint(x: 20, y: 220),
                iconImage: "doc.fill"
            )
            loadedIcons.append(documentsIcon)
        }

        icons = loadedIcons
    }

    private func handleIconTap(_ icon: DesktopIcon) {
        selectedIconId = icon.id
    }

    private func handleIconDoubleTap(_ icon: DesktopIcon) {
        Logger.sojuKit.logWithFile("Opening icon: \(icon.name) at \(icon.url.path)", level: .info)

        // Check if it's a Windows executable
        if icon.url.pathExtension.lowercased() == "exe" {
            // Create and run program
            let program = Program(
                name: icon.name,
                url: icon.url,
                icon: icon.iconImage == "app" ? nil : NSImage(systemSymbolName: icon.iconImage, accessibilityDescription: nil)
            )

            Task {
                do {
                    Logger.sojuKit.logWithFile("Starting program: \(icon.name)", level: .info)
                    // Add to workspace's running programs
                    await MainActor.run {
                        workspace.programs.append(program)
                    }

                    // Execute the program
                    try await program.run(in: workspace)

                    Logger.sojuKit.logWithFile("Program \(icon.name) completed successfully", level: .info)
                } catch {
                    Logger.sojuKit.logWithFile("Failed to run program \(icon.name): \(error)", level: .error)

                    // Remove from running programs on error
                    await MainActor.run {
                        workspace.programs.removeAll { $0.id == program.id }
                    }
                }
            }
        } else {
            // Open folders and other files with Finder
            Logger.sojuKit.logWithFile("Opening \(icon.name) with Finder", level: .debug)
            NSWorkspace.shared.open(icon.url)
        }
    }

    private func handleIconPositionChanged(_ icon: DesktopIcon, newPosition: CGPoint) {
        // Update icon position in array
        if let index = icons.firstIndex(where: { $0.id == icon.id }) {
            var updatedIcon = icons[index]
            updatedIcon.position = newPosition
            icons[index] = updatedIcon

            // Save position to UserDefaults using stable identifier
            let identifier = getIconIdentifier(icon)
            let key = "icon_\(identifier)_position"
            let positionData = ["x": newPosition.x, "y": newPosition.y]
            UserDefaults.standard.set(positionData, forKey: key)

            Logger.sojuKit.logWithFile("Icon \(icon.name) moved to: \(newPosition)", level: .debug)
        }
    }

    private func getIconIdentifier(_ icon: DesktopIcon) -> String {
        // Use stable identifier based on URL path
        let pathComponents = icon.url.pathComponents
        if pathComponents.contains("Desktop") {
            return "desktop"
        } else if pathComponents.contains("Documents") {
            return "documents"
        } else if icon.url == workspace.winePrefixURL {
            return "mycomputer"
        } else {
            // For executables or custom icons, use name
            return icon.name.lowercased().replacingOccurrences(of: " ", with: "_")
        }
    }

    private func handleDroppedExecutables(_ urls: [URL], in size: CGSize) -> Bool {
        Logger.sojuKit.logWithFile("Dropped \(urls.count) executables onto desktop", level: .info)
        var newIcons: [DesktopIcon] = []

        // Calculate next available position
        let startX: CGFloat = 120
        var currentY: CGFloat = 20

        // Find the maximum Y position used
        if let maxY = icons.map({ $0.position.y }).max() {
            currentY = maxY + 100
        }

        for url in urls {
            Logger.sojuKit.logWithFile("Adding executable to desktop: \(url.lastPathComponent)", level: .debug)
            // Create Program and add to workspace
            let program = Program(
                name: url.deletingPathExtension().lastPathComponent,
                url: url
            )
            workspace.programs.append(program)

            // Create desktop icon
            let icon = DesktopIcon(
                name: program.name,
                url: url,
                position: CGPoint(x: startX, y: currentY),
                iconImage: "app.fill"
            )
            newIcons.append(icon)
            currentY += 100
        }

        // Add new icons to the list
        icons.append(contentsOf: newIcons)

        return true
    }

    private func loadSavedPosition(for iconName: String) -> CGPoint? {
        let key = "icon_\(iconName)_position"
        guard let positionData = UserDefaults.standard.dictionary(forKey: key),
              let x = positionData["x"] as? CGFloat,
              let y = positionData["y"] as? CGFloat else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }
}
