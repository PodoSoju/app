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
                    // Progress indicator
                    HStack {
                        ProgressView()
                            .controlSize(.small)

                        Text("Installing \(program.name)...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
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
        VStack(spacing: 20) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            VStack(spacing: 8) {
                Text("설치 실패")
                    .font(.title3)
                    .fontWeight(.medium)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Show installation log
            Divider()
                .padding(.vertical)

            VStack(alignment: .leading, spacing: 8) {
                Text("설치 로그")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(program.output.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
            }
        }
        .frame(maxHeight: .infinity)
        .padding()
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

        do {
            try await program.run(in: workspace)
        } catch {
            await MainActor.run {
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
                await scanForPrograms()
            } else {
                // Installation failed
                await MainActor.run {
                    phase = .error
                    errorMessage = "설치가 종료 코드 \(exitCode)로 실패했습니다."
                }
            }
        }
    }

    /// Scans for newly installed programs
    private func scanForPrograms() async {
        await MainActor.run {
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
                phase = .error
                errorMessage = "프로그램 검색 실패: \(error.localizedDescription)"
            }
        }
    }
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
