//
//  WorkspaceCreationView.swift
//  Soju
//
//  Created on 2026-01-08.
//

import SwiftUI
import SojuKit

struct WorkspaceCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "desktopcomputer"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)

                // TODO: Add icon picker, Windows version picker
            }
            .formStyle(.grouped)
            .navigationTitle("Create Workspace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Create") {
                        // TODO: Call WorkspaceManager.createWorkspace()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    WorkspaceCreationView()
}
