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

/// Program addition modal (stub for now)
struct AddProgramView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var workspace: Workspace
    @State private var programName = ""
    @State private var selectedFileURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Program Name", text: $programName)

                HStack {
                    if let url = selectedFileURL {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No file selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Browse...") {
                        selectExecutable()
                    }
                }

                // TODO: Add icon picker
                // TODO: Add arguments field
                // TODO: Add working directory picker
            }
            .formStyle(.grouped)
            .navigationTitle("Add Program")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") {
                        addProgram()
                    }
                    .disabled(programName.isEmpty || selectedFileURL == nil)
                }
            }
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions
    private func selectExecutable() {
        Logger.sojuKit.debug("Opening file picker for executable selection", category: "UI")

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.exe]
        panel.message = "Select a Windows executable (.exe)"

        // Start in workspace's drive_c
        panel.directoryURL = workspace.winePrefixURL

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Logger.sojuKit.info("Selected executable: \(url.lastPathComponent)", category: "UI")
                selectedFileURL = url

                // Auto-fill program name if empty
                if programName.isEmpty {
                    programName = url.deletingPathExtension().lastPathComponent
                }
            }
        }
    }

    private func addProgram() {
        guard let url = selectedFileURL else {
            Logger.sojuKit.warning("Cannot add program: no file selected", category: "UI")
            return
        }

        Logger.sojuKit.info("Adding program: \(programName) (\(url.lastPathComponent))", category: "UI")

        // TODO: Implement actual program addition to workspace.settings.pinnedPrograms
        // For now, just dismiss

        let program = PinnedProgram(name: programName, url: url)
        workspace.settings.pinnedPrograms.append(program)

        // Settings are automatically saved via Workspace.saveSettings() (called from settings didSet)
        Logger.sojuKit.info("Program added successfully", category: "UI")

        dismiss()
    }
}

#Preview {
    AddProgramView(workspace: Workspace.preview)
}
