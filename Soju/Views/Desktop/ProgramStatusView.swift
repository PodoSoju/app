//
//  ProgramStatusView.swift
//  Soju
//
//  Created on 2026-01-07.
//

import SwiftUI
import SojuKit

/// Shows running programs with status and output
struct ProgramStatusView: View {
    @ObservedObject var workspace: Workspace
    @State private var selectedProgramId: UUID?
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Label("Running Programs", systemImage: "app.badge")
                    .font(.headline)

                Spacer()

                Text("\(workspace.programs.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(Capsule())

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            if isExpanded {
                // Programs list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if workspace.programs.isEmpty {
                            Text("No running programs")
                                .foregroundStyle(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(workspace.programs) { program in
                                ProgramRow(
                                    program: program,
                                    isSelected: selectedProgramId == program.id,
                                    onSelect: {
                                        selectedProgramId = program.id
                                    }
                                )
                            }
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 300)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
    }
}

// MARK: - Program Row

struct ProgramRow: View {
    @ObservedObject var program: Program
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var showOutput: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Icon
                if let icon = program.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "app.fill")
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.secondary)
                }

                // Name
                Text(program.name)
                    .font(.body)
                    .lineLimit(1)

                Spacer()

                // Status indicator
                if program.isRunning {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let exitCode = program.exitCode {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(exitCode == 0 ? .blue : .red)
                            .frame(width: 8, height: 8)
                        Text(exitCode == 0 ? "Completed" : "Failed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Output toggle
                Button(action: { showOutput.toggle() }) {
                    Image(systemName: showOutput ? "chevron.up" : "chevron.down")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture {
                onSelect()
            }

            // Output console
            if showOutput {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if program.output.isEmpty {
                            Text("No output yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(8)
                        } else {
                            ForEach(Array(program.output.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }
                            .padding(8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)
                .background(Color.black.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ProgramStatusView(workspace: Workspace(
        workspaceUrl: URL(fileURLWithPath: "/tmp/test"),
        isRunning: true,
        isAvailable: true
    ))
    .frame(width: 400)
}
