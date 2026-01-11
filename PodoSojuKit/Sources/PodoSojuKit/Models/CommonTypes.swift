//
//  CommonTypes.swift
//  PodoSojuKit
//
//  Created on 2026-01-07.
//

import Foundation

// MARK: - Windows Version

public enum WinVersion: String, CaseIterable, Codable, Sendable {
    case winXP = "winxp64"
    case win7 = "win7"
    case win8 = "win8"
    case win81 = "win81"
    case win10 = "win10"
    case win11 = "win11"

    public func pretty() -> String {
        switch self {
        case .winXP: return "Windows XP"
        case .win7: return "Windows 7"
        case .win8: return "Windows 8"
        case .win81: return "Windows 8.1"
        case .win10: return "Windows 10"
        case .win11: return "Windows 11"
        }
    }
}

// MARK: - Enhanced Sync

public enum EnhancedSync: String, Codable, Equatable {
    case none
    case esync
    case msync
}

// MARK: - DXVK HUD

public enum DXVKHUD: String, Codable, Equatable {
    case full
    case partial
    case fps
    case off
}

// MARK: - Pinned Program

public struct PinnedProgram: Codable, Hashable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var url: URL?

    public init(id: UUID = UUID(), name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.url = try container.decodeIfPresent(URL.self, forKey: .url)
    }
}
