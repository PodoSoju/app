//
//  Workspace.swift
//  SojuKit
//
//  Created on 2026-01-07.
//

import Foundation
import SwiftUI
import AppKit
import ApplicationServices
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
            Logger.sojuKit.error(
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
            Logger.sojuKit.error(
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
        Logger.sojuKit.info("Registered running program: \(url.lastPathComponent)", category: "Workspace")
    }

    /// Unregister a program when it exits
    /// - Parameter url: Program URL
    public func unregisterRunningProgram(_ url: URL) {
        runningLock.lock()
        defer { runningLock.unlock() }

        let key = url.path.lowercased()
        runningProgramPIDs.removeValue(forKey: key)
        Logger.sojuKit.info("Unregistered running program: \(url.lastPathComponent)", category: "Workspace")
    }

    /// Focus an existing Wine window using Accessibility API
    /// - Parameter url: Program URL (unused, focuses any Wine window)
    /// - Returns: true if window was focused, false if not found
    @MainActor
    public func focusRunningProgram(_ url: URL) -> Bool {
        Logger.sojuKit.logWithFile("🔍 focusRunningProgram called", level: .info)

        // Wine 프로세스 찾기
        let wineApps = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName?.lowercased() == "wine"
        }
        Logger.sojuKit.logWithFile("🔍 Wine apps found: \(wineApps.count)", level: .info)

        // 첫 번째 Wine 창 포커스
        for app in wineApps {
            let pid = app.processIdentifier
            let axApp = AXUIElementCreateApplication(pid)

            var windowsRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
            Logger.sojuKit.logWithFile("🔍 PID \(pid): AX result = \(result.rawValue)", level: .info)

            if result == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
                Logger.sojuKit.logWithFile("🔍 Found \(windows.count) windows", level: .info)

                // 모든 창 활성화
                for window in windows {
                    let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    Logger.sojuKit.logWithFile("🔍 AXRaise result: \(raiseResult.rawValue)", level: .info)
                }
                AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, true as CFTypeRef)

                // NSRunningApplication으로도 activate
                app.activate()
                Logger.sojuKit.logWithFile("✅ Focused Wine windows (PID: \(pid))", level: .info)
                return true
            }
        }

        Logger.sojuKit.logWithFile("❌ No Wine windows found", level: .info)
        return false
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

    /// Clean up stale entries in runningProgramPIDs
    /// Call this periodically or when Wine processes are known to have exited
    public func cleanupStaleRunningPrograms() {
        runningLock.lock()
        defer { runningLock.unlock() }

        // If no Wine processes are running, clear all entries
        if !hasRunningWineProcesses() {
            if !runningProgramPIDs.isEmpty {
                Logger.sojuKit.info("No Wine processes running, clearing \(runningProgramPIDs.count) stale entries", category: "Workspace")
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

        Logger.sojuKit.info("🚀 Program execution started", category: category)
        Logger.sojuKit.debug("Program: \(self.name)", category: category)
        Logger.sojuKit.debug("URL: \(self.url.path(percentEncoded: false))", category: category)
        Logger.sojuKit.debug("Workspace: \(workspace.settings.name)", category: category)

        // Check if this program is already running - focus instead of launching new instance
        if workspace.isProgramRunning(self.url) {
            Logger.sojuKit.info("⚠️ Program already running, attempting to focus", category: category)
            _ = await workspace.focusRunningProgram(self.url)
            return
        }

        guard !isRunning else {
            Logger.sojuKit.warning("⚠️ Program instance already running, ignoring request", category: category)
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

            Logger.sojuKit.debug("✅ Test output added to array, count: \(self.output.count)", category: category)
        }
        Logger.sojuKit.debug("✅ State updated: isRunning=true", category: category)

        // Use Task.detached to create independent execution context (Whisky pattern)
        // This is critical for GUI window visibility
        // Program is @unchecked Sendable (same as Whisky)
        try await Task.detached(priority: .userInitiated) { [workspace] in
            do {
                let podoSoju = PodoSojuManager.shared
                Logger.sojuKit.debug("📦 PodoSojuManager acquired", category: category)

                // Check if this is an installer - enable verbose Wine debug output
                let isInstaller = InstallerDetector.isInstaller(self.url)
                var additionalEnv: [String: String] = [:]

                if isInstaller {
                    Logger.sojuKit.info("🔧 Installer detected - enabling Wine debug output", category: category)
                    additionalEnv["WINEDEBUG"] = "warn+all"
                }

                // Determine Wine arguments based on file type
                // .lnk files require ShortcutParser to extract target exe path
                let wineArgs: [String]
                let fileExtension = self.url.pathExtension.lowercased()

                if fileExtension == "lnk" {
                    // ShortcutParser로 실제 타겟 exe 찾기
                    if let targetURL = try? await ShortcutParser.parseShortcut(self.url, winePrefixURL: workspace.winePrefixURL) {
                        Logger.sojuKit.info("📎 Shortcut target found: \(targetURL.path)", category: category)
                        wineArgs = ["start", "/unix", targetURL.path(percentEncoded: false)]
                    } else {
                        // fallback: .lnk 파일 직접 실행
                        Logger.sojuKit.warning("📎 Shortcut target not found, using lnk directly", category: category)
                        wineArgs = ["start", "/unix", self.url.path(percentEncoded: false)]
                    }
                } else {
                    // For .exe files, use 'wine start /unix' to handle Unix paths
                    wineArgs = ["start", "/unix", self.url.path(percentEncoded: false)]
                }

                Logger.sojuKit.debug("🍷 Wine args: \(wineArgs)", category: category)
                Logger.sojuKit.info("🎭 Running in detached task (Whisky pattern)", category: category)

                // Use empty loop to ignore output and just wait for process completion
                // This prevents blocking on 'wine start /unix' which spawns background processes
                // Pattern from Whisky (line 110-114)
                // captureOutput: false prevents pipes from blocking GUI windows
                for await _ in try podoSoju.runWine(
                    args: wineArgs,
                    workspace: workspace,
                    additionalEnv: additionalEnv,
                    captureOutput: false
                ) { }

                Logger.sojuKit.info("✅ Wine start command completed", category: category)

                // Set exit code and running state on successful completion (Whisky pattern)
                // This triggers InstallationProgressView.onChange(of: program.exitCode) to advance phase
                await MainActor.run {
                    self.isRunning = false
                    self.exitCode = 0
                }

                // Unregister program when Wine process completes
                workspace.unregisterRunningProgram(self.url)
                Logger.sojuKit.info("✅ Program unregistered: \(self.name)", category: category)
            } catch {
                Logger.sojuKit.critical("💥 Fatal error: \(error.localizedDescription)", category: category)
                Logger.sojuKit.debug("Error details: \(String(reflecting: error))", category: category)

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
