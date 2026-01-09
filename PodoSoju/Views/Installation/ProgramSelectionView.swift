//
//  ProgramSelectionView.swift
//  PodoSoju
//
//  Created on 2026-01-08.
//

import SwiftUI
import PodoSojuKit

/// View for selecting discovered programs to add to workspace after installation
struct ProgramSelectionView: View {
    // MARK: - Properties

    let programs: [DiscoveredProgram]
    let onConfirm: ([DiscoveredProgram]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPrograms: Set<DiscoveredProgram.ID> = []

    // MARK: - Initialization

    init(programs: [DiscoveredProgram], onConfirm: @escaping ([DiscoveredProgram]) -> Void) {
        self.programs = programs
        self.onConfirm = onConfirm

        // Pre-select all programs by default
        _selectedPrograms = State(initialValue: Set(programs.map(\.id)))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                headerSection

                Divider()

                // Programs list
                programsList

                Divider()

                // Footer with action buttons
                footerSection
            }
            .navigationTitle("발견된 프로그램")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("건너뛰기") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("추가할 프로그램 선택")
                .font(.headline)

            Text("\(programs.count)개의 프로그램을 발견했습니다. 워크스페이스에 추가할 프로그램을 선택하세요.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var programsList: some View {
        List(selection: $selectedPrograms) {
            ForEach(programs) { program in
                ProgramRow(
                    program: program,
                    isSelected: selectedPrograms.contains(program.id)
                )
                .tag(program.id)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleSelection(program.id)
                }
            }
        }
        .listStyle(.inset)
    }

    private var footerSection: some View {
        HStack {
            // Selection controls
            HStack(spacing: 12) {
                Button("모두 선택") {
                    selectedPrograms = Set(programs.map(\.id))
                }
                .buttonStyle(.link)

                Button("모두 해제") {
                    selectedPrograms.removeAll()
                }
                .buttonStyle(.link)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                Button("취소") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("추가 (\(selectedPrograms.count))") {
                    confirmSelection()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedPrograms.isEmpty)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func toggleSelection(_ id: DiscoveredProgram.ID) {
        if selectedPrograms.contains(id) {
            selectedPrograms.remove(id)
        } else {
            selectedPrograms.insert(id)
        }
    }

    private func confirmSelection() {
        let selected = programs.filter { selectedPrograms.contains($0.id) }
        onConfirm(selected)
        dismiss()
    }
}

// MARK: - Program Row

private struct ProgramRow: View {
    let program: DiscoveredProgram
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundColor(isSelected ? .accentColor : .secondary)

            // App icon
            Image(systemName: "app.fill")
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)

            // Program info
            VStack(alignment: .leading, spacing: 4) {
                Text(program.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    // File path
                    Text(program.url.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    // Badge for shortcut files
                    if program.isFromShortcut {
                        Text("바로가기")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("Multiple Programs") {
    ProgramSelectionView(
        programs: [
            DiscoveredProgram(
                name: "Notepad++",
                url: URL(fileURLWithPath: "/Users/test/.wine/drive_c/Program Files/Notepad++/notepad++.exe"),
                isFromShortcut: true
            ),
            DiscoveredProgram(
                name: "Firefox",
                url: URL(fileURLWithPath: "/Users/test/.wine/drive_c/Program Files/Mozilla Firefox/firefox.exe"),
                isFromShortcut: false
            ),
            DiscoveredProgram(
                name: "Steam",
                url: URL(fileURLWithPath: "/Users/test/.wine/drive_c/Program Files (x86)/Steam/Steam.exe"),
                isFromShortcut: true
            )
        ],
        onConfirm: { selected in
            print("Selected \(selected.count) programs")
        }
    )
}

#Preview("Single Program") {
    ProgramSelectionView(
        programs: [
            DiscoveredProgram(
                name: "Calculator",
                url: URL(fileURLWithPath: "/Users/test/.wine/drive_c/Windows/System32/calc.exe"),
                isFromShortcut: false
            )
        ],
        onConfirm: { selected in
            print("Selected \(selected.count) programs")
        }
    )
}

#Preview("Empty State") {
    ProgramSelectionView(
        programs: [],
        onConfirm: { _ in }
    )
}
