//
//  ContentView.swift
//  Soju
//
//  Created on 2026-01-07.
//

import SwiftUI
import SojuKit
import os.log

struct ContentView: View {
    @StateObject private var workspaceManager = WorkspaceManager.shared
    @State private var selectedWorkspace: Workspace?
    @State private var isCreatingWorkspace = false
    @State private var errorMessage: String?
    @State private var showCreateWorkspace = false

    var body: some View {
        Group {
            if workspaceManager.workspaces.isEmpty {
                // No workspaces available
                emptyStateView
            } else if workspaceManager.workspaces.count == 1 {
                // Single workspace - go directly to shortcuts grid
                ShortcutsGridView(workspace: workspaceManager.workspaces[0])
                    .onAppear {
                        selectedWorkspace = workspaceManager.workspaces.first
                    }
            } else {
                // Multiple workspaces - show selection screen
                if let workspace = selectedWorkspace {
                    ShortcutsGridView(workspace: workspace)
                        .transition(.opacity)
                } else {
                    workspaceSelectionView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wineglass")
                .imageScale(.large)
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Welcome to Soju")
                .font(.largeTitle)

            Text("No workspaces configured")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Button(isCreatingWorkspace ? "Creating..." : "Create Workspace") {
                Task {
                    await createFirstWorkspace()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCreatingWorkspace)
        }
        .padding()
    }

    // MARK: - Workspace Selection
    private var workspaceSelectionView: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 30) {
                Text("Select a Workspace")
                    .font(.largeTitle)

                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 20, alignment: .top)
                        ],
                        alignment: .center,
                        spacing: 20
                    ) {
                        ForEach(workspaceManager.workspaces) { workspace in
                            WorkspaceCard(workspace: workspace) {
                                Logger.sojuKit.logWithFile("📂 Workspace selected: \(workspace.settings.name)", level: .info)

                                // Sync with WorkspaceManager for Wine environment setup
                                workspaceManager.selectWorkspace(workspace)

                                withAnimation {
                                    selectedWorkspace = workspace
                                }
                                Logger.sojuKit.logWithFile("✅ Entered workspace: \(workspace.settings.name)", level: .debug)
                            }
                            .frame(minWidth: 200, maxWidth: 300)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button("Back") {
                    // TODO: Go back to main menu
                    print("Back to main menu")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()

            // + Button (floating bottom-right)
            Button(action: { showCreateWorkspace = true }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .padding(20)
            .sheet(isPresented: $showCreateWorkspace) {
                WorkspaceCreationView()
            }
        }
    }

    // MARK: - Actions

    private func createFirstWorkspace() async {
        isCreatingWorkspace = true
        errorMessage = nil

        do {
            let workspace = try await workspaceManager.createWorkspace(
                name: "My Workspace",
                icon: "desktopcomputer",
                windowsVersion: .win10
            )

            // After creation, select the workspace
            await MainActor.run {
                selectedWorkspace = workspace
                isCreatingWorkspace = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to create workspace: \(error.localizedDescription)"
                isCreatingWorkspace = false
            }
        }
    }
}

// MARK: - Workspace Card
struct WorkspaceCard: View {
    let workspace: Workspace
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: workspace.settings.icon)
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text(workspace.settings.name)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(workspace.url.lastPathComponent)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 200, minHeight: 150)
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            Logger.sojuKit.logWithFile("🖱️ Workspace double-clicked: \(workspace.settings.name)", level: .info)
            Logger.sojuKit.logWithFile("📂 Entering workspace...", level: .debug)
            onSelect()
            Logger.sojuKit.logWithFile("✅ onSelect() called", level: .debug)
        }
    }
}

#Preview("Multiple Workspaces") {
    ContentView()
}
