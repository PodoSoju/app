import Foundation
import OSLog

/// Scans Wine prefixes for installed programs after installation completes
@MainActor
public class ProgramScanner {
    private static let logger = Logger.podoSojuKit

    // MARK: - Scan Configuration

    /// Maximum directory depth when scanning Program Files
    private static let maxScanDepth = 3

    /// Directories to scan for shortcuts (relative to prefix root)
    private static let shortcutPaths = [
        "drive_c/users/Public/Desktop",
        "drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs"
    ]

    /// Directories to scan for executables (relative to prefix root)
    private static let programFilesPaths = [
        "drive_c/Program Files",
        "drive_c/Program Files (x86)"
    ]

    // MARK: - Public API

    /// Scans the workspace for newly installed programs
    ///
    /// Scan strategy:
    /// 1. Search for .lnk files in Desktop and Start Menu
    /// 2. Search for .exe files in Program Files directories
    /// 3. Filter out uninstallers and system files
    /// 4. Parse shortcuts to resolve target executables
    ///
    /// - Parameter workspace: The workspace to scan
    /// - Returns: Array of discovered programs
    /// - Throws: File system errors during scanning
    public static func scanForNewPrograms(in workspace: Workspace) async throws -> [DiscoveredProgram] {
        logger.info("Starting program scan in workspace: \(workspace.settings.name)")

        var discoveredPrograms: [DiscoveredProgram] = []

        // Phase 1: Scan for shortcuts
        let shortcuts = try await scanForShortcuts(in: workspace)
        logger.debug("Found \(shortcuts.count) shortcuts")

        // Extract winePrefixURL to avoid data race
        let winePrefixURL = workspace.winePrefixURL

        for shortcut in shortcuts {
            // Try to resolve shortcut to executable
            if let targetURL = try? await ShortcutParser.parseShortcut(shortcut, winePrefixURL: winePrefixURL) {
                let programName = extractProgramName(from: shortcut)
                let program = DiscoveredProgram(
                    name: programName,
                    url: targetURL,
                    isFromShortcut: true
                )
                discoveredPrograms.append(program)
                logger.debug("Discovered program from shortcut: \(programName)")
            }
        }

        // Phase 2: Scan for executables in Program Files
        let executables = try await scanForExecutables(in: workspace)
        logger.debug("Found \(executables.count) executables")

        for executable in executables {
            // Skip if already discovered via shortcut
            let alreadyDiscovered = discoveredPrograms.contains { program in
                program.url.path == executable.path
            }

            if !alreadyDiscovered {
                let programName = extractProgramName(from: executable)
                let program = DiscoveredProgram(
                    name: programName,
                    url: executable,
                    isFromShortcut: false
                )
                discoveredPrograms.append(program)
                logger.debug("Discovered program from direct scan: \(programName)")
            }
        }

        logger.info("Program scan complete: discovered \(discoveredPrograms.count) programs")
        return discoveredPrograms
    }

    // MARK: - Private Scan Methods

    /// Scans for .lnk shortcut files in Desktop and Start Menu
    private static func scanForShortcuts(in workspace: Workspace) async throws -> [URL] {
        var shortcuts: [URL] = []

        for relativePath in shortcutPaths {
            let directoryURL = workspace.winePrefixURL.appendingPathComponent(relativePath)

            guard FileManager.default.fileExists(atPath: directoryURL.path) else {
                logger.debug("Shortcut directory not found: \(relativePath)")
                continue
            }

            let foundShortcuts = try scanDirectoryRecursively(
                directoryURL,
                fileExtension: "lnk",
                maxDepth: 5
            )
            shortcuts.append(contentsOf: foundShortcuts)
        }

        return shortcuts
    }

    /// Scans for .exe executable files in Program Files directories
    private static func scanForExecutables(in workspace: Workspace) async throws -> [URL] {
        var executables: [URL] = []

        for relativePath in programFilesPaths {
            let directoryURL = workspace.winePrefixURL.appendingPathComponent(relativePath)

            guard FileManager.default.fileExists(atPath: directoryURL.path) else {
                logger.debug("Program Files directory not found: \(relativePath)")
                continue
            }

            let foundExecutables = try scanDirectoryRecursively(
                directoryURL,
                fileExtension: "exe",
                maxDepth: maxScanDepth
            )

            // Filter out uninstallers and system files
            let validExecutables = foundExecutables.filter { url in
                !InstallerDetector.isUninstaller(url)
            }

            executables.append(contentsOf: validExecutables)
        }

        return executables
    }

    // MARK: - File System Utilities

    /// Recursively scans a directory for files with a specific extension
    ///
    /// - Parameters:
    ///   - directory: Directory to scan
    ///   - fileExtension: File extension to match (e.g., "exe", "lnk")
    ///   - maxDepth: Maximum recursion depth
    ///   - currentDepth: Current recursion depth (internal)
    /// - Returns: Array of matching file URLs
    private static func scanDirectoryRecursively(
        _ directory: URL,
        fileExtension: String,
        maxDepth: Int,
        currentDepth: Int = 0
    ) throws -> [URL] {
        guard currentDepth <= maxDepth else {
            return []
        }

        var results: [URL] = []
        let fileManager = FileManager.default

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for url in contents {
                guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else {
                    continue
                }

                if resourceValues.isRegularFile == true {
                    // Check if file matches extension
                    if url.pathExtension.lowercased() == fileExtension.lowercased() {
                        results.append(url)
                    }
                } else if resourceValues.isDirectory == true, currentDepth < maxDepth {
                    // Recurse into subdirectory
                    let subResults = try scanDirectoryRecursively(
                        url,
                        fileExtension: fileExtension,
                        maxDepth: maxDepth,
                        currentDepth: currentDepth + 1
                    )
                    results.append(contentsOf: subResults)
                }
            }
        } catch {
            // Log error but continue scanning other directories
            logger.warning("Failed to scan directory \(directory.path): \(error.localizedDescription)")
        }

        return results
    }

    /// Extracts a human-readable program name from a file URL
    ///
    /// Strategies:
    /// 1. Remove file extension
    /// 2. Clean up common suffixes (Setup, Installer, Uninstall)
    /// 3. Remove version numbers
    ///
    /// - Parameter url: File URL
    /// - Returns: Cleaned program name
    private static func extractProgramName(from url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent

        // Remove common suffixes
        let suffixesToRemove = [
            " Setup",
            " Installer",
            " Install",
            "Setup",
            "Installer",
            "Install"
        ]

        for suffix in suffixesToRemove {
            if name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        // Remove version numbers (e.g., "App 1.2.3" -> "App")
        if let range = name.range(of: #"\s+\d+(\.\d+)*$"#, options: .regularExpression) {
            name = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        return name.isEmpty ? url.lastPathComponent : name
    }
}
