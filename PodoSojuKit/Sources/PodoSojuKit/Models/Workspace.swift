//
//  Workspace.swift
//  PodoSojuKit
//
//  Created on 2026-01-07.
//

import Foundation
import SwiftUI
import AppKit
import ApplicationServices
import CoreGraphics
import os.log

public final class Workspace: ObservableObject, Equatable, Hashable, Identifiable, Comparable, @unchecked Sendable {
    // MARK: - Properties

    /// Workspace directory URL
    public let url: URL

    /// Metadata file URL
    public let metadataURL: URL

    /// Workspace settings
    @Published public var settings: WorkspaceSettings {
        didSet { saveSettings() }
    }

    /// Running programs in this workspace
    @Published public var programs: [Program] = []

    /// Whether workspace is currently running
    @Published public var isRunning: Bool = false

    /// Whether workspace is available (metadata exists)
    public var isAvailable: Bool = false

    /// Running program URLs - used to prevent duplicate launches and focus existing windows
    /// Key: URL path (lowercased), Value: NSRunningApplication PID
    @Published public var runningProgramPIDs: [String: pid_t] = [:]

    /// Lock for thread-safe access to runningProgramPIDs
    private let runningLock = NSLock()

    // MARK: - Computed Properties

    /// Wine prefix URL (drive_c directory)
    public var winePrefixURL: URL {
        return url.appending(path: "drive_c")
    }

    /// Wine prefix path as String
    public var winePrefixPath: String {
        return url.path(percentEncoded: false)
    }

    /// Programs folder URL for portable executables
    public var programsURL: URL {
        return url.appending(path: "Programs")
    }

    // MARK: - Initialization

    public init(workspaceUrl: URL, isRunning: Bool = false, isAvailable: Bool = false) {
        let metadataURL = workspaceUrl
            .appending(path: "Metadata")
            .appendingPathExtension("plist")

        self.url = workspaceUrl
        self.isRunning = isRunning
        self.isAvailable = isAvailable
        self.metadataURL = metadataURL

        do {
            self.settings = try WorkspaceSettings.decode(from: metadataURL)
        } catch {
            Logger.podoSojuKit.error(
                "Failed to load settings for workspace `\(metadataURL.path(percentEncoded: false))`: \(error)"
            )
            self.settings = WorkspaceSettings()
        }
    }

    // MARK: - Methods

    /// Save workspace settings to disk
    private func saveSettings() {
        do {
            try settings.encode(to: self.metadataURL)
        } catch {
            Logger.podoSojuKit.error(
                "Failed to encode settings for workspace `\(self.metadataURL.path(percentEncoded: false))`: \(error)"
            )
        }
    }

    /// Get Wine environment variables for this workspace
    public func wineEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = winePrefixPath

        // Add workspace-specific environment variables
        settings.environmentVariables(wineEnv: &env)

