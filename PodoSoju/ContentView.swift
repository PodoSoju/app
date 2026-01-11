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
    @State private var showSettings = false

    var body: some View {
        Group {
            if showPodoSojuSetup {
                podoSojuSetupView
            } else if workspaceManager.workspaces.isEmpty {
                emptyStateView
            } else if let workspace = selectedWorkspace {
                // 워크스페이스 화면 + 홈 버튼
                ShortcutsGridView(workspace: workspace, onHome: {
                    withAnimation {
                        selectedWorkspace = nil
                    }
                })
            } else {
                // 워크스페이스 선택 화면
                workspaceSelectionView
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
            Logger.podoSojuKit.info("PodoSoju not installed, showing setup view")
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
                            WorkspaceCard(
                                workspace: workspace,
                                onSelect: {
                                    Logger.podoSojuKit.info("📂 Workspace selected: \(workspace.settings.name)")
                                    workspaceManager.selectWorkspace(workspace)

                                    withAnimation {
                                        selectedWorkspace = workspace
                                    }
                                },
                                onDelete: {
                                    Task {
                                        do {
                                            try await workspaceManager.deleteWorkspace(workspace)
                                            Logger.podoSojuKit.info("🗑️ Workspace deleted: \(workspace.settings.name)")
                                        } catch {
                                            Logger.podoSojuKit.error("Failed to delete workspace: \(error)")
                                        }
                                    }
                                }
                            )
                            .frame(minWidth: 200, maxWidth: 300)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()

            // Bottom-right buttons (cleanup, settings, +)
            HStack(spacing: 12) {
                // Wine 좀비 정리 버튼
                Button(action: { cleanupWineZombies() }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .help("Wine 좀비 프로세스 정리")

                // Settings button (전체 설정)
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                // + Button (새 워크스페이스)
                Button(action: { showCreateWorkspace = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .sheet(isPresented: $showCreateWorkspace) {
                WorkspaceCreationView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Actions

    /// Wine 좀비 프로세스 정리
    private func cleanupWineZombies() {
        let processNames = ["wine", "wineserver", "PodoJuice"]
        var killedCount = 0

        for name in processNames {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            task.arguments = ["-9", name]
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                killedCount += 1
            }
        }

        // NetFile 등 Wine 앱도 정리
        let killAllTask = Process()
        killAllTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killAllTask.arguments = ["-9", "-f", "C:\\\\"]  // Wine 경로 패턴
        try? killAllTask.run()
        killAllTask.waitUntilExit()

        Logger.podoSojuKit.info("Wine zombies cleaned up", category: "ContentView")
    }

    private func createFirstWorkspace() async {
        isCreatingWorkspace = true
        errorMessage = nil

        do {
            let workspace = try await workspaceManager.createWorkspace(
                name: "My Workspace",
                icon: "desktopcomputer",
                windowsVersion: .win10
            )

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
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: workspace.settings.icon)
                    .font(.system(size: 48))
                    .foregroundColor(.blue)

                // 실행 중 표시
                if workspace.isRunning {
                    Circle()
                        .fill(.green)
                        .frame(width: 12, height: 12)
                        .offset(x: 4, y: -4)
                }
            }

            Text(workspace.settings.name)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("\(workspace.desktopShortcutCount) apps")
                .font(.caption)
                .foregroundColor(.secondary)
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
            onSelect()
        }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Workspace", systemImage: "trash")
            }
        }
        .alert("Delete Workspace?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("'\(workspace.settings.name)' will be permanently deleted. This cannot be undone.")
        }
    }
}

#Preview("Multiple Workspaces") {
    ContentView()
}
