//
//  AddProgramView.swift
//  Soju
//
//  Created on 2026-01-08.
//

import SwiftUI
import SojuKit
import AppKit
import os.log
import UniformTypeIdentifiers

// MARK: - UTType Extension
extension UTType {
    static var exe: UTType {
        UTType(filenameExtension: "exe") ?? .data
    }
}

// MARK: - Add Mode
enum AddProgramMode {
    case file      // Add File: start from ~/Downloads (installer)
    case shortcut  // Add Shortcut: start from drive_c (direct exe)
}

/// Program addition modal - simplified flow with two entry points
/// - "Add File": Browse from ~/Downloads for installer files
/// - "Add Shortcut": Browse from drive_c for direct exe shortcuts
struct AddProgramView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var workspace: Workspace

    // Mode selection
    @State private var selectedMode: AddProgramMode?

    // File selection state
    @State private var programName = ""
    @State private var selectedFileURL: URL?
    @State private var isInstaller = false

    // Installation progress state
    @State private var showInstallationProgress = false
    @State private var installerProgram: Program?

    var body: some View {
        NavigationStack {
            if selectedMode == nil {
                // Mode selection view
                modeSelectionView
            } else {
                // File selection form
                fileSelectionForm
            }
        }
        .frame(width: 450)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showInstallationProgress) {
            if let program = installerProgram {
                InstallationProgressView(
                    program: program,
                    workspace: workspace,
                    onComplete: { discoveredPrograms in
                        // Add discovered programs to workspace
                        for discovered in discoveredPrograms {
                            let pinnedProgram = PinnedProgram(
                                name: discovered.name,
                                url: discovered.url
                            )
                            workspace.settings.pinnedPrograms.append(pinnedProgram)
                        }

                        showInstallationProgress = false
                        dismiss()  // Close AddProgramView
                    }
                )
            }
        }
    }

    // MARK: - Mode Selection View

    private var modeSelectionView: some View {
        VStack(spacing: 20) {
            Text("Choose how to add a program")
                .font(.headline)
                .padding(.top, 20)

            VStack(spacing: 12) {
                // Add File button
                Button {
                    selectedMode = .file
                    selectExecutable(mode: .file)
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .font(.title2)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add File")
                                .fontWeight(.medium)
                            Text("Browse Downloads for installer (.exe)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Add Shortcut button
                Button {
                    selectedMode = .shortcut
                    selectExecutable(mode: .shortcut)
                } label: {
                    HStack {
                        Image(systemName: "link.badge.plus")
                            .font(.title2)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Shortcut")
                                .fontWeight(.medium)
                            Text("Browse installed programs in drive_c")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .navigationTitle("Add Program")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: - File Selection Form

    private var fileSelectionForm: some View {
        Form {
            Section {
                HStack {
                    if let url = selectedFileURL {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent)
                                .fontWeight(.medium)
                            // Show relative path from drive_c or full path for external files
                            if let relativePath = relativePathFromDriveC(url) {
                                Text(relativePath)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text(url.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    } else {
                        Text("No file selected")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Browse...") {
                        if let mode = selectedMode {
                            selectExecutable(mode: mode)
                        }
                    }
                }
            } header: {
                Text("Executable")
            }

            if selectedFileURL != nil {
                Section {
                    TextField("Name", text: $programName)
                } header: {
                    Text("Shortcut Name")
                }

                if isInstaller {
                    Section {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.orange)
                            Text("This appears to be an installer.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(selectedMode == .file ? "Add File" : "Add Shortcut")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                if isInstaller {
                    Button("Run Installer") {
                        runInstaller()
                    }
                    .disabled(programName.isEmpty || selectedFileURL == nil)
                } else {
                    Button("Add Shortcut") {
                        addProgram()
                    }
                    .disabled(programName.isEmpty || selectedFileURL == nil)
                }
            }
        }
    }

    // MARK: - Helpers
    private func relativePathFromDriveC(_ url: URL) -> String? {
        let driveCPath = workspace.winePrefixURL.path
        let filePath = url.deletingLastPathComponent().path
        if filePath.hasPrefix(driveCPath) {
            let relative = String(filePath.dropFirst(driveCPath.count))
            return relative.isEmpty ? "/" : relative
        }
        return nil
    }

    // MARK: - Actions
    private func selectExecutable(mode: AddProgramMode) {
        Logger.sojuKit.debug("Opening file picker for executable selection (mode: \(String(describing: mode)))", category: "UI")

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.exe]
        panel.prompt = "Select"

        // Set starting directory based on mode
        switch mode {
        case .file:
            // Start from ~/Downloads for installer files
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            panel.message = "Select an installer file (.exe) from Downloads"
        case .shortcut:
            // Start from workspace's drive_c folder for shortcuts
            panel.directoryURL = workspace.winePrefixURL
            panel.message = "Select a Windows executable (.exe) to create a shortcut"
        }

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Logger.sojuKit.info("Selected executable: \(url.lastPathComponent)", category: "UI")
                selectedFileURL = url

                // Check if installer and update state
                isInstaller = InstallerDetector.isInstaller(url)

                // Auto-fill program name
                if isInstaller {
                    // Use friendly name from installer
                    programName = InstallerDetector.installerName(from: url)
                    Logger.sojuKit.info("Detected installer: \(programName)", category: "UI")
                } else {
                    // Use filename without extension
                    programName = url.deletingPathExtension().lastPathComponent
                }
            } else if response == .cancel && selectedFileURL == nil {
                // User cancelled without selecting - go back to mode selection
                selectedMode = nil
            }
        }
    }

    private func addProgram() {
        guard let url = selectedFileURL else {
            Logger.sojuKit.warning("Cannot add program: no file selected", category: "UI")
            return
        }

        Logger.sojuKit.info("Adding program: \(programName) (\(url.lastPathComponent))", category: "UI")
        Logger.sojuKit.debug("  URL: \(url.path)", category: "UI")
        Logger.sojuKit.debug("  Workspace: \(workspace.settings.name)", category: "UI")
        Logger.sojuKit.debug("  Current pinnedPrograms count: \(workspace.settings.pinnedPrograms.count)", category: "UI")

        let program = PinnedProgram(name: programName, url: url)
        workspace.settings.pinnedPrograms.append(program)

        Logger.sojuKit.info("Program added successfully", category: "UI")
        Logger.sojuKit.debug("  New pinnedPrograms count: \(workspace.settings.pinnedPrograms.count)", category: "UI")

        // Log all pinned programs for debugging
        for (index, pinned) in workspace.settings.pinnedPrograms.enumerated() {
            Logger.sojuKit.debug("  [\(index)] \(pinned.name): \(pinned.url?.path ?? "nil")", category: "UI")
        }

        dismiss()
    }

    private func runInstaller() {
        guard let url = selectedFileURL else {
            Logger.sojuKit.warning("Cannot run installer: no file selected", category: "UI")
            return
        }

        Logger.sojuKit.info("Starting installer: \(programName) (\(url.lastPathComponent))", category: "UI")

        installerProgram = Program(name: programName, url: url)
        showInstallationProgress = true
    }
}

#Preview {
    AddProgramView(workspace: Workspace.preview)
}