        return env
    }

    // MARK: - Running Program Management

    /// Check if a program is already running
    /// - Parameter url: Program URL to check
    /// - Returns: true if program is running
    public func isProgramRunning(_ url: URL) -> Bool {
        runningLock.lock()
        defer { runningLock.unlock() }

        let key = url.path.lowercased()
        guard let pid = runningProgramPIDs[key] else {
            return false
        }

        // Verify the process is still running
        if let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
            return true
        }

        // Process no longer running, clean up
        runningProgramPIDs.removeValue(forKey: key)
        return false
    }

    /// Register a program as running
    /// - Parameters:
    ///   - url: Program URL
    ///   - pid: Process ID (optional, for Wine we may not have direct PID)
    public func registerRunningProgram(_ url: URL, pid: pid_t? = nil) {
        runningLock.lock()
        defer { runningLock.unlock() }

        let key = url.path.lowercased()
        // Use 0 as placeholder PID when actual PID is not available
        runningProgramPIDs[key] = pid ?? 0
        Logger.podoSojuKit.info("Registered running program: \(url.lastPathComponent)", category: "Workspace")
    }

    /// Unregister a program when it exits
    /// - Parameter url: Program URL
    public func unregisterRunningProgram(_ url: URL) {
        runningLock.lock()
        defer { runningLock.unlock() }

        let key = url.path.lowercased()
        runningProgramPIDs.removeValue(forKey: key)
        Logger.podoSojuKit.info("Unregistered running program: \(url.lastPathComponent)", category: "Workspace")
    }

    /// Focus an existing Wine window using CGWindowList API
    /// - Parameter url: Program URL
    /// - Returns: true if window was focused, false if not found
    @MainActor
    public func focusRunningProgram(_ url: URL) -> Bool {
        // 프로그램 이름 추출 (확장자 제외, 소문자)
        let programName = url.deletingPathExtension().lastPathComponent.lowercased()
        Logger.podoSojuKit.info("🔍 focusRunningProgram: \(programName)", category: "Workspace")

        // CGWindowList로 모든 창 가져오기
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            Logger.podoSojuKit.warning("⚠️ Failed to get window list", category: "Workspace")
            return false
        }

        // Wine 관련 프로세스 PID 수집
        let wineProcessNames = ["wine64", "wine", "wineserver", "winedevice", "start.exe", "explorer.exe"]
        var winePIDs: Set<pid_t> = []

        for app in NSWorkspace.shared.runningApplications {
            let exeName = app.executableURL?.lastPathComponent.lowercased() ?? ""
            let appName = app.localizedName?.lowercased() ?? ""

            if wineProcessNames.contains(where: { exeName.contains($0) || appName.contains($0) }) {
                winePIDs.insert(app.processIdentifier)
            }
        }

        // pgrep으로 추가 Wine 프로세스 찾기
        if let pgrepPIDs = getWinePIDsFromPgrep() {
            winePIDs.formUnion(pgrepPIDs)
        }

        Logger.podoSojuKit.debug("Found Wine PIDs: \(winePIDs)", category: "Workspace")

        // 창 목록에서 Wine 창 찾기
        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }

            // windowName은 nil일 수 있음 (Wine 창은 kCGWindowName이 nil인 경우가 많음)
            let windowName = windowInfo[kCGWindowName as String] as? String
            let windowNameLower = windowName?.lowercased() ?? ""

            // Wine PID인지 확인
            let isWineWindow = winePIDs.contains(ownerPID)

            // 창 제목 매칭 확인
            let titleMatches = !windowNameLower.isEmpty && (
                windowNameLower.contains(programName) ||
                (programName.contains("solitaire") && windowNameLower.contains("solitaire")) ||
                (programName.contains("netfile") && windowNameLower.contains("넷파일"))
            )

            // Wine 창이면 포커스 시도 (제목 매칭 여부와 관계없이)
            if isWineWindow {
                Logger.podoSojuKit.info("🎯 Found Wine window: '\(windowName ?? "(no title)")' (PID: \(ownerPID), titleMatches: \(titleMatches))", category: "Workspace")

                // Accessibility API로 창 활성화
                if let app = NSRunningApplication(processIdentifier: ownerPID) {
                    app.activate(options: [.activateIgnoringOtherApps])

                    // AXUIElement로 창을 앞으로
                    let axApp = AXUIElementCreateApplication(ownerPID)
                    var windowsRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                       let windows = windowsRef as? [AXUIElement] {
                        if let firstWindow = windows.first {
                            AXUIElementPerformAction(firstWindow, kAXRaiseAction as CFString)
                        }
                    }
                    AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, true as CFTypeRef)

                    // 제목이 매칭되면 이 프로그램의 창으로 확정
                    if titleMatches {
                        Logger.podoSojuKit.info("✅ Focused matching Wine window (PID: \(ownerPID))", category: "Workspace")
                        return true
                    }
                    // 제목이 없거나 매칭 안 되면 다른 창 계속 탐색
                }
            }
        }

        // Wine 창은 있지만 제목 매칭 실패 - 계속 대기
        Logger.podoSojuKit.info("⏳ No matching window yet for: \(programName)", category: "Workspace")
        return false
    }

    /// Get Wine process PIDs using pgrep
    private func getWinePIDsFromPgrep() -> Set<pid_t>? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "wine|wineserver|winedevice"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            var pids: Set<pid_t> = []
            for line in output.split(separator: "\n") {
                if let pid = pid_t(line.trimmingCharacters(in: .whitespaces)) {
                    pids.insert(pid)
                }
            }
            return pids.isEmpty ? nil : pids
        } catch {
            return nil
        }
    }

    /// Check if any Wine processes are still running for this workspace
    /// - Returns: true if Wine processes are running
    public func hasRunningWineProcesses() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { app in
            app.localizedName?.lowercased().contains("wine") == true ||
            app.executableURL?.lastPathComponent.lowercased().contains("wine") == true
        }
    }

    // MARK: - Portable Program Management

    /// Error types for portable program operations
    public enum PortableProgramError: LocalizedError {
        case fileNotFound(URL)
        case copyFailed(URL, Error)
        case createDirectoryFailed(URL, Error)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "File not found: \(url.lastPathComponent)"
            case .copyFailed(let url, let error):
                return "Failed to copy \(url.lastPathComponent): \(error.localizedDescription)"
            case .createDirectoryFailed(let url, let error):
                return "Failed to create directory \(url.path): \(error.localizedDescription)"
            }
        }
    }

    /// Copy a portable program to the workspace's Programs folder
    ///
    /// - Parameter sourceURL: The source URL of the portable executable
    /// - Returns: The URL of the copied file in the Programs folder
    /// - Throws: `PortableProgramError` if the operation fails
    ///
    /// # Behavior
    /// - Creates the Programs folder if it doesn't exist
    /// - Overwrites existing files with the same name
    /// - Returns the destination URL of the copied file
    ///
    /// # Example
    /// ```swift
    /// let sourceURL = URL(fileURLWithPath: "/Downloads/MyApp.exe")
    /// let destinationURL = try workspace.copyPortableProgram(from: sourceURL)
    /// // destinationURL: /workspace/Programs/MyApp.exe
    /// ```
    public func copyPortableProgram(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default

        Logger.podoSojuKit.info(
            "Copying portable program: \(sourceURL.lastPathComponent)",
            category: "Workspace"
        )

        // Verify source file exists
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            Logger.podoSojuKit.error(
                "Source file not found: \(sourceURL.path)",
                category: "Workspace"
            )
            throw PortableProgramError.fileNotFound(sourceURL)
        }

        // Create Programs folder if needed
        if !fileManager.fileExists(atPath: programsURL.path) {
            do {
                try fileManager.createDirectory(
                    at: programsURL,
                    withIntermediateDirectories: true
                )
                Logger.podoSojuKit.info(
                    "Created Programs folder: \(programsURL.path)",
                    category: "Workspace"
                )
            } catch {
                Logger.podoSojuKit.error(
                    "Failed to create Programs folder: \(error.localizedDescription)",
                    category: "Workspace"
                )
                throw PortableProgramError.createDirectoryFailed(programsURL, error)
            }
        }

        // Destination URL
        let destinationURL = programsURL.appending(path: sourceURL.lastPathComponent)

        do {
            // Remove existing file if present (overwrite behavior)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
                Logger.podoSojuKit.debug(
                    "Removed existing file: \(destinationURL.lastPathComponent)",
                    category: "Workspace"
                )
            }

            // Copy file
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            Logger.podoSojuKit.info(
                "Copied portable program to: \(destinationURL.path)",
                category: "Workspace"
            )

            return destinationURL
        } catch {
            Logger.podoSojuKit.error(
                "Failed to copy file: \(error.localizedDescription)",
                category: "Workspace"
            )
            throw PortableProgramError.copyFailed(sourceURL, error)
        }
    }

    // MARK: - Stale Program Cleanup

    /// Clean up stale entries in runningProgramPIDs
    /// Call this periodically or when Wine processes are known to have exited
    public func cleanupStaleRunningPrograms() {
        runningLock.lock()
        defer { runningLock.unlock() }

        // If no Wine processes are running, clear all entries
        if !hasRunningWineProcesses() {
            if !runningProgramPIDs.isEmpty {
                Logger.podoSojuKit.info("No Wine processes running, clearing \(runningProgramPIDs.count) stale entries", category: "Workspace")
                runningProgramPIDs.removeAll()
            }
        }
    }

    // MARK: - Equatable

    public static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        return lhs.url == rhs.url
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        return hasher.combine(url)
    }

    // MARK: - Identifiable

    public var id: URL {
        self.url
    }

    // MARK: - Comparable

    public static func < (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.settings.name.lowercased() < rhs.settings.name.lowercased()
    }
}

