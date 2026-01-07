//
//  DesktopIcon.swift
//  Soju
//
//  Created on 2026-01-07.
//

import Foundation
import SwiftUI

/// Represents an icon on the desktop
struct DesktopIcon: Identifiable, Hashable {
    let id: UUID
    let name: String
    let url: URL
    var position: CGPoint
    let iconImage: String // SF Symbol name or custom image name

    init(id: UUID = UUID(), name: String, url: URL, position: CGPoint, iconImage: String = "app") {
        self.id = id
        self.name = name
        self.url = url
        self.position = position
        self.iconImage = iconImage
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DesktopIcon, rhs: DesktopIcon) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Sample Data
extension DesktopIcon {
    static let sampleIcons: [DesktopIcon] = [
        DesktopIcon(
            name: "Documents",
            url: URL(fileURLWithPath: "/Users/Documents"),
            position: CGPoint(x: 20, y: 20),
            iconImage: "folder.fill"
        ),
        DesktopIcon(
            name: "Downloads",
            url: URL(fileURLWithPath: "/Users/Downloads"),
            position: CGPoint(x: 20, y: 120),
            iconImage: "arrow.down.circle.fill"
        ),
        DesktopIcon(
            name: "Applications",
            url: URL(fileURLWithPath: "/Applications"),
            position: CGPoint(x: 20, y: 220),
            iconImage: "square.grid.2x2.fill"
        ),
        DesktopIcon(
            name: "Desktop",
            url: URL(fileURLWithPath: "/Users/Desktop"),
            position: CGPoint(x: 20, y: 320),
            iconImage: "desktopcomputer"
        )
    ]
}
