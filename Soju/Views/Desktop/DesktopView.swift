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
                        }
                    )
                }
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
        NSWorkspace.shared.open(icon.url)
    }
}
