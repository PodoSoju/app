import Foundation
import OSLog

/// Parsed shortcut information
public struct ParsedShortcut {
    /// Target path from the shortcut (Windows path format)
    public let targetPath: String?
    /// Working directory
    public let workingDirectory: String?
    /// Command line arguments
    public let arguments: String?
    /// Icon location
    public let iconLocation: String?
}

/// Parses Windows .lnk (shortcut) files to extract target executable paths
public struct ShortcutParser {
    private static let logger = Logger.sojuKit

    // LNK file signature
    private static let lnkSignature: [UInt8] = [0x4C, 0x00, 0x00, 0x00]

    /// Parse a .lnk file and extract shortcut information
    /// - Parameter url: URL to the .lnk file
    /// - Returns: ParsedShortcut with target path and other info, or nil if parsing fails
    public static func parse(_ url: URL) -> ParsedShortcut? {
        guard url.pathExtension.lowercased() == "lnk" else {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            logger.debug("Failed to read .lnk file: \(url.lastPathComponent)", category: "ShortcutParser")
            return nil
        }

        guard data.count > 76 else {
            logger.debug("LNK file too small: \(url.lastPathComponent)", category: "ShortcutParser")
            return nil
        }

        // Verify LNK signature
        let signature = Array(data[0..<4])
        guard signature == lnkSignature else {
            logger.debug("Invalid LNK signature: \(url.lastPathComponent)", category: "ShortcutParser")
            return nil
        }

        // Read link flags at offset 0x14 (20)
        let linkFlags = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0x14, as: UInt32.self) }

        let hasLinkTargetIDList = (linkFlags & 0x01) != 0
        let hasLinkInfo = (linkFlags & 0x02) != 0
        let hasName = (linkFlags & 0x04) != 0
        let hasRelativePath = (linkFlags & 0x08) != 0
        let hasWorkingDir = (linkFlags & 0x10) != 0
        let hasArguments = (linkFlags & 0x20) != 0
        let hasIconLocation = (linkFlags & 0x40) != 0

        var offset = 76 // Shell Link Header size

        // Skip Shell Link Target ID List if present
        if hasLinkTargetIDList {
            guard offset + 2 <= data.count else { return nil }
            let idListSize = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
            offset += 2 + Int(idListSize)
        }

        var targetPath: String?

        // Parse Link Info if present
        if hasLinkInfo {
            guard offset + 4 <= data.count else { return nil }
            let linkInfoSize = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            
            // Validate linkInfoSize - must be at least 28 bytes for valid LinkInfo structure
            // and should not exceed remaining data
            let linkInfoSizeInt = Int(linkInfoSize)
            guard linkInfoSizeInt >= 28,
                  offset + linkInfoSizeInt <= data.count else {
                logger.debug("Invalid or truncated LinkInfo (size=\(linkInfoSize)): skipping", category: "ShortcutParser")
                // Try to skip the LinkInfo section if size seems valid
                if linkInfoSizeInt > 0 && linkInfoSizeInt < 1_000_000 {
                    offset += linkInfoSizeInt
                } else {
                    // Cannot determine valid size, abort parsing
                    return ParsedShortcut(
                        targetPath: nil,
                        workingDirectory: nil,
                        arguments: nil,
                        iconLocation: nil
                    )
                }
                // Continue with remaining sections
                return ParsedShortcut(
                    targetPath: nil,
                    workingDirectory: nil,
                    arguments: nil,
                    iconLocation: nil
                )
            }

            // Extract local base path if present - now safe because linkInfoSize >= 28
            let linkInfoFlags = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self) }
            let hasVolumeIDAndLocalBasePath = (linkInfoFlags & 0x01) != 0

            if hasVolumeIDAndLocalBasePath {
                // Verify localBasePathOffset is within bounds
                guard offset + 20 <= data.count else {
                    offset += linkInfoSizeInt
                    return ParsedShortcut(targetPath: nil, workingDirectory: nil, arguments: nil, iconLocation: nil)
                }
                let localBasePathOffset = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 16, as: UInt32.self) }
                let pathStart = offset + Int(localBasePathOffset)
                // Validate pathStart is within LinkInfo bounds and data bounds
                if pathStart >= offset && pathStart < offset + linkInfoSizeInt && pathStart < data.count {
                    targetPath = readNullTerminatedString(from: data, at: pathStart)
                }
            }

            offset += linkInfoSizeInt
        }

        var workingDir: String?
        var arguments: String?
        var iconLocation: String?

        // Read string data
        if hasName {
            let (_, newOffset) = readUnicodeString(from: data, at: offset)
            offset = newOffset
        }

        if hasRelativePath {
            let (relativePath, newOffset) = readUnicodeString(from: data, at: offset)
            offset = newOffset
            // If we don't have a target path yet, use relative path
            if targetPath == nil && relativePath != nil {
                targetPath = relativePath
            }
        }

        if hasWorkingDir {
            let (dir, newOffset) = readUnicodeString(from: data, at: offset)
            offset = newOffset
            workingDir = dir
        }

        if hasArguments {
            let (args, newOffset) = readUnicodeString(from: data, at: offset)
            offset = newOffset
            arguments = args
        }

        if hasIconLocation {
            let (icon, _) = readUnicodeString(from: data, at: offset)
            iconLocation = icon
        }

        logger.debug("Parsed shortcut \(url.lastPathComponent): target=\(targetPath ?? "nil")", category: "ShortcutParser")

        return ParsedShortcut(
            targetPath: targetPath,
            workingDirectory: workingDir,
            arguments: arguments,
            iconLocation: iconLocation
        )
    }

    /// Resolve a Windows path to a macOS URL within a Wine prefix
    /// - Parameters:
    ///   - targetPath: Windows path (e.g., "C:\\Program Files\\App\\app.exe")
    ///   - prefixURL: Wine prefix URL (points to drive_c directory)
    /// - Returns: Resolved macOS URL, or nil if resolution fails
    public static func resolveTargetURL(targetPath: String, prefixURL: URL) -> URL? {
        // Convert Windows path separators
        var path = targetPath.replacingOccurrences(of: "\\", with: "/")

        // Handle drive letters (C:, D:, etc.)
        if path.count >= 2 && path[path.index(path.startIndex, offsetBy: 1)] == ":" {
            let driveLetter = path.prefix(1).lowercased()
            path = String(path.dropFirst(2)) // Remove "C:"

            // Map drive letter to Wine prefix
            // C: -> drive_c, D: -> dosdevices/d:, etc.
            let resolvedURL: URL
            if driveLetter == "c" {
                resolvedURL = prefixURL.appendingPathComponent(path)
            } else {
                // For other drives, check dosdevices
                let parentPrefix = prefixURL.deletingLastPathComponent()
                let drivePath = parentPrefix.appendingPathComponent("dosdevices/\(driveLetter):")
                resolvedURL = drivePath.appendingPathComponent(path)
            }

            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                return resolvedURL
            }
        }

        // Try as relative path
        let relativeURL = prefixURL.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: relativeURL.path) {
            return relativeURL
        }

        return nil
    }

    // MARK: - LNK Parsing Helpers

    private static func readNullTerminatedString(from data: Data, at offset: Int) -> String? {
        var endIndex = offset
        while endIndex < data.count && data[endIndex] != 0 {
            endIndex += 1
        }
        guard endIndex > offset else { return nil }
        return String(data: data[offset..<endIndex], encoding: .windowsCP1252)
            ?? String(data: data[offset..<endIndex], encoding: .utf8)
    }

    private static func readUnicodeString(from data: Data, at offset: Int) -> (String?, Int) {
        guard offset + 2 <= data.count else { return (nil, offset) }
        let charCount = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
        let byteCount = Int(charCount) * 2
        let stringStart = offset + 2
        let stringEnd = stringStart + byteCount

        guard stringEnd <= data.count else { return (nil, offset + 2) }

        let stringData = data[stringStart..<stringEnd]
        let string = String(data: stringData, encoding: .utf16LittleEndian)

        return (string, stringEnd)
    }

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

        // Strategy 1: Parse the .lnk binary format to get the actual target
        if let shortcut = parse(lnkURL),
           let targetPath = shortcut.targetPath,
           let resolvedURL = resolveTargetURL(targetPath: targetPath, prefixURL: winePrefixURL) {
            logger.info("Resolved shortcut target: \(resolvedURL.lastPathComponent)")
            return resolvedURL
        }

        // Strategy 2: Try to find executable in the same directory
        let parentDirectory = lnkURL.deletingLastPathComponent()
        if let nearbyExecutable = try? findExecutableInDirectory(parentDirectory) {
            logger.info("Found executable near shortcut: \(nearbyExecutable.lastPathComponent)")
            return nearbyExecutable
        }

        // Strategy 3: Try to find executable in common installation paths
        let programName = lnkURL.deletingPathExtension().lastPathComponent
        if let executable = try? findExecutableByName(programName, winePrefixURL: winePrefixURL) {
            logger.info("Found executable by name search: \(executable.lastPathComponent)")
            return executable
        }

        // Strategy 4: Return the .lnk file itself as fallback
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
