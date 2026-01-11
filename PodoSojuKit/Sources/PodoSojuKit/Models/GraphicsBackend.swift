//
//  GraphicsBackend.swift
//  PodoSojuKit
//
//  Created on 2026-01-09.
//

import Foundation

// MARK: - Graphics Backend

/// DirectX 변환 그래픽 백엔드
public enum GraphicsBackend: String, CaseIterable, Codable, Sendable {
    /// DXMT - DirectX to Metal (DX10/11)
    /// PodoSoju/Wine 기본 제공
    case dxmt = "DXMT"

    /// DXVK - DirectX to Vulkan via MoltenVK (DX9~11)
    /// 레트로 게임, DX9 호환성 필요 시 사용
    case dxvk = "DXVK"

    /// D3DMetal - Apple Game Porting Toolkit (DX11/12)
    /// GPTK 설치 필요, 최신 게임용
    case d3dmetal = "D3DMetal"

    /// 사용자에게 표시할 이름
    public var displayName: String {
        switch self {
        case .dxmt:
            return "DXMT (Default)"
        case .dxvk:
            return "DXVK"
        case .d3dmetal:
            return "D3DMetal (GPTK)"
        }
    }

    /// 설명
    public var description: String {
        switch self {
        case .dxmt:
            return "DirectX 10/11 to Metal translation. Best compatibility for most games."
        case .dxvk:
            return "DirectX 9-11 via Vulkan/MoltenVK. Better for older/retro games."
        case .d3dmetal:
            return "Apple Game Porting Toolkit. Supports DX11/12, requires GPTK installation."
        }
    }

    /// 지원하는 DirectX 버전
    public var supportedDirectX: String {
        switch self {
        case .dxmt:
            return "DX10, DX11"
        case .dxvk:
            return "DX9, DX10, DX11"
        case .d3dmetal:
            return "DX11, DX12"
        }
    }

    /// GPTK 필요 여부
    public var requiresGPTK: Bool {
        return self == .d3dmetal
    }
}

// MARK: - GPTK Installation Status

/// Game Porting Toolkit 설치 상태
public enum GPTKInstallationStatus: Sendable {
    case notInstalled
    case installed(version: String?)
    case partiallyInstalled

    public var isInstalled: Bool {
        switch self {
        case .installed:
            return true
        case .notInstalled, .partiallyInstalled:
            return false
        }
    }
}
