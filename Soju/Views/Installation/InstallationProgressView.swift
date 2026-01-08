//
//  InstallationProgressView.swift
//  Soju
//
//  Created on 2026-01-08.
//

import SwiftUI
import SojuKit

/// View that shows installation progress and discovered programs
///
/// **Workflow:**
/// 1. Runs installer via Program.run()
/// 2. Shows live output from AsyncStream
/// 3. Monitors installation completion via exitCode
/// 4. Scans for newly installed programs
/// 5. Presents program selection UI
@MainActor
struct InstallationProgressView: View {
    // MARK: - Properties

    /// The installer program being executed
    @ObservedObject var program: Program

    /// The workspace where installation is happening
    let workspace: Workspace

    /// Callback invoked with discovered programs
    let onComplete: ([DiscoveredProgram]) -> Void

    /// Environment dismiss action
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// Current installation phase
    @State private var phase: InstallationPhase = .installing

    /// Discovered programs after successful installation
    @State private var discoveredPrograms: [DiscoveredProgram] = []

    /// Error message if installation or scanning fails
    @State private var errorMessage: String?

    /// Scroll position for auto-scrolling output
    @State private var scrollTarget: UUID?

    /// Current operation being performed (for error context)
    @State private var currentOperation: String = "초기화 중"

    /// Error context with detailed information
    @State private var errorContext: ErrorContext?

    // MARK: - Initialization

