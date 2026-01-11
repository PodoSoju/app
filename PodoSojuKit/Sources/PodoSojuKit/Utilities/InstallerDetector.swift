//
//  InstallerDetector.swift
//  PodoSojuKit
//
//  Created on 2026-01-08.
//

import Foundation
import os.log

/// Utility for detecting and extracting information from installer executables
///
/// `InstallerDetector` provides methods to identify Windows installer files
/// and extract program names from installer filenames.
///
/// # Detection Logic
/// - First checks filename keywords (fast)
/// - Falls back to file signature detection using macOS `file` command (accurate)
/// - Excludes uninstallers with keywords: "uninstall", "unins"
/// - Case-insensitive matching against filename (without extension)
///
/// # Example
/// ```swift
/// let url = URL(fileURLWithPath: "/path/to/NetFile_Setup.exe")
///
/// if InstallerDetector.isInstaller(url) {
///     let programName = InstallerDetector.installerName(from: url)
///     print("Detected installer for: \(programName)") // "NetFile"
/// }
/// ```
public struct InstallerDetector {

    // MARK: - Constants

    /// Keywords that indicate an installer file (case-insensitive)
    private static let installerKeywords = ["setup", "install", "installer"]

    /// Keywords that indicate an uninstaller file (case-insensitive)
    private static let excludeKeywords = ["uninstall", "unins"]

    /// Wine system paths that typically contain stub programs
    private static let wineSystemPaths = [
        "windows/system32",
        "Windows Media Player",
        "Internet Explorer",
        "windows/command"
    ]

    /// Maximum file size for Wine stub detection (50KB)
    private static let wineStubMaxSize: Int64 = 50_000

    /// Known installer signatures detected by `file` command
    private static let installerSignatures = [
        "nullsoft installer",
        "inno setup",
        "installshield",
        "wise installer",
        "msi installer",
        "windows installer"
    ]

    // MARK: - Public API

    /// Determines if the given file URL points to an uninstaller executable
    ///
    /// - Parameter url: The file URL to check
    /// - Returns: `true` if the file is detected as an uninstaller, `false` otherwise
    ///
    /// # Example
    /// ```swift
    /// let uninstallUrl = URL(fileURLWithPath: "/Programs/unins000.exe")
    /// InstallerDetector.isUninstaller(uninstallUrl) // true
    ///
    /// let appUrl = URL(fileURLWithPath: "/Programs/NetFile.exe")
    /// InstallerDetector.isUninstaller(appUrl) // false
    /// ```
    public static func isUninstaller(_ url: URL) -> Bool {
        let filename = url.deletingPathExtension().lastPathComponent.lowercased()

        // Check for uninstaller keywords
        for keyword in excludeKeywords {
            if filename.contains(keyword) {
                Logger.podoSojuKit.debug(
                    "File contains uninstaller keyword '\(keyword)': is uninstaller",
                    category: "InstallerDetector"
                )
                return true
            }
        }

        return false
    }

    /// Determines if the given file URL points to a Wine stub program
    ///
    /// Wine stub programs are placeholder executables that either do nothing
    /// or provide minimal functionality. These are not useful to display as shortcuts.
    ///
    /// Detection strategy:
    /// 1. Only check `.exe` files
    /// 2. File must be small (< 50KB)
    /// 3. File must be in a Wine system path
    /// 4. File content must contain "stub" string
    ///
    /// - Parameter url: The file URL to check
    /// - Returns: `true` if the file is detected as a Wine stub program, `false` otherwise
    ///
    /// # Example
    /// ```swift
    /// // Wine stub in system32
    /// let wmplayerUrl = URL(fileURLWithPath: "/prefix/drive_c/windows/system32/wmplayer.exe")
    /// InstallerDetector.isWineStub(wmplayerUrl) // true (if small and contains "stub")
    ///
    /// let gameUrl = URL(fileURLWithPath: "/Programs/MyGame.exe")
    /// InstallerDetector.isWineStub(gameUrl) // false
    /// ```
    public static func isWineStub(_ url: URL) -> Bool {
        // 1. Only check exe files
        guard url.pathExtension.lowercased() == "exe" else {
            return false
        }

        // 2. Check file size - must be under 50KB
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              size < wineStubMaxSize else {
            return false
        }

        // 3. Check if in Wine system path
        let pathLower = url.path.lowercased()
        let isWinePath = wineSystemPaths.contains { pathLower.contains($0.lowercased()) }

        guard isWinePath else {
            return false
        }

        // 4. Check file content for "stub" byte pattern
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            Logger.podoSojuKit.debug(
                "Could not read file content: \(url.lastPathComponent)",
                category: "InstallerDetector"
            )
            return false
        }

