//
//  ContentView.swift
//  Soju
//
//  Created on 2026-01-07.
//

import SwiftUI
import SojuKit

struct ContentView: View {
    @StateObject private var workspaceManager = WorkspaceManager.shared
    @State private var selectedWorkspace: Workspace?

    var body: some View {
        Group {
            if workspaceManager.workspaces.isEmpty {
                // No workspaces available
                emptyStateView
            } else if workspaceManager.workspaces.count == 1 {
                // Single workspace - go directly to desktop
                DesktopView(workspace: workspaceManager.workspaces[0])
                    .onAppear {
                        selectedWorkspace = workspaceManager.workspaces.first
                    }
            } else {
                // Multiple workspaces - show selection screen
                if let workspace = selectedWorkspace {
                    DesktopView(workspace: workspace)
                        .transition(.opacity)
                } else {
                    workspaceSelectionView
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
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

            Button("Create Workspace") {
                // TODO: Implement workspace creation
                print("Create workspace")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Workspace Selection
    private var workspaceSelectionView: some View {
        VStack(spacing: 30) {
            Text("Select a Workspace")
                .font(.largeTitle)

            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 20)
                ], spacing: 20) {
                    ForEach(workspaceManager.workspaces) { workspace in
                        WorkspaceCard(workspace: workspace) {
                            withAnimation {
                                selectedWorkspace = workspace
                            }
                        }
                    }
                }
                .padding()
            }

            Button("Back") {
                // TODO: Go back to main menu
                print("Back to main menu")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - Workspace Card
struct WorkspaceCard: View {
    @ObservedObject var workspace: Workspace
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: workspace.settings.icon)
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text(workspace.settings.name)
                .font(.headline)

            Text(workspace.url.lastPathComponent)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isHovered ? Color.accentColor : Color.gray.opacity(0.3),
                    lineWidth: 1.5
                )
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
        }
    }
}

#Preview("Multiple Workspaces") {
    ContentView()
}
