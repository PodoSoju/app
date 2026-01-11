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
struct WinetricksTab: View {
    @ObservedObject var workspace: Workspace
    @State private var isInstalling = false
    @State private var installStatus: String?

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
                    HStack {
                        VStack(alignment: .leading) {
                            Text(component.1)
                                .font(.body)
                            Text(component.0)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Install") {
                            installComponent(component.0)
                        }
                        .disabled(isInstalling)
                    }
                }
            }

            if let status = installStatus {
                Section("Status") {
                    HStack {
                        if isInstalling {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(status)
                            .foregroundColor(isInstalling ? .secondary : .green)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func installComponent(_ component: String) {
        isInstalling = true
        installStatus = "Installing \(component)..."

        Task {
            do {
                try await SojuManager.shared.runWinetricks(
                    workspace: workspace,
                    component: component
                )
                await MainActor.run {
                    installStatus = "✓ \(component) installed successfully"
                    isInstalling = false
                }
            } catch {
                await MainActor.run {
                    installStatus = "✗ Failed: \(error.localizedDescription)"
                    isInstalling = false
                }
            }
        }
    }
}

#Preview {
    WorkspaceSettingsView(workspace: Workspace.preview)
}