        // Search for "stub" byte pattern in binary data
        let stubPattern = "stub".data(using: .ascii)!
        let stubPatternUpper = "STUB".data(using: .ascii)!
        let containsStub = data.range(of: stubPattern) != nil || data.range(of: stubPatternUpper) != nil

        if containsStub {
            Logger.podoSojuKit.debug(
                "File '\(url.lastPathComponent)' is a Wine stub program (size: \(size) bytes)",
                category: "InstallerDetector"
            )
        }

        return containsStub
    }

    /// Determines if the given file URL points to an installer executable
    ///
    /// Uses a two-stage detection strategy:
    /// 1. Fast filename keyword check (returns immediately if match found)
    /// 2. Accurate file signature check using macOS `file` command (slower but reliable)
    ///
    /// - Parameter url: The file URL to check
    /// - Returns: `true` if the file is detected as an installer, `false` otherwise
    ///
    /// # Example
    /// ```swift
    /// let setupUrl = URL(fileURLWithPath: "/Downloads/NetFile_Setup.exe")
    /// InstallerDetector.isInstaller(setupUrl) // true
    ///
    /// let appUrl = URL(fileURLWithPath: "/Programs/NetFile.exe")
    /// InstallerDetector.isInstaller(appUrl) // false
    ///
    /// let uninstallUrl = URL(fileURLWithPath: "/Programs/unins000.exe")
    /// InstallerDetector.isInstaller(uninstallUrl) // false
    /// ```
    public static func isInstaller(_ url: URL) -> Bool {
        let filename = url.deletingPathExtension().lastPathComponent.lowercased()

        Logger.podoSojuKit.debug(
            "Checking installer status for: \(url.lastPathComponent)",
            category: "InstallerDetector"
        )

        // Stage 1: Check filename (fast)
        // First exclude uninstaller files
        for excludeKeyword in excludeKeywords {
            if filename.contains(excludeKeyword) {
                Logger.podoSojuKit.debug(
                    "File contains exclude keyword '\(excludeKeyword)': not an installer",
                    category: "InstallerDetector"
                )
                return false
            }
        }

        // Check for installer keywords in filename
        let hasInstallerKeyword = installerKeywords.contains { filename.contains($0) }
        
        if hasInstallerKeyword {
            Logger.podoSojuKit.info(
                "File contains installer keyword: is installer",
                category: "InstallerDetector"
            )
            return true
        }

        // Stage 2: Check file signature (slower but accurate)
        Logger.podoSojuKit.debug(
            "No installer keywords in filename, checking file signature...",
            category: "InstallerDetector"
        )
        return checkFileSignature(url)
    }

    // MARK: - Private Methods

    /// Checks file signature using macOS `file` command
    ///
    /// This method uses the system `file` utility to detect actual installer types
    /// based on file magic numbers and internal structure, rather than just filename.
    ///
    /// - Parameter url: The file URL to check
    /// - Returns: `true` if file signature matches known installer types
    private static func checkFileSignature(_ url: URL) -> Bool {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            Logger.podoSojuKit.warning(
                "File does not exist: \(url.path)",
                category: "InstallerDetector"
            )
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/file")
        process.arguments = [url.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lowercased = output.lowercased()

                Logger.podoSojuKit.debug(
                    "file command output: \(output.trimmingCharacters(in: .whitespacesAndNewlines))",
                    category: "InstallerDetector"
                )

                // Check for known installer signatures
                for signature in installerSignatures {
                    if lowercased.contains(signature) {
                        Logger.podoSojuKit.info(
                            "Detected installer signature '\(signature)': is installer",
                            category: "InstallerDetector"
                        )
                        return true
                    }
                }

                Logger.podoSojuKit.debug(
                    "No installer signature found in file output",
                    category: "InstallerDetector"
                )
                return false
            }
        } catch {
            Logger.podoSojuKit.error(
                "Failed to check file signature: \(error.localizedDescription)",
                category: "InstallerDetector"
            )
        }

        return false
    }

    /// Extracts the program name from an installer filename
    ///
    /// Attempts to extract the application name by removing common installer
    /// keywords and cleaning up the filename.
    ///
    /// - Parameter url: The installer file URL
    /// - Returns: The extracted program name, or the original filename if extraction fails
    ///
    /// # Extraction Rules
    /// 1. Remove file extension
    /// 2. Remove installer keywords (setup, install, installer)
    /// 3. Remove common separators (underscore, hyphen, space)
    /// 4. Trim whitespace and return
    ///
    /// # Examples
    /// ```swift
    /// let url1 = URL(fileURLWithPath: "/Downloads/NetFile_Setup.exe")
    /// InstallerDetector.installerName(from: url1) // "NetFile"
    ///
    /// let url2 = URL(fileURLWithPath: "/Downloads/MyApp-Installer-v2.0.exe")
    /// InstallerDetector.installerName(from: url2) // "MyApp-v2.0"
    ///
    /// let url3 = URL(fileURLWithPath: "/Downloads/install_chrome.exe")
    /// InstallerDetector.installerName(from: url3) // "chrome"
    /// ```
    public static func installerName(from url: URL) -> String {
        let filenameWithoutExt = url.deletingPathExtension().lastPathComponent
        var programName = filenameWithoutExt

        Logger.podoSojuKit.debug(
            "Extracting program name from: \(url.lastPathComponent)",
            category: "InstallerDetector"
        )

        // Sort keywords by length (longest first) to avoid partial matches
        // e.g., "installer" should be removed before "install" to avoid leaving "er"
        let sortedKeywords = installerKeywords.sorted { $0.count > $1.count }

        // Remove installer keywords (case-insensitive)
        for keyword in sortedKeywords {
            // Build regex pattern for keyword with optional separators
            // Matches: "setup", "_setup", "-setup", " setup", "setup_", "setup-", "setup "
            let patterns = [
                "_\(keyword)",
                "-\(keyword)",
                " \(keyword)",
                "\(keyword)_",
                "\(keyword)-",
                "\(keyword) ",
                "\(keyword)"
            ]

            for pattern in patterns {
                // Replace all occurrences of the pattern
                while let range = programName.range(
                    of: pattern,
                    options: [.caseInsensitive]
                ) {
                    programName.removeSubrange(range)
                    Logger.podoSojuKit.debug(
                        "Removed pattern '\(pattern)': \(programName)",
                        category: "InstallerDetector"
                    )
                }
            }
        }

        // Clean up remaining separators at start/end
        programName = programName
            .trimmingCharacters(in: CharacterSet(charactersIn: "_- "))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // If we removed everything, fall back to original filename
        if programName.isEmpty {
            programName = filenameWithoutExt
            Logger.podoSojuKit.warning(
                "Program name extraction resulted in empty string, using original: \(programName)",
                category: "InstallerDetector"
            )
        } else {
            Logger.podoSojuKit.info(
                "Extracted program name: \(programName)",
                category: "InstallerDetector"
            )
        }

        return programName
    }
}
