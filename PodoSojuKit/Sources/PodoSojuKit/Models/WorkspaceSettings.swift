//
//  WorkspaceSettings.swift
//  PodoSojuKit
//
//  Created on 2026-01-07.
//

import Foundation
import SemanticVersion
import os.log

// MARK: - Workspace Info

public struct WorkspaceInfo: Codable, Equatable {
    var name: String = "My PC"
    var icon: String = "desktopcomputer"  // SF Symbol name
    var pinnedPrograms: [PinnedProgram] = []
    var programOrder: [UUID] = []  // Custom ordering for grid-based layout

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "My PC"
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "desktopcomputer"
        self.pinnedPrograms = try container.decodeIfPresent([PinnedProgram].self, forKey: .pinnedPrograms) ?? []
        self.programOrder = try container.decodeIfPresent([UUID].self, forKey: .programOrder) ?? []
    }
}

// MARK: - Wine Configuration

public struct WorkspaceWineConfig: Codable, Equatable {
    static let defaultWineVersion = SemanticVersion(11, 0, 0)
    var wineVersion: SemanticVersion = Self.defaultWineVersion
    var windowsVersion: WinVersion = .win10
    var enhancedSync: EnhancedSync = .msync
    var avxEnabled: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.wineVersion = try container.decodeIfPresent(SemanticVersion.self, forKey: .wineVersion) ?? Self.defaultWineVersion
        self.windowsVersion = try container.decodeIfPresent(WinVersion.self, forKey: .windowsVersion) ?? .win10
        self.enhancedSync = try container.decodeIfPresent(EnhancedSync.self, forKey: .enhancedSync) ?? .msync
        self.avxEnabled = try container.decodeIfPresent(Bool.self, forKey: .avxEnabled) ?? false
    }
}

// MARK: - Graphics Configuration

public struct WorkspaceGraphicsConfig: Codable, Equatable {
    var graphicsBackend: GraphicsBackend = .dxmt
    var metalHud: Bool = false
    var metalTrace: Bool = false
    var dxrEnabled: Bool = false
    var dxvk: Bool = false
    var dxvkAsync: Bool = true
    var dxvkHud: DXVKHUD = .off

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.graphicsBackend = try container.decodeIfPresent(GraphicsBackend.self, forKey: .graphicsBackend) ?? .dxmt
        self.metalHud = try container.decodeIfPresent(Bool.self, forKey: .metalHud) ?? false
        self.metalTrace = try container.decodeIfPresent(Bool.self, forKey: .metalTrace) ?? false
        self.dxrEnabled = try container.decodeIfPresent(Bool.self, forKey: .dxrEnabled) ?? false
        self.dxvk = try container.decodeIfPresent(Bool.self, forKey: .dxvk) ?? false
        self.dxvkAsync = try container.decodeIfPresent(Bool.self, forKey: .dxvkAsync) ?? true
        self.dxvkHud = try container.decodeIfPresent(DXVKHUD.self, forKey: .dxvkHud) ?? .off
    }
}

// MARK: - Workspace Settings

public struct WorkspaceSettings: Codable, Equatable {
    static let defaultFileVersion = SemanticVersion(1, 0, 0)

    var fileVersion: SemanticVersion = Self.defaultFileVersion
    private var info: WorkspaceInfo
    private var wineConfig: WorkspaceWineConfig
    private var graphicsConfig: WorkspaceGraphicsConfig

    public init() {
        self.info = WorkspaceInfo()
        self.wineConfig = WorkspaceWineConfig()
        self.graphicsConfig = WorkspaceGraphicsConfig()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fileVersion = try container.decodeIfPresent(SemanticVersion.self, forKey: .fileVersion) ?? Self.defaultFileVersion
        self.info = try container.decodeIfPresent(WorkspaceInfo.self, forKey: .info) ?? WorkspaceInfo()
        self.wineConfig = try container.decodeIfPresent(WorkspaceWineConfig.self, forKey: .wineConfig) ?? WorkspaceWineConfig()
        self.graphicsConfig = try container.decodeIfPresent(WorkspaceGraphicsConfig.self, forKey: .graphicsConfig) ?? WorkspaceGraphicsConfig()
    }

    // MARK: - Convenience Properties

    public var name: String {
        get { return info.name }
        set { info.name = newValue }
    }

    public var icon: String {
        get { return info.icon }
        set { info.icon = newValue }
    }

    public var pinnedPrograms: [PinnedProgram] {
        get { return info.pinnedPrograms }
        set { info.pinnedPrograms = newValue }
    }

    public var programOrder: [UUID] {
        get { return info.programOrder }
        set { info.programOrder = newValue }
    }

    public var wineVersion: SemanticVersion {
        get { return wineConfig.wineVersion }
        set { wineConfig.wineVersion = newValue }
    }

    public var windowsVersion: WinVersion {
        get { return wineConfig.windowsVersion }
        set { wineConfig.windowsVersion = newValue }
    }

    public var enhancedSync: EnhancedSync {
        get { return wineConfig.enhancedSync }
        set { wineConfig.enhancedSync = newValue }
    }

    public var avxEnabled: Bool {
        get { return wineConfig.avxEnabled }
        set { wineConfig.avxEnabled = newValue }
    }

