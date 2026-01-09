//
//  DesktopIcon.swift
//  Soju
//
//  Created on 2026-01-07.
//

import Foundation
import SwiftUI

/// Represents an icon on the desktop (grid-based layout, no free positioning)
struct DesktopIcon: Identifiable, Hashable, Comparable {
    let id: UUID
    let name: String
    let url: URL
    let iconImage: String // SF Symbol name

    init(id: UUID = UUID(), name: String, url: URL, iconImage: String = "app.fill") {
        self.id = id
        self.name = name
        self.url = url
        self.iconImage = iconImage
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DesktopIcon, rhs: DesktopIcon) -> Bool {
        lhs.id == rhs.id
    }

    // Comparable conformance - case-insensitive name sorting
    static func < (lhs: DesktopIcon, rhs: DesktopIcon) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

// MARK: - Sample Data
extension DesktopIcon {
    static let sampleIcons: [DesktopIcon] = [
        DesktopIcon(
            name: "Documents",
            url: URL(fileURLWithPath: "/Users/Documents"),
            iconImage: "folder.fill"
        ),
        DesktopIcon(
            name: "Downloads",
            url: URL(fileURLWithPath: "/Users/Downloads"),
            iconImage: "arrow.down.circle.fill"
        ),
        DesktopIcon(
            name: "Applications",
            url: URL(fileURLWithPath: "/Applications"),
            iconImage: "square.grid.2x2.fill"
        ),
        DesktopIcon(
            name: "Desktop",
            url: URL(fileURLWithPath: "/Users/Desktop"),
            iconImage: "desktopcomputer"
        )
    ]
}
