//
//  WorkspaceCreationView.swift
//  PodoSoju
//
//  Created on 2026-01-08.
//

import SwiftUI
import PodoSojuKit
import os.log

struct WorkspaceCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "desktopcomputer"
    @State private var windowsVersion: WinVersion = .win10
    @State private var isCreating = false
    @State private var errorMessage: String?

    private let availableIcons = [
        "desktopcomputer",
        "laptopcomputer",
        "server.rack",
        "display",
        "pc",
        "macpro.gen3"
    ]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)

                Picker("Icon", selection: $icon) {
                    ForEach(availableIcons, id: \.self) { iconName in
                        Label {
                            Text(iconName)
                        } icon: {
                            Image(systemName: iconName)
                        }
                    }
                }

                Picker("Windows Version", selection: $windowsVersion) {
                    ForEach(WinVersion.allCases.reversed(), id: \.self) { version in
                        Text(version.pretty())
                    }
                }

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create Workspace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isCreating ? "Creating..." : "Create") {
                        createWorkspace()
                    }
                    .disabled(name.isEmpty || isCreating)
                }
            }
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func createWorkspace() {
        Logger.podoSojuKit.info("🏗️ User initiated workspace creation", category: "UI")
        Logger.podoSojuKit.debug("Name: '\(name)', Icon: '\(icon)', Windows: '\(windowsVersion)'", category: "UI")

        isCreating = true
        errorMessage = nil

        Task {
            do {
                _ = try await WorkspaceManager.shared.createWorkspace(
                    name: name,
                    icon: icon,
                    windowsVersion: windowsVersion
                )

                await MainActor.run {
                    Logger.podoSojuKit.info("✅ Workspace creation successful, dismissing modal", category: "UI")
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    Logger.podoSojuKit.error("❌ Workspace creation failed: \(error.localizedDescription)", category: "UI")
                    errorMessage = "Failed to create workspace: \(error.localizedDescription)"
                    isCreating = false
                }
            }
        }
    }
}

#Preview {
    WorkspaceCreationView()
}