    init(
        program: Program,
        workspace: Workspace,
        onComplete: @escaping ([DiscoveredProgram]) -> Void
    ) {
        self.program = program
        self.workspace = workspace
        self.onComplete = onComplete
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with current phase
                headerSection

                Divider()

                // Main content based on phase
                contentSection

                Divider()

                // Footer with actions
                footerSection
            }
            .navigationTitle("설치 진행 중")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                    .disabled(program.isRunning)
                }
            }
        }
        .frame(width: 600, height: 700)
        .task {
            await startInstallation()
        }
        .onChange(of: program.exitCode) { oldValue, newValue in
            if let exitCode = newValue {
                handleInstallationComplete(exitCode: exitCode)
            }
        }
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(phaseTitle)
                .font(.headline)

            Text(phaseDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    @ViewBuilder
    private var contentSection: some View {
        switch phase {
        case .installing:
            installingView

        case .scanning:
            scanningView

        case .programsFound:
            programsFoundView

        case .noProgramsFound:
            noProgramsFoundView

        case .error:
            errorView
        }
    }

    private var footerSection: some View {
        HStack {
            // Phase indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(phaseIndicatorColor)
                    .frame(width: 8, height: 8)

                Text(phaseStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Action buttons
            actionButtons
        }
        .padding()
    }

    // MARK: - Phase Views

    private var installingView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Progress indicator with current operation
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProgressView()
                                .controlSize(.small)

                            Text(currentOperation)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Text(program.name)
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .padding()

                    Divider()

                    // Live output
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(program.output.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .id(UUID())
                        }

                        // Invisible anchor for auto-scroll
                        Color.clear
                            .frame(height: 1)
                            .id(scrollTarget)
                    }
                    .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: program.output.count) { oldValue, newValue in
                // Auto-scroll to bottom when new output arrives
                let newTarget = UUID()
                scrollTarget = newTarget
                withAnimation {
                    proxy.scrollTo(newTarget, anchor: .bottom)
                }
            }
        }
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)

            Text("프로그램 검색 중...")
                .font(.title3)

            Text("설치된 프로그램을 찾고 있습니다.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private var programsFoundView: some View {
        ProgramSelectionView(
            programs: discoveredPrograms,
            onConfirm: { selectedPrograms in
                onComplete(selectedPrograms)
                dismiss()
            }
        )
    }

    private var noProgramsFoundView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("프로그램을 찾지 못했습니다")
                    .font(.title3)
                    .fontWeight(.medium)

                Text("설치가 완료되었지만 자동으로 프로그램을 찾을 수 없습니다.\n수동으로 실행 파일을 추가해주세요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxHeight: .infinity)
        .padding()
    }

    private var errorView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Error icon and title
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)

                Text("오류 발생")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Error context section
                if let context = errorContext {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("오류 정보")
                                .font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "작업", value: context.operation)
                            InfoRow(label: "프로그램", value: context.programName)
                            InfoRow(label: "파일 경로", value: context.programPath)
                            InfoRow(label: "워크스페이스", value: context.workspaceName)
                            InfoRow(label: "발생 시간", value: formatTimestamp(context.timestamp))
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }

                // Detailed logs section
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.secondary)
                        Text("상세 로그")
                            .font(.headline)
                    }

                    if program.output.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("로그가 비어있습니다.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)

                            Text("가능한 원인:")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Wine이 제대로 설치되지 않았을 수 있습니다")
                                Text("• 실행 파일에 실행 권한이 없을 수 있습니다")
                                Text("• 파일 경로가 올바르지 않을 수 있습니다")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(program.output.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .foregroundColor(
                                            line.lowercased().contains("error") ||
                                            line.lowercased().contains("failed") ? .red : .primary
                                        )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        }
                        .frame(height: 300)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }
            .padding()
        }
        .frame(maxHeight: .infinity)
        .environment(\.locale, Locale(identifier: "ko_KR"))
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch phase {
        case .installing:
            // No actions during installation
            EmptyView()

        case .scanning:
            // No actions during scanning
            EmptyView()

        case .programsFound:
            // Actions are in ProgramSelectionView
            EmptyView()

        case .noProgramsFound, .error:
            Button("완료") {
                onComplete([])
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Computed Properties

    private var phaseTitle: String {
        switch phase {
        case .installing:
            return "설치 중"
        case .scanning:
            return "프로그램 검색 중"
        case .programsFound:
            return "프로그램 발견"
        case .noProgramsFound:
            return "완료"
        case .error:
            return "오류"
        }
    }

    private var phaseDescription: String {
        switch phase {
        case .installing:
            return "\(program.name) 설치가 진행 중입니다..."
        case .scanning:
            return "설치된 프로그램을 검색하고 있습니다..."
        case .programsFound:
            return "\(discoveredPrograms.count)개의 프로그램을 발견했습니다."
        case .noProgramsFound:
            return "설치가 완료되었습니다."
        case .error:
            return "설치 중 오류가 발생했습니다."
        }
    }

    private var phaseStatusText: String {
        switch phase {
        case .installing:
            return "설치 중..."
        case .scanning:
            return "검색 중..."
        case .programsFound:
            return "완료"
        case .noProgramsFound:
            return "완료"
        case .error:
            return "실패"
        }
    }

    private var phaseIndicatorColor: Color {
        switch phase {
        case .installing, .scanning:
            return .blue
        case .programsFound, .noProgramsFound:
            return .green
        case .error:
            return .red
        }
    }

    // MARK: - Installation Logic

    /// Starts the installation process
    private func startInstallation() async {
        phase = .installing
        currentOperation = "설치 파일 '\(program.name)' 실행 중"

        do {
            try await program.run(in: workspace)
        } catch {
            await MainActor.run {
                errorContext = ErrorContext(
                    operation: currentOperation,
                    programName: program.name,
                    programPath: program.url.path,
                    workspaceName: workspace.settings.name,
                    timestamp: Date()
                )
                phase = .error
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Handles installation completion and triggers program scanning
    private func handleInstallationComplete(exitCode: Int32) {
        Task {
            if exitCode == 0 {
                // Installation successful - scan for programs
                currentOperation = "설치된 프로그램 검색 중"
                await scanForPrograms()
            } else {
                // Installation failed
                await MainActor.run {
                    errorContext = ErrorContext(
                        operation: currentOperation,
                        programName: program.name,
                        programPath: program.url.path,
                        workspaceName: workspace.settings.name,
                        timestamp: Date()
                    )
                    phase = .error
                    errorMessage = "설치 과정에서 문제가 발생했습니다. 아래 상세 로그를 확인해주세요."
                }
            }
        }
    }

    /// Scans for newly installed programs
    private func scanForPrograms() async {
        await MainActor.run {
            currentOperation = "설치된 프로그램 검색 중"
            phase = .scanning
        }

        do {
            let programs = try await ProgramScanner.scanForNewPrograms(in: workspace)

            await MainActor.run {
                discoveredPrograms = programs

                if programs.isEmpty {
                    phase = .noProgramsFound
                } else {
                    phase = .programsFound
                }
            }
        } catch {
            await MainActor.run {
                errorContext = ErrorContext(
                    operation: currentOperation,
                    programName: program.name,
                    programPath: program.url.path,
                    workspaceName: workspace.settings.name,
                    timestamp: Date()
                )
                phase = .error
                errorMessage = "프로그램 검색 실패: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Helper Methods

    /// Formats a timestamp for display
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }
}

// MARK: - Error Context

/// Contains detailed context about where and why an error occurred
private struct ErrorContext {
    /// The operation that was being performed
    let operation: String

    /// Name of the program being installed
    let programName: String

    /// Full file path to the installer
    let programPath: String

    /// Name of the workspace
    let workspaceName: String

    /// When the error occurred
    let timestamp: Date
}

// MARK: - Installation Phase

/// Represents the current phase of the installation process
private enum InstallationPhase {
    /// Currently running the installer
    case installing

    /// Scanning for installed programs
    case scanning

    /// Programs were found - showing selection UI
    case programsFound

    /// No programs found but installation succeeded
    case noProgramsFound

    /// Installation or scanning failed
    case error
}

// MARK: - Helper Views

/// A row displaying a label and value in a consistent format
private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(label):")
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Preview

#Preview("Installing") {
    let workspace = Workspace.preview
    let program = Program(
        name: "Notepad++ Installer",
        url: URL(fileURLWithPath: "/Users/test/Downloads/npp.8.6.Installer.exe")
    )

    return InstallationProgressView(
        program: program,
        workspace: workspace,
        onComplete: { programs in
            print("Completed with \(programs.count) programs")
        }
    )
}

#Preview("Scanning") {
    let workspace = Workspace.preview
    let program = Program(
        name: "Steam Installer",
        url: URL(fileURLWithPath: "/Users/test/Downloads/SteamSetup.exe")
    )

    return InstallationProgressView(
        program: program,
        workspace: workspace,
        onComplete: { _ in }
    )
}
