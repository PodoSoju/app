import SwiftUI
import SojuKit

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
        .frame(width: 500, height: 400)
        .padding()
    }
}

/// Soju (Wine) 관련 설정
struct SojuSettingsView: View {
    @ObservedObject private var downloadManager = SojuDownloadManager.shared

    var body: some View {
        Form {
            Section("Soju (Wine Distribution)") {
                HStack {
                    Text("Installed Version:")
                    Spacer()
                    if let version = SojuManager.shared.version {
                        Text(version.versionString)
                            .foregroundStyle(.secondary)
                    } else if SojuManager.shared.isInstalled {
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

            Section("D3DMetal (Optional)") {
                HStack {
                    Text("Status:")
                    Spacer()
                    if SojuManager.shared.isD3DMetalInstalled {
                        Text("Installed")
                            .foregroundStyle(.green)
                    } else if SojuManager.shared.isGPTKInstalled() {
                        Text("GPTK available")
                            .foregroundStyle(.orange)
                    } else {
                        Text("GPTK not installed")
                            .foregroundStyle(.secondary)
                    }
                }

                if !SojuManager.shared.isD3DMetalInstalled && SojuManager.shared.isGPTKInstalled() {
                    Button("Install D3DMetal from GPTK") {
                        try? SojuManager.shared.installD3DMetalFromGPTK()
                    }
                }

                Text("D3DMetal provides DirectX 12 support. Requires Apple Game Porting Toolkit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            try? await downloadManager.checkForUpdate()
        }
    }
}

#Preview {
    SettingsView()
}