    public var dxvk: Bool {
        get { return graphicsConfig.dxvk }
        set { graphicsConfig.dxvk = newValue }
    }

    public var dxvkAsync: Bool {
        get { return graphicsConfig.dxvkAsync }
        set { graphicsConfig.dxvkAsync = newValue }
    }

    public var dxvkHud: DXVKHUD {
        get { return graphicsConfig.dxvkHud }
        set { graphicsConfig.dxvkHud = newValue }
    }

    public var metalHud: Bool {
        get { return graphicsConfig.metalHud }
        set { graphicsConfig.metalHud = newValue }
    }

    public var metalTrace: Bool {
        get { return graphicsConfig.metalTrace }
        set { graphicsConfig.metalTrace = newValue }
    }

    public var dxrEnabled: Bool {
        get { return graphicsConfig.dxrEnabled }
        set { graphicsConfig.dxrEnabled = newValue }
    }

    public var graphicsBackend: GraphicsBackend {
        get { return graphicsConfig.graphicsBackend }
        set { graphicsConfig.graphicsBackend = newValue }
    }

    // MARK: - Encoding/Decoding

    /// Decode settings from metadata URL
    @discardableResult
    public static func decode(from metadataURL: URL) throws -> WorkspaceSettings {
        guard FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)) else {
            let settings = WorkspaceSettings()
            try settings.encode(to: metadataURL)
            return settings
        }

        let decoder = PropertyListDecoder()
        let data = try Data(contentsOf: metadataURL)
        var settings = try decoder.decode(WorkspaceSettings.self, from: data)

        guard settings.fileVersion == WorkspaceSettings.defaultFileVersion else {
            Logger.podoSojuKit.warning("Invalid file version `\(settings.fileVersion)`")
            settings = WorkspaceSettings()
            try settings.encode(to: metadataURL)
            return settings
        }

        return settings
    }

    /// Encode settings to metadata URL
    func encode(to metadataUrl: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(self)
        try data.write(to: metadataUrl)
    }

    // MARK: - Environment Variables

    /// Configure Wine environment variables based on settings
    public func environmentVariables(wineEnv: inout [String: String]) {
        // Graphics backend configuration
        switch graphicsConfig.graphicsBackend {
        case .dxmt:
            // DXMT is the default, no special configuration needed
            break

        case .dxvk:
            // DXVK - redirect DirectX DLLs to DXVK
            wineEnv.updateValue("dxgi,d3d9,d3d10core,d3d11=n,b", forKey: "WINEDLLOVERRIDES")

            // DXVK HUD configuration
            switch graphicsConfig.dxvkHud {
            case .full:
                wineEnv.updateValue("full", forKey: "DXVK_HUD")
            case .partial:
                wineEnv.updateValue("devinfo,fps,frametimes", forKey: "DXVK_HUD")
            case .fps:
                wineEnv.updateValue("fps", forKey: "DXVK_HUD")
            case .off:
                break
            }

            if graphicsConfig.dxvkAsync {
                wineEnv.updateValue("1", forKey: "DXVK_ASYNC")
            }

        case .d3dmetal:
            // D3DMetal - Apple Game Porting Toolkit
            // Uses D3DMetal.framework from GPTK
            wineEnv.updateValue("1", forKey: "D3DM_SUPPORT_DXR")
        }

        // Legacy DXVK flag support (for backwards compatibility)
        if graphicsConfig.dxvk && graphicsConfig.graphicsBackend != .dxvk {
            wineEnv.updateValue("dxgi,d3d9,d3d10core,d3d11=n,b", forKey: "WINEDLLOVERRIDES")
            switch graphicsConfig.dxvkHud {
            case .full:
                wineEnv.updateValue("full", forKey: "DXVK_HUD")
            case .partial:
                wineEnv.updateValue("devinfo,fps,frametimes", forKey: "DXVK_HUD")
            case .fps:
                wineEnv.updateValue("fps", forKey: "DXVK_HUD")
            case .off:
                break
            }
        }

        if graphicsConfig.dxvkAsync && graphicsConfig.graphicsBackend != .dxvk {
            wineEnv.updateValue("1", forKey: "DXVK_ASYNC")
        }

        // Enhanced sync configuration
        switch wineConfig.enhancedSync {
        case .none:
            break
        case .esync:
            wineEnv.updateValue("1", forKey: "WINEESYNC")
        case .msync:
            wineEnv.updateValue("1", forKey: "WINEMSYNC")
            wineEnv.updateValue("1", forKey: "WINEESYNC")
        }

        // Metal configuration
        if graphicsConfig.metalHud {
            wineEnv.updateValue("1", forKey: "MTL_HUD_ENABLED")
        }

        if graphicsConfig.metalTrace {
            wineEnv.updateValue("1", forKey: "METAL_CAPTURE_ENABLED")
        }

        // AVX configuration
        if wineConfig.avxEnabled {
            wineEnv.updateValue("1", forKey: "ROSETTA_ADVERTISE_AVX")
        }

        // DXR configuration (also enabled by D3DMetal backend)
        if graphicsConfig.dxrEnabled && graphicsConfig.graphicsBackend != .d3dmetal {
            wineEnv.updateValue("1", forKey: "D3DM_SUPPORT_DXR")
        }
    }
}
