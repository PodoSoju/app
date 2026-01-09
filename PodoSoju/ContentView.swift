//
//  ContentView.swift
//  PodoSoju
//
//  Created on 2026-01-07.
//

import SwiftUI
import PodoSojuKit
import os.log

struct ContentView: View {
    @StateObject private var workspaceManager = WorkspaceManager.shared
    @StateObject private var downloadManager = SojuDownloadManager.shared
    @State private var selectedWorkspace: Workspace?
    @State private var isCreatingWorkspace = false
    @State private var errorMessage: String?
    @State private var showCreateWorkspace = false
    @State private var showPodoSojuSetup = false
    @State private var hasCheckedPodoSoju = false

    var body: some View {
        Group {
            if showPodoSojuSetup {
                // PodoSoju not installed - show setup view
                podoSojuSetupView
            } else if workspaceManager.workspaces.isEmpty {
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
        .onAppear {
            checkPodoSojuInstallation()
        }
    }

    // MARK: - PodoSoju Installation Check

    private func checkPodoSojuInstallation() {
        guard !hasCheckedPodoSoju else { return }
        hasCheckedPodoSoju = true

        if !SojuManager.shared.isInstalled {
            Logger.sojuKit.info("PodoSoju not installed, showing setup view")
            showPodoSojuSetup = true
        }
    }

    // MARK: - PodoSoju Setup View

    private var podoSojuSetupView: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle")
                .imageScale(.large)
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Soju Required")
                .font(.largeTitle)

            Text("PodoSoju requires Soju (Wine distribution) to run Windows applications.\nPlease download and install it to continue.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            // Download progress
            if downloadManager.state.isInProgress {
                VStack(spacing: 8) {
                    switch downloadManager.state {
                    case .checking:
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Checking for latest version...")
                        }
                    case .downloading(let progress):
                        VStack(spacing: 4) {
                            ProgressView(value: progress)
                                .frame(width: 300)
                            Text("Downloading... \(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    case .extracting:
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Extracting...")
                        }
                    case .installing:
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Installing...")
                        }
                    default:
                        EmptyView()
                    }

                    Button("Cancel") {
                        downloadManager.cancelDownload()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button("Download Soju") {
                    downloadSoju()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if case .completed = downloadManager.state {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Installation complete!")
                }
                .onAppear {
                    // Wait a moment then proceed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            showPodoSojuSetup = false
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func downloadSoju() {
        errorMessage = nil

        Task {
            do {
                _ = try await downloadManager.checkForUpdate()
                try await downloadManager.downloadLatest()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
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
                                Logger.sojuKit.info("📂 Workspace selected: \(workspace.settings.name)")

                                // Sync with WorkspaceManager for Wine environment setup
                                workspaceManager.selectWorkspace(workspace)

                                withAnimation {
                                    selectedWorkspace = workspace
                                }
                                Logger.sojuKit.debug("✅ Entered workspace: \(workspace.settings.name)")
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
            Logger.sojuKit.info("🖱️ Workspace double-clicked: \(workspace.settings.name)")
            Logger.sojuKit.debug("📂 Entering workspace...")
            onSelect()
            Logger.sojuKit.debug("✅ onSelect() called")
        }
    }
}

#Preview("Multiple Workspaces") {
    ContentView()
}
