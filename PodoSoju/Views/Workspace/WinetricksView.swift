//
//  WinetricksView.swift
//  PodoSoju
//
//  Created on 2026-01-11.
//

import SwiftUI
import PodoSojuKit

/// Winetricks component browser and runner (Whisky-style)
/// Displays available winetricks verbs in a tabbed interface and runs them via Terminal.app
struct WinetricksView: View {
    let workspace: Workspace

    @State private var winetricks: [WinetricksCategory]?
    @State private var selectedTrick: UUID?
    @State private var isLoading = true
    @State private var loadError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("Winetricks")
                    .font(.title)
                    .fontWeight(.semibold)
                Text("Select a component to install")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 16)

            Divider()

            // Content
            if isLoading {
                loadingView
            } else if let error = loadError {
                errorView(error)
            } else if let winetricks = winetricks, !winetricks.isEmpty {
                tabbedContentView(winetricks)
            } else {
                emptyView
            }
        }
        .frame(minWidth: 600, minHeight: 450)
        .onAppear {
            loadVerbs()
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
            Text("Loading winetricks verbs...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Failed to load winetricks")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                loadVerbs()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No winetricks verbs found")
                .font(.headline)
            Spacer()
        }
    }

    private func tabbedContentView(_ categories: [WinetricksCategory]) -> some View {
        VStack(spacing: 0) {
            TabView {
                ForEach(categories, id: \.category) { category in
                    VerbTableView(
                        verbs: category.verbs,
                        selection: $selectedTrick
                    )
                    .tabItem {
                        Text(categoryDisplayName(category.category))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()

            // Action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Run") {
                    runSelectedTrick(categories)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTrick == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private func categoryDisplayName(_ category: WinetricksCategories) -> String {
        switch category {
        case .apps:
            return "Apps"
        case .benchmarks:
            return "Benchmarks"
        case .dlls:
            return "DLLs"
        case .fonts:
            return "Fonts"
        case .games:
            return "Games"
        case .settings:
            return "Settings"
        }
    }

    private func loadVerbs() {
        isLoading = true
        loadError = nil

        Task.detached {
            do {
                let categories = try await SojuManager.shared.listWinetricksVerbs()
                await MainActor.run {
                    self.winetricks = categories
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.loadError = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func runSelectedTrick(_ categories: [WinetricksCategory]) {
        guard let selectedId = selectedTrick else { return }

        // Find the selected verb across all categories
        let allVerbs = categories.flatMap { $0.verbs }
        guard let verb = allVerbs.first(where: { $0.id == selectedId }) else { return }

        // Run in Terminal and dismiss
        Task.detached {
            await SojuManager.shared.runWinetricksInTerminal(
                command: verb.name,
                workspace: workspace
            )
        }
        dismiss()
    }
}

/// Table view for displaying winetricks verbs
private struct VerbTableView: View {
    let verbs: [WinetricksVerb]
    @Binding var selection: UUID?

    var body: some View {
        Table(verbs, selection: $selection) {
            TableColumn("Name") { verb in
                Text(verb.name)
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 100, ideal: 150, max: 200)

            TableColumn("Description") { verb in
                Text(verb.description)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

#if DEBUG
#Preview {
    WinetricksView(workspace: Workspace.preview)
}
#endif
