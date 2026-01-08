import Foundation
import OSLog

/// Parses Windows .lnk (shortcut) files to extract target executable paths
public struct ShortcutParser {
    private static let logger = Logger.sojuKit

    /// Attempts to parse a Windows .lnk file and return the target executable URL
    ///
    /// This implementation uses a simplified approach:
    /// 1. Scans nearby directories for .exe files
    /// 2. Returns the .lnk URL itself if no executable found
    ///
    /// A more robust implementation could:
    /// - Parse the binary .lnk format (complex, requires understanding LNK structure)
    /// - Use Wine's `winepath` utility to resolve shortcuts
    ///
    /// - Parameters:
    ///   - lnkURL: URL to the .lnk shortcut file
    ///   - winePrefixURL: Wine prefix URL (drive_c directory)
    /// - Returns: URL to the target executable, or nil if parsing failed
    public static func parseShortcut(_ lnkURL: URL, winePrefixURL: URL) async throws -> URL? {
        guard lnkURL.pathExtension.lowercased() == "lnk" else {
            logger.warning("Not a .lnk file: \(lnkURL.path)")
            return nil
        }

        guard FileManager.default.fileExists(atPath: lnkURL.path) else {
            logger.warning("Shortcut file not found: \(lnkURL.path)")
            return nil
        }

        logger.debug("Parsing shortcut: \(lnkURL.lastPathComponent)")

        // Strategy 1: Try to find executable in the same directory
        let parentDirectory = lnkURL.deletingLastPathComponent()
        if let nearbyExecutable = try? findExecutableInDirectory(parentDirectory) {
            logger.info("Found executable near shortcut: \(nearbyExecutable.lastPathComponent)")
            return nearbyExecutable
        }

        // Strategy 2: Try to find executable in common installation paths
        let programName = lnkURL.deletingPathExtension().lastPathComponent
        if let executable = try? findExecutableByName(programName, winePrefixURL: winePrefixURL) {
            logger.info("Found executable by name search: \(executable.lastPathComponent)")
            return executable
        }

        // Strategy 3: Return the .lnk file itself as fallback
        logger.debug("Could not resolve shortcut target, returning .lnk URL")
        return lnkURL
    }

    // MARK: - Private Helpers

    /// Searches for an executable file in the given directory (non-recursive)
    private static func findExecutableInDirectory(_ directory: URL) throws -> URL? {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )

        return contents.first { url in
            url.pathExtension.lowercased() == "exe" &&
            !InstallerDetector.isUninstaller(url)
        }
    }

    /// Searches for an executable by name in common Wine installation paths
    private static func findExecutableByName(_ name: String, winePrefixURL: URL) throws -> URL? {
        // Use system username or fallback to "wine"
        let username = NSUserName()

        let searchPaths = [
            "Program Files/\(name)",
            "Program Files (x86)/\(name)",
            "users/\(username)/AppData/Local/\(name)"
        ]

        let fileManager = FileManager.default

        for searchPath in searchPaths {
            let directoryURL = winePrefixURL.appendingPathComponent(searchPath)

            guard fileManager.fileExists(atPath: directoryURL.path) else {
                continue
            }

            // Scan this directory for .exe files (depth 1)
            if let executable = try? scanDirectoryForExecutable(directoryURL, maxDepth: 1) {
                return executable
            }
        }

        return nil
    }

    /// Recursively scans a directory for executable files up to maxDepth
    private static func scanDirectoryForExecutable(_ directory: URL, maxDepth: Int, currentDepth: Int = 0) throws -> URL? {
        guard currentDepth <= maxDepth else { return nil }

        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        // First, check for executables in current directory
        for url in contents {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else {
                continue
            }

            if resourceValues.isRegularFile == true,
               url.pathExtension.lowercased() == "exe",
               !InstallerDetector.isUninstaller(url) {
                return url
            }
        }

        // Then recurse into subdirectories
        if currentDepth < maxDepth {
            for url in contents {
                guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]) else {
                    continue
                }

                if resourceValues.isDirectory == true {
                    if let found = try scanDirectoryForExecutable(url, maxDepth: maxDepth, currentDepth: currentDepth + 1) {
                        return found
                    }
                }
            }
        }

        return nil
    }
}
