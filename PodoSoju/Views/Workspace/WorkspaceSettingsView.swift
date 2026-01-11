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
    @State private var showWinetricks = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("General").tag(0)
                Text("Wine").tag(1)
                Text("Graphics").tag(2)
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
                default:
                    GeneralSettingsTab(workspace: workspace)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom buttons
            HStack {
                Button("Winetricks...") {
                    showWinetricks = true
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Done") {
                    let currentSettings = workspace.settings
                    workspace.settings = currentSettings
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .sheet(isPresented: $showWinetricks) {
            WinetricksView(workspace: workspace)
        }
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
                    set: { newVersion in
                        let oldVersion = workspace.settings.windowsVersion
                        workspace.settings.windowsVersion = newVersion
                        // Apply to registry if changed
                        if oldVersion != newVersion {
                            Task {
                                do {
                                    try await SojuManager.shared.applyWindowsVersion(newVersion, to: workspace)
                                } catch {
                                    Logger.podoSojuKit.error("Failed to apply Windows version: \(error)")
                                }
                            }
                        }
                    }
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

#if DEBUG
#Preview {
    WorkspaceSettingsView(workspace: Workspace.preview)
}
#endif
