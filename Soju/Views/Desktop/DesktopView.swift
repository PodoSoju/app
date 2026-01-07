//
//  DesktopView.swift
//  Soju
//
//  Created on 2026-01-07.
//

import SwiftUI
import SojuKit

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
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onTapGesture {
                // Deselect when clicking on empty space
                selectedIconId = nil
            }
        }
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
        loadedIcons.append(DesktopIcon(
            name: workspace.settings.name,
            url: workspace.winePrefixURL,
            position: CGPoint(x: 20, y: 20),
            iconImage: workspace.settings.icon
        ))

        // Desktop folder
        if FileManager.default.fileExists(atPath: desktopPath.path(percentEncoded: false)) {
            loadedIcons.append(DesktopIcon(
                name: "Desktop",
                url: desktopPath,
                position: CGPoint(x: 20, y: 120),
                iconImage: "folder.fill"
            ))
        }

        // Documents
        let documentsPath = workspace.winePrefixURL
            .appending(path: "users")
            .appending(path: "crossover")
            .appending(path: "Documents")

        if FileManager.default.fileExists(atPath: documentsPath.path(percentEncoded: false)) {
            loadedIcons.append(DesktopIcon(
                name: "Documents",
                url: documentsPath,
                position: CGPoint(x: 20, y: 220),
                iconImage: "doc.fill"
            ))
        }

        icons = loadedIcons
    }

    private func handleIconTap(_ icon: DesktopIcon) {
        selectedIconId = icon.id
    }

    private func handleIconDoubleTap(_ icon: DesktopIcon) {
        print("Opening: \(icon.name) at \(icon.url.path)")

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
                    // Add to workspace's running programs
                    await MainActor.run {
                        workspace.programs.append(program)
                    }

                    // Execute the program
                    try await program.run(in: workspace)

                    print("Program \(icon.name) completed")
                } catch {
                    print("Failed to run program \(icon.name): \(error)")

                    // Remove from running programs on error
                    await MainActor.run {
                        workspace.programs.removeAll { $0.id == program.id }
                    }
                }
            }
        } else {
            // Open folders and other files with Finder
            NSWorkspace.shared.open(icon.url)
        }
    }

    private func handleIconPositionChanged(_ icon: DesktopIcon, newPosition: CGPoint) {
        // Update icon position in array
        if let index = icons.firstIndex(where: { $0.id == icon.id }) {
            icons[index].position = newPosition
        }

        // Save position to UserDefaults
        let key = "icon_\(icon.name)_position"
        let positionData = ["x": newPosition.x, "y": newPosition.y]
        UserDefaults.standard.set(positionData, forKey: key)
    }

    private func handleDroppedExecutables(_ urls: [URL], in size: CGSize) -> Bool {
        var newIcons: [DesktopIcon] = []

        // Calculate next available position
        let startX: CGFloat = 120
        var currentY: CGFloat = 20

        // Find the maximum Y position used
        if let maxY = icons.map({ $0.position.y }).max() {
            currentY = maxY + 100
        }

        for url in urls {
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
