//
//  WorkspaceSettingsView.swift
//  PodoSoju
//
//  Created on 2026-01-10.
//

import SwiftUI
import PodoSojuKit
import os.log

struct WorkspaceSettingsView: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("General").tag(0)
                Text("Wine").tag(1)
                Text("Graphics").tag(2)
                Text("Winetricks").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case 0:
                    GeneralSettingsTab(workspace: workspace)
                case 1:
                    WineSettingsTab(workspace: workspace)
                case 2:
                    GraphicsSettingsTab(workspace: workspace)
                case 3:
                    WinetricksTab(workspace: workspace)
                default:
                    GeneralSettingsTab(workspace: workspace)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Done button
            HStack {
                Spacer()
                Button("Done") {
                    let currentSettings = workspace.settings
                    workspace.settings = currentSettings
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .padding()
            }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General Settings Tab
struct GeneralSettingsTab: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        Form {
            Section("Workspace Info") {
                TextField("Name", text: Binding(
                    get: { workspace.settings.name },
                    set: {
                        workspace.settings.name = $0
                        workspace.objectWillChange.send()
                    }
                ))

                Picker("Icon", selection: Binding(
                    get: { workspace.settings.icon },
                    set: {
                        workspace.settings.icon = $0
                        workspace.objectWillChange.send()
                    }
                )) {
                    Label("Desktop", systemImage: "desktopcomputer").tag("desktopcomputer")
                    Label("Laptop", systemImage: "laptopcomputer").tag("laptopcomputer")
                    Label("Server", systemImage: "server.rack").tag("server.rack")
                    Label("Display", systemImage: "display").tag("display")
                    Label("PC", systemImage: "pc").tag("pc")
                }
            }

            Section("Workspace ID") {
                Text(workspace.url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Wine Settings Tab
struct WineSettingsTab: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        Form {
            Section("Windows Compatibility") {
                Picker("Windows Version", selection: Binding(
                    get: { workspace.settings.windowsVersion },
                    set: { workspace.settings.windowsVersion = $0 }
                )) {
                    ForEach(WinVersion.allCases.reversed(), id: \.self) { version in
                        Text(version.pretty()).tag(version)
                    }
                }
            }

            Section("Performance") {
                Picker("Sync Mode", selection: Binding(
                    get: { workspace.settings.enhancedSync },
                    set: { workspace.settings.enhancedSync = $0 }
                )) {
                    Text("None").tag(EnhancedSync.none)
                    Text("ESync").tag(EnhancedSync.esync)
                    Text("MSync (Recommended)").tag(EnhancedSync.msync)
                }

                Toggle("Enable AVX (Rosetta)", isOn: Binding(
                    get: { workspace.settings.avxEnabled },
                    set: { workspace.settings.avxEnabled = $0 }
                ))
            }

            Section("Logging") {
                Picker("Wine Debug Level", selection: Binding(
                    get: { workspace.settings.wineDebugLevel },
                    set: { workspace.settings.wineDebugLevel = $0 }
                )) {
                    ForEach(WineDebugLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .help("Set WINEDEBUG level. Use 'All' when debugging crashes.")

                Text("Current: WINEDEBUG=\(workspace.settings.wineDebugLevel.wineDebugValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Graphics Settings Tab
struct GraphicsSettingsTab: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        Form {
            Section("Graphics Backend") {
                Picker("Backend", selection: Binding(
                    get: { workspace.settings.graphicsBackend },
                    set: { workspace.settings.graphicsBackend = $0 }
                )) {
                    Text("DXMT (Recommended)").tag(GraphicsBackend.dxmt)
                    Text("DXVK").tag(GraphicsBackend.dxvk)
                    Text("D3DMetal (GPTK)").tag(GraphicsBackend.d3dmetal)
                }
            }

            Section("Debug") {
                Toggle("Metal HUD", isOn: Binding(
                    get: { workspace.settings.metalHud },
                    set: { workspace.settings.metalHud = $0 }
                ))

                Toggle("DXR (Ray Tracing)", isOn: Binding(
                    get: { workspace.settings.dxrEnabled },
                    set: { workspace.settings.dxrEnabled = $0 }
                ))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Winetricks Tab

/// Installation status for individual component
enum InstallStatus: Equatable {
    case idle
    case downloading(percent: Int)
    case installing
    case success
    case failed(String)
}

struct WinetricksTab: View {
    @ObservedObject var workspace: Workspace

    /// Per-component install status
    @State private var componentStatuses: [String: InstallStatus] = [:]

    private let commonComponents = [
        ("vcrun2019", "Visual C++ 2015-2022"),
        ("vcrun2022", "Visual C++ 2022"),
        ("d3dx9", "DirectX 9"),
        ("d3dx10", "DirectX 10"),
        ("d3dx11_43", "DirectX 11"),
        ("dotnet48", ".NET Framework 4.8"),
        ("dotnet6", ".NET 6.0"),
        ("corefonts", "Core Fonts"),
        ("cjkfonts", "CJK Fonts (Korean/Japanese/Chinese)"),
    ]

    var body: some View {
        Form {
            Section("Common Components") {
                ForEach(commonComponents, id: \.0) { component in
                    WinetricksComponentRow(
                        componentId: component.0,
                        componentName: component.1,
                        status: componentStatuses[component.0] ?? .idle,
                        onInstall: { installComponent(component.0) }
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    private func installComponent(_ componentId: String) {
        // Prevent re-installing if already in progress or succeeded
        let currentStatus = componentStatuses[componentId] ?? .idle
        switch currentStatus {
        case .downloading, .installing, .success:
            return
        case .idle, .failed:
            break
        }

        componentStatuses[componentId] = .downloading(percent: 0)

        Task {
            do {
                try await SojuManager.shared.runWinetricks(
                    workspace: workspace,
                    component: componentId
                ) { progress in
                    Task { @MainActor in
                        switch progress {
                        case .downloading(let percent):
                            componentStatuses[componentId] = .downloading(percent: percent)
                        case .installing:
                            componentStatuses[componentId] = .installing
                        }
                    }
                }

                await MainActor.run {
                    componentStatuses[componentId] = .success
                }
            } catch {
                await MainActor.run {
                    componentStatuses[componentId] = .failed(error.localizedDescription)
                }
            }
        }
    }
}

/// Individual row for a winetricks component with independent install button
struct WinetricksComponentRow: View {
    let componentId: String
    let componentName: String
    let status: InstallStatus
    let onInstall: () -> Void

    /// Check if install is in progress
    private var isInstalling: Bool {
        switch status {
        case .downloading, .installing:
            return true
        default:
            return false
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(componentName)
                    .font(.body)
                    .foregroundColor(status == .success ? .secondary : .primary)
                Text(componentId)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status / Install button
            statusView
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            Button("Install") {
                onInstall()
            }
            .buttonStyle(.bordered)

        case .downloading(let percent):
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
                Text("Downloading \(percent)%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .frame(minWidth: 120, alignment: .trailing)

        case .installing:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
                Text("Installing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 120, alignment: .trailing)

        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                Text("Installed")
                    .font(.caption)
                    .foregroundColor(.green)
            }

        case .failed(let message):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 14))
                Button("Retry") {
                    onInstall()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .help("Failed: \(message)")
        }
    }
}

#Preview {
    WorkspaceSettingsView(workspace: Workspace.preview)
}