// MARK: - Program

/// Represents a Windows program that can be executed in a workspace
@MainActor
public class Program: Identifiable, Hashable, ObservableObject, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public let url: URL // Path to .exe file
    public let icon: NSImage?

    /// Whether the program is currently running
    @Published public private(set) var isRunning: Bool = false

    /// Process output stream
    @Published public private(set) var output: [String] = []

    /// Process exit code (nil if still running)
    @Published public private(set) var exitCode: Int32?

    public init(id: UUID = UUID(), name: String, url: URL, icon: NSImage? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.icon = icon
    }

    /// Run this program in the specified workspace
    /// Uses Task.detached to match Whisky's execution context for GUI visibility
    public func run(in workspace: Workspace) async throws {
        let executionId = UUID().uuidString.prefix(8)
        let category = "Program[\(executionId)]"

        Logger.podoSojuKit.info("🚀 Program execution started", category: category)
        Logger.podoSojuKit.debug("Program: \(self.name)", category: category)
        Logger.podoSojuKit.debug("URL: \(self.url.path(percentEncoded: false))", category: category)
        Logger.podoSojuKit.debug("Workspace: \(workspace.settings.name)", category: category)

        // Check if this program is already running - focus instead of launching new instance
        if workspace.isProgramRunning(self.url) {
            Logger.podoSojuKit.info("⚠️ Program already running, attempting to focus", category: category)
            _ = workspace.focusRunningProgram(self.url)
            return
        }

        guard !isRunning else {
            Logger.podoSojuKit.warning("⚠️ Program instance already running, ignoring request", category: category)
            return
        }

        // Register this program as running
        workspace.registerRunningProgram(self.url)

        await MainActor.run {
            self.isRunning = true
            self.exitCode = nil
            self.output = []

            // Add test output to verify the mechanism works
            self.output.append("🧪 Test: Wine execution starting...")
            self.output.append("Program: \(self.name)")
            self.output.append("File: \(self.url.path(percentEncoded: false))")

            Logger.podoSojuKit.debug("✅ Test output added to array, count: \(self.output.count)", category: category)
        }
        Logger.podoSojuKit.debug("✅ State updated: isRunning=true", category: category)

        // Use Task.detached to create independent execution context (Whisky pattern)
        // This is critical for GUI window visibility
        // Program is @unchecked Sendable (same as Whisky)
        try await Task.detached(priority: .userInitiated) { [workspace] in
            do {
                let sojuManager = SojuManager.shared
                Logger.podoSojuKit.debug("📦 SojuManager acquired", category: category)

                // Check if this is an installer - enable verbose Wine debug output
                let isInstaller = InstallerDetector.isInstaller(self.url)
                var additionalEnv: [String: String] = [:]

                // Set exe path for window identification
                additionalEnv["SOJU_EXE_PATH"] = self.url.path(percentEncoded: false)

                if isInstaller {
                    Logger.podoSojuKit.info("🔧 Installer detected - enabling Wine debug output", category: category)
                    additionalEnv["WINEDEBUG"] = "warn+all"
                }

                // Determine Wine arguments based on file type
                // .lnk files require ShortcutParser to extract target exe path
                let wineArgs: [String]
                let fileExtension = self.url.pathExtension.lowercased()

                if fileExtension == "lnk" {
                    // ShortcutParser로 실제 타겟 exe 찾기
                    if let targetURL = try? await ShortcutParser.parseShortcut(self.url, winePrefixURL: workspace.winePrefixURL) {
                        Logger.podoSojuKit.info("📎 Shortcut target found: \(targetURL.path)", category: category)
                        wineArgs = ["start", "/unix", targetURL.path(percentEncoded: false)]
                    } else {
                        // fallback: .lnk 파일 직접 실행
                        Logger.podoSojuKit.warning("📎 Shortcut target not found, using lnk directly", category: category)
                        wineArgs = ["start", "/unix", self.url.path(percentEncoded: false)]
                    }
                } else {
                    // For .exe files, use 'wine start /unix' to handle Unix paths
                    wineArgs = ["start", "/unix", self.url.path(percentEncoded: false)]
                }

                Logger.podoSojuKit.debug("🍷 Wine args: \(wineArgs)", category: category)
                Logger.podoSojuKit.info("🎭 Running in detached task (Whisky pattern)", category: category)

                // Use empty loop to ignore output and just wait for process completion
                // This prevents blocking on 'wine start /unix' which spawns background processes
                // Pattern from Whisky (line 110-114)
                // captureOutput: false prevents pipes from blocking GUI windows
                for await _ in try sojuManager.runWine(
                    args: wineArgs,
                    workspace: workspace,
                    additionalEnv: additionalEnv,
                    captureOutput: false
                ) { }

                Logger.podoSojuKit.info("✅ Wine start command completed", category: category)

                // Set exit code and running state on successful completion (Whisky pattern)
                // This triggers InstallationProgressView.onChange(of: program.exitCode) to advance phase
                await MainActor.run {
                    self.isRunning = false
                    self.exitCode = 0
                }

                // Unregister program when Wine process completes
                workspace.unregisterRunningProgram(self.url)
                Logger.podoSojuKit.info("✅ Program unregistered: \(self.name)", category: category)
            } catch {
                Logger.podoSojuKit.critical("💥 Fatal error: \(error.localizedDescription)", category: category)
                Logger.podoSojuKit.debug("Error details: \(String(reflecting: error))", category: category)

                await MainActor.run {
                    self.isRunning = false
                    self.exitCode = 1
                }

                // Unregister program on error as well
                workspace.unregisterRunningProgram(self.url)

                throw error
            }
        }.value
    }

    // MARK: - Equatable

    nonisolated public static func == (lhs: Program, rhs: Program) -> Bool {
        return lhs.id == rhs.id
    }

    // MARK: - Hashable

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Preview Support

#if DEBUG
extension Workspace {
    public static var preview: Workspace {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewWorkspace")
        let workspace = Workspace(workspaceUrl: tempURL, isRunning: false, isAvailable: true)
        workspace.settings.name = "Preview Workspace"
        workspace.settings.icon = "desktopcomputer"
        return workspace
    }
}
#endif
