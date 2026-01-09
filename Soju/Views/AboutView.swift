import SwiftUI

struct AboutView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 20) {
            // App Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            // App Name
            Text("PodoSoju")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Tagline
            Text("포도소주 - Windows apps on macOS")
                .font(.headline)
                .foregroundStyle(.secondary)

            // Version
            Text("Version \(appVersion) (\(buildNumber))")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Divider()
                .frame(width: 200)

            // Description
            VStack(spacing: 8) {
                Text("PodoSoju is a Wine-based Windows application launcher for macOS.")
                    .multilineTextAlignment(.center)

                Text("Powered by Soju (소주 - Wine distribution)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 300)

            Divider()
                .frame(width: 200)

            // Credits
            VStack(spacing: 4) {
                Text("Built with")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Link("Wine", destination: URL(string: "https://www.winehq.org")!)
                    Link("DXMT", destination: URL(string: "https://github.com/3Shain/dxmt")!)
                    Link("DXVK", destination: URL(string: "https://github.com/doitsujin/dxvk")!)
                }
                .font(.caption)
            }

            // Copyright
            Text("© 2025")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .padding(40)
        .frame(width: 400, height: 480)
    }
}

#Preview {
    AboutView()
}
