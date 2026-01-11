import SwiftUI
import PodoSojuKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GraphicsSettingsView()
                .tabItem {
                    Label("Graphics", systemImage: "display")
                }

            LogSettingsView()
                .tabItem {
                    Label("Logs", systemImage: "doc.text")
                }

            SojuSettingsView()
                .tabItem {
                    Label("Soju", systemImage: "wineglass")
                }
        }
        .frame(width: 500, height: 550)
        .padding()
    }
}

/// Soju (Wine) 관련 설정
struct SojuSettingsView: View {
    @ObservedObject private var downloadManager = SojuDownloadManager.shared
    @ObservedObject private var sojuManager = SojuManager.shared
    @State private var selectedReleaseId: String?

    private var installedVersion: String? {
        sojuManager.version?.versionString
    }

    var body: some View {
        Form {
            Section("Soju (Wine Distribution)") {
                HStack {
                    Text("Installed Version:")
                    Spacer()
                    if let version = sojuManager.version {
                        Text(version.versionString)
                            .foregroundStyle(.secondary)
                    } else if sojuManager.isInstalled {
                        Text("Unknown")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not installed")
                            .foregroundStyle(.red)
                    }
                }

                HStack {
                    Text("Latest Version:")
                    Spacer()
                    if let release = downloadManager.latestRelease {
                        Text(release.version)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Checking...")
                            .foregroundStyle(.secondary)
                    }
                }

                if downloadManager.state.isInProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Downloading...")
                        ProgressView(value: downloadManager.downloadProgress)
                    }
                } else {
                    Button("Check for Updates") {
                        Task {
                            try? await downloadManager.checkForUpdate()
                        }
                    }
                }
            }

            Section("Version Selection") {
                if downloadManager.allReleases.isEmpty {
                    HStack {
                        Text("Loading versions...")
                            .foregroundStyle(.secondary)
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    }
                } else {
                    Picker("Select Version", selection: $selectedReleaseId) {
                        Text("Select a version")
                            .tag(nil as String?)
                        ForEach(downloadManager.allReleases) { release in
                            Text(versionLabel(for: release))
                                .tag(release.id as String?)
                        }
                    }
                    .pickerStyle(.menu)

                    if downloadManager.state.isInProgress {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Installing...")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Install Selected Version") {
                            installSelectedVersion()
                        }
                        .disabled(selectedReleaseId == nil || isSelectedVersionInstalled)
                    }

                    if isSelectedVersionInstalled {
                        Text("This version is already installed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("D3DMetal (Optional)") {
                HStack {
                    Text("Status:")
                    Spacer()
                    if sojuManager.isD3DMetalInstalled {
                        Text("Installed")
                            .foregroundStyle(.green)
                    } else if sojuManager.isGPTKInstalled() {
                        Text("GPTK available")
                            .foregroundStyle(.orange)
                    } else {
                        Text("GPTK not installed")
                            .foregroundStyle(.secondary)
                    }
                }

                if !sojuManager.isD3DMetalInstalled && sojuManager.isGPTKInstalled() {
                    Button("Install D3DMetal from GPTK") {
                        try? sojuManager.installD3DMetalFromGPTK()
                    }
                }

                Text("D3DMetal provides DirectX 12 support. Requires Apple Game Porting Toolkit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            try? await downloadManager.fetchAllReleases()
        }
    }

    private var isSelectedVersionInstalled: Bool {
        guard let selectedId = selectedReleaseId,
              let release = downloadManager.allReleases.first(where: { $0.id == selectedId }) else {
            return false
        }
        return release.version == installedVersion
    }

    private func versionLabel(for release: GitHubRelease) -> String {
        var label = release.version
        if release.prerelease {
            label += " (pre)"
        }
        if release.version == installedVersion {
            label += " (installed)"
        }
        return label
    }

    private func installSelectedVersion() {
        guard let selectedId = selectedReleaseId,
              let release = downloadManager.allReleases.first(where: { $0.id == selectedId }) else {
            return
        }
        Task {
            try? await downloadManager.downloadRelease(release)
        }
    }
}

#Preview {
    SettingsView()
}
