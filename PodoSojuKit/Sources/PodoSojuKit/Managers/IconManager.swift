//
//  IconManager.swift
//  PodoSojuKit
//
//  Created on 2026-01-11.
//

import Foundation
import AppKit
import OSLog

/// Manages exe icon extraction and caching
/// Icons are stored in {workspace}/.soju/apps/{exe_name}.{png|bmp}
public final class IconManager: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = IconManager()

    private init() {}

    // MARK: - Public Methods

    /// Get icon for an exe file, extracting if necessary
    /// - Parameters:
    ///   - exeURL: URL to the .exe or .lnk file
    ///   - workspace: Workspace containing the exe
    /// - Returns: NSImage if icon exists or was extracted, nil otherwise
    public func getIcon(for exeURL: URL, in workspace: URL) -> NSImage? {
        let exeName = exeURL.deletingPathExtension().lastPathComponent
        let iconsDir = workspace.appendingPathComponent(".soju/apps")

        // 1. Check for existing PNG
        let pngPath = iconsDir.appendingPathComponent("\(exeName).png")
        if FileManager.default.fileExists(atPath: pngPath.path) {
            return NSImage(contentsOf: pngPath)
        }

        // 2. Check for existing BMP
        let bmpPath = iconsDir.appendingPathComponent("\(exeName).bmp")
        if FileManager.default.fileExists(atPath: bmpPath.path) {
            return NSImage(contentsOf: bmpPath)
        }

        // 3. Check for existing ICO
        let icoPath = iconsDir.appendingPathComponent("\(exeName).ico")
        if FileManager.default.fileExists(atPath: icoPath.path) {
            return NSImage(contentsOf: icoPath)
        }

        // 4. No icon found
        return nil
    }

    /// Get icon URL for an exe file (checks PNG first, then BMP, then ICO)
    /// - Parameters:
    ///   - exeURL: URL to the .exe file
    ///   - workspace: Workspace URL
    /// - Returns: URL to icon file if exists, nil otherwise
    public func getIconURL(for exeURL: URL, in workspace: URL) -> URL? {
        let exeName = exeURL.deletingPathExtension().lastPathComponent
        let iconsDir = workspace.appendingPathComponent(".soju/apps")

        // Check PNG → BMP → ICO
        for ext in ["png", "bmp", "ico"] {
            let iconPath = iconsDir.appendingPathComponent("\(exeName).\(ext)")
            if FileManager.default.fileExists(atPath: iconPath.path) {
                return iconPath
            }
        }

        return nil
    }

    /// Extract icon from exe file using soju-extract-icon tool
    /// - Parameters:
    ///   - exeURL: URL to the .exe file
    ///   - workspace: Workspace URL
    /// - Returns: URL to extracted icon file, nil if extraction failed
    @discardableResult
    public func extractIcon(from exeURL: URL, in workspace: URL) async -> URL? {
        let exeName = exeURL.deletingPathExtension().lastPathComponent
        let iconsDir = workspace.appendingPathComponent(".soju/apps")
        let outputBase = iconsDir.appendingPathComponent(exeName)

        // Create icons directory if needed
        try? FileManager.default.createDirectory(at: iconsDir, withIntermediateDirectories: true)

        // Find soju-extract-icon tool
        guard let extractorPath = findExtractor() else {
            Logger.podoSojuKit.error("soju-extract-icon not found", category: "IconManager")
            return nil
        }

        // Run extraction
        let process = Process()
        process.executableURL = URL(fileURLWithPath: extractorPath)
        process.arguments = [exeURL.path, outputBase.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                // Check which files were created (PNG preferred)
                for ext in ["png", "bmp", "ico"] {
                    let iconPath = iconsDir.appendingPathComponent("\(exeName).\(ext)")
                    if FileManager.default.fileExists(atPath: iconPath.path) {
                        Logger.podoSojuKit.info("Extracted icon: \(iconPath.lastPathComponent)", category: "IconManager")
                        return iconPath
                    }
                }
            } else {
                Logger.podoSojuKit.warning("Icon extraction failed for: \(exeName)", category: "IconManager")
            }
        } catch {
            Logger.podoSojuKit.error("Icon extraction error: \(error.localizedDescription)", category: "IconManager")
        }

        return nil
    }

    /// Get icon, extracting if necessary
    /// - Parameters:
    ///   - exeURL: URL to the .exe file
    ///   - workspace: Workspace URL
    /// - Returns: NSImage if available
    public func getOrExtractIcon(for exeURL: URL, in workspace: URL) async -> NSImage? {
        // 1. Check existing
        if let icon = getIcon(for: exeURL, in: workspace) {
            return icon
        }

        // 2. Extract
        if let iconURL = await extractIcon(from: exeURL, in: workspace) {
            return NSImage(contentsOf: iconURL)
        }

        return nil
    }

    // MARK: - Private Methods

    /// Find soju-extract-icon tool
    private func findExtractor() -> String? {
        // 1. Check in Soju bin directory
        let sojuBin = SojuManager.shared.binFolder.appendingPathComponent("soju-extract-icon")
        if FileManager.default.isExecutableFile(atPath: sojuBin.path) {
            return sojuBin.path
        }

        // 2. Check in PATH
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for dir in pathDirs {
            let path = "\(dir)/soju-extract-icon"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }
}
