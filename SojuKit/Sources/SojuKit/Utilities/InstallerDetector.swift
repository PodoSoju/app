//
//  InstallerDetector.swift
//  SojuKit
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
/// - Identifies installers by common keywords: "setup", "install", "installer"
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

    // MARK: - Public API

    /// Determines if the given file URL points to an installer executable
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

        Logger.sojuKit.debug(
            "Checking installer status for: \(url.lastPathComponent)",
            category: "InstallerDetector"
        )

        // Exclude uninstaller files
        for excludeKeyword in excludeKeywords {
            if filename.contains(excludeKeyword) {
                Logger.sojuKit.debug(
                    "File contains exclude keyword '\(excludeKeyword)': not an installer",
                    category: "InstallerDetector"
                )
                return false
            }
        }

        // Check for installer keywords
        for keyword in installerKeywords {
            if filename.contains(keyword) {
                Logger.sojuKit.info(
                    "File contains installer keyword '\(keyword)': is installer",
                    category: "InstallerDetector"
                )
                return true
            }
        }

        Logger.sojuKit.debug(
            "No installer keywords found: not an installer",
            category: "InstallerDetector"
        )
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

        Logger.sojuKit.debug(
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
                    Logger.sojuKit.debug(
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
            Logger.sojuKit.warning(
                "Program name extraction resulted in empty string, using original: \(programName)",
                category: "InstallerDetector"
            )
        } else {
            Logger.sojuKit.info(
                "Extracted program name: \(programName)",
                category: "InstallerDetector"
            )
        }

        return programName
    }
}
