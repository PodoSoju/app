//
//  GraphicsSettingsView.swift
//  Soju
//
//  Created on 2026-01-09.
//

import SwiftUI
import PodoSojuKit
import os.log

struct GraphicsSettingsView: View {
    @StateObject private var downloadManager = SojuDownloadManager.shared
    @State private var gptkStatus: GPTKInstallationStatus = .notInstalled
    @State private var isCheckingUpdate: Bool = false
    @State private var updateAvailable: GitHubRelease?
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var showDownloadProgress: Bool = false

    var body: some View {
        Form {
            // Soju Section
            Section("Soju (Wine)") {
                sojuStatusView

                if showDownloadProgress {
                    downloadProgressView
                }
            }

            // Graphics Backend Section
            Section("Graphics Backend") {
                graphicsBackendInfoView
            }

            // GPTK Section
            Section("Game Porting Toolkit (D3DMetal)") {
                gptkStatusView
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            gptkStatus = SojuManager.shared.checkGPTKStatus()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    // MARK: - Soju Status View

    @ViewBuilder
    private var sojuStatusView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Installation Status")
                    .font(.headline)

                if downloadManager.isInstalled {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Installed")
                            .foregroundColor(.secondary)
                        if let version = downloadManager.currentVersion {
                            Text("v\(version)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Not Installed")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if downloadManager.state.isInProgress {
                ProgressView()
                    .scaleEffect(0.8)
            } else if isCheckingUpdate {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                HStack(spacing: 8) {
                    Button("Check for Updates") {
                        checkForUpdates()
                    }
                    .buttonStyle(.bordered)

                    if !downloadManager.isInstalled {
                        Button("Install") {
                            installSoju()
                        }
                        .buttonStyle(.borderedProminent)
                    } else if updateAvailable != nil {
                        Button("Update") {
                            installSoju()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }

        if let release = updateAvailable {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.blue)
                Text("Update available: v\(release.version)")
                    .foregroundColor(.blue)
            }
            .font(.caption)
        }
    }

    // MARK: - Download Progress View

    @ViewBuilder
    private var downloadProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                switch downloadManager.state {
                case .checking:
                    Text("Checking for updates...")
                case .downloading:
                    Text("Downloading...")
                case .extracting:
                    Text("Extracting...")
                case .installing:
                    Text("Installing...")
                case .completed:
                    Text("Installation complete!")
                        .foregroundColor(.green)
                case .failed(let error):
                    Text("Failed: \(error.localizedDescription)")
                        .foregroundColor(.red)
                case .idle:
                    EmptyView()
                }
                Spacer()

                if downloadManager.state.isInProgress {
                    Button("Cancel") {
                        downloadManager.cancelDownload()
                        showDownloadProgress = false
                    }
                    .buttonStyle(.bordered)
                }
            }

            if case .downloading(let progress) = downloadManager.state {
                ProgressView(value: progress)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Graphics Backend Info View

    @ViewBuilder
    private var graphicsBackendInfoView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(backend.displayName)
                                .font(.headline)

                            if backend == .dxmt {
                                Text("Default")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }

                            if backend == .d3dmetal && !gptkStatus.isInstalled {
                                Text("GPTK Required")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            }
                        }

                        Text(backend.description)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Supports: \(backend.supportedDirectX)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                if backend != GraphicsBackend.allCases.last {
                    Divider()
                }
            }
        }

        Text("Graphics backend is configured per-workspace in the workspace settings.")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 4)
    }

    // MARK: - GPTK Status View

    @ViewBuilder
    private var gptkStatusView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("GPTK Status")
                    .font(.headline)

                switch gptkStatus {
                case .installed(let version):
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Installed")
                            .foregroundColor(.secondary)
                        if let version = version {
                            Text("v\(version)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                case .partiallyInstalled:
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Partially Installed")
                            .foregroundColor(.secondary)
                    }
                case .notInstalled:
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                        Text("Not Installed")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if gptkStatus.isInstalled {
                Button("Install D3DMetal") {
                    installD3DMetal()
                }
                .buttonStyle(.bordered)
                .disabled(SojuManager.shared.isD3DMetalInstalled)
            } else {
                Link("Get GPTK", destination: URL(string: "https://developer.apple.com/games/game-porting-toolkit/")!)
                    .buttonStyle(.bordered)
            }
        }

        if SojuManager.shared.isD3DMetalInstalled {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("D3DMetal.framework is installed in Soju")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Remove") {
                    removeD3DMetal()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .font(.caption)
            }
        }

        if !gptkStatus.isInstalled {
            VStack(alignment: .leading, spacing: 4) {
                Text("D3DMetal requires Apple's Game Porting Toolkit (GPTK) to be installed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("GPTK provides DX11/DX12 support through Apple's D3DMetal translation layer.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Actions

    private func checkForUpdates() {
        isCheckingUpdate = true
        updateAvailable = nil

        Task {
            do {
                let release = try await downloadManager.checkForUpdate()
                await MainActor.run {
                    updateAvailable = release
                    isCheckingUpdate = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isCheckingUpdate = false
                }
            }
        }
    }

    private func installSoju() {
        showDownloadProgress = true

        Task {
            do {
                // First check for latest release if not already done
                if downloadManager.latestRelease == nil {
                    _ = try await downloadManager.checkForUpdate()
                }

                try await downloadManager.downloadLatest()

                await MainActor.run {
                    updateAvailable = nil
                    // Keep progress view visible briefly to show completion
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showDownloadProgress = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func installD3DMetal() {
        do {
            try SojuManager.shared.installD3DMetalFromGPTK()
            // Force view refresh
            gptkStatus = SojuManager.shared.checkGPTKStatus()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func removeD3DMetal() {
        do {
            try SojuManager.shared.uninstallD3DMetal()
            // Force view refresh
            gptkStatus = SojuManager.shared.checkGPTKStatus()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Preview

#Preview {
    GraphicsSettingsView()
        .frame(width: 600, height: 500)
}
