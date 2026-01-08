//
//  InstallerDetectorTests.swift
//  SojuKitTests
//
//  Created on 2026-01-08.
//

import XCTest
@testable import SojuKit

final class InstallerDetectorTests: XCTestCase {

    // MARK: - isInstaller Tests

    func testIsInstaller_WithSetupKeyword_ReturnsTrue() {
        let url = URL(fileURLWithPath: "/path/to/NetFile_Setup.exe")
        XCTAssertTrue(InstallerDetector.isInstaller(url))
    }

    func testIsInstaller_WithInstallKeyword_ReturnsTrue() {
        let url = URL(fileURLWithPath: "/path/to/install_chrome.exe")
        XCTAssertTrue(InstallerDetector.isInstaller(url))
    }

    func testIsInstaller_WithInstallerKeyword_ReturnsTrue() {
        let url = URL(fileURLWithPath: "/path/to/MyApp-Installer.exe")
        XCTAssertTrue(InstallerDetector.isInstaller(url))
    }

    func testIsInstaller_CaseInsensitive_ReturnsTrue() {
        let urls = [
            URL(fileURLWithPath: "/path/to/SETUP.exe"),
            URL(fileURLWithPath: "/path/to/Install.exe"),
            URL(fileURLWithPath: "/path/to/InStAlLeR.exe")
        ]

        for url in urls {
            XCTAssertTrue(
                InstallerDetector.isInstaller(url),
                "Should detect installer regardless of case: \(url.lastPathComponent)"
            )
        }
    }

    func testIsInstaller_RegularExecutable_ReturnsFalse() {
        let url = URL(fileURLWithPath: "/path/to/NetFile.exe")
        XCTAssertFalse(InstallerDetector.isInstaller(url))
    }

    func testIsInstaller_WithUninstallKeyword_ReturnsFalse() {
        let urls = [
            URL(fileURLWithPath: "/path/to/uninstall.exe"),
            URL(fileURLWithPath: "/path/to/unins000.exe"),
            URL(fileURLWithPath: "/path/to/Uninstall_App.exe")
        ]

        for url in urls {
            XCTAssertFalse(
                InstallerDetector.isInstaller(url),
                "Should exclude uninstaller: \(url.lastPathComponent)"
            )
        }
    }

    func testIsInstaller_EmptyFilename_ReturnsFalse() {
        let url = URL(fileURLWithPath: "/path/to/.exe")
        XCTAssertFalse(InstallerDetector.isInstaller(url))
    }

    // MARK: - installerName Tests

    func testInstallerName_WithSetupSuffix_RemovesSetup() {
        let url = URL(fileURLWithPath: "/path/to/NetFile_Setup.exe")
        let name = InstallerDetector.installerName(from: url)
        XCTAssertEqual(name, "NetFile")
    }

    func testInstallerName_WithInstallPrefix_RemovesInstall() {
        let url = URL(fileURLWithPath: "/path/to/install_chrome.exe")
        let name = InstallerDetector.installerName(from: url)
        XCTAssertEqual(name, "chrome")
    }

    func testInstallerName_WithInstallerInfix_RemovesInstaller() {
        let url = URL(fileURLWithPath: "/path/to/MyApp-Installer-v2.0.exe")
        let name = InstallerDetector.installerName(from: url)
        XCTAssertEqual(name, "MyApp-v2.0")
    }

    func testInstallerName_MultipleKeywords_RemovesAll() {
        let url = URL(fileURLWithPath: "/path/to/setup_installer_app.exe")
        let name = InstallerDetector.installerName(from: url)
        XCTAssertEqual(name, "app")
    }

    func testInstallerName_CaseInsensitive_RemovesKeywords() {
        let urls = [
            (URL(fileURLWithPath: "/path/to/SETUP.exe"), ""),
            (URL(fileURLWithPath: "/path/to/MyApp_SETUP.exe"), "MyApp"),
            (URL(fileURLWithPath: "/path/to/InStAlL_Tool.exe"), "Tool")
        ]

        for (url, expected) in urls {
            let name = InstallerDetector.installerName(from: url)
            if expected.isEmpty {
                // If extraction results in empty, should return original filename
                XCTAssertFalse(name.isEmpty, "Should not return empty string")
            } else {
                XCTAssertEqual(
                    name,
                    expected,
                    "Failed for: \(url.lastPathComponent)"
                )
            }
        }
    }

    func testInstallerName_NoKeywords_ReturnsOriginalName() {
        let url = URL(fileURLWithPath: "/path/to/NetFile.exe")
        let name = InstallerDetector.installerName(from: url)
        XCTAssertEqual(name, "NetFile")
    }

    func testInstallerName_ComplexFilename_ExtractsCorrectly() {
        let testCases: [(String, String)] = [
            ("7-Zip_Setup.exe", "7-Zip"),
            ("VLC-media-player-install.exe", "VLC-media-player"),
            ("Adobe Reader DC Setup.exe", "Adobe Reader DC"),
            ("firefox-installer.exe", "firefox"),
            ("setup_python_3.11.exe", "python_3.11")
        ]

        for (filename, expected) in testCases {
            let url = URL(fileURLWithPath: "/path/to/\(filename)")
            let name = InstallerDetector.installerName(from: url)
            XCTAssertEqual(
                name,
                expected,
                "Failed for filename: \(filename)"
            )
        }
    }

    func testInstallerName_OnlyKeyword_ReturnsFallback() {
        // When extraction removes everything, should return original filename
        let urls = [
            URL(fileURLWithPath: "/path/to/setup.exe"),
            URL(fileURLWithPath: "/path/to/install.exe"),
            URL(fileURLWithPath: "/path/to/installer.exe")
        ]

        for url in urls {
            let name = InstallerDetector.installerName(from: url)
            XCTAssertFalse(
                name.isEmpty,
                "Should return fallback name for: \(url.lastPathComponent)"
            )
        }
    }

    func testInstallerName_WithVersion_PreservesVersion() {
        let url = URL(fileURLWithPath: "/path/to/App_v1.2.3_Setup.exe")
        let name = InstallerDetector.installerName(from: url)
        XCTAssertTrue(
            name.contains("v1.2.3") || name.contains("1.2.3"),
            "Should preserve version number"
        )
    }

    // MARK: - Integration Tests

    func testRealWorldInstallers() {
        let testCases: [(String, Bool, String?)] = [
            // (filename, isInstaller, expectedName)
            ("NetFile_Setup.exe", true, "NetFile"),
            ("Chrome-Setup.exe", true, "Chrome"),
            ("firefox_installer.exe", true, "firefox"),
            ("VSCode.exe", false, "VSCode"),
            ("unins000.exe", false, nil),
            ("Steam-Setup.exe", true, "Steam"),
            ("Discord Setup.exe", true, "Discord")
        ]

        for (filename, shouldBeInstaller, expectedName) in testCases {
            let url = URL(fileURLWithPath: "/path/to/\(filename)")

            // Test isInstaller
            XCTAssertEqual(
                InstallerDetector.isInstaller(url),
                shouldBeInstaller,
                "isInstaller check failed for: \(filename)"
            )

            // Test installerName if applicable
            if let expected = expectedName {
                let name = InstallerDetector.installerName(from: url)
                XCTAssertEqual(
                    name,
                    expected,
                    "installerName extraction failed for: \(filename)"
                )
            }
        }
    }
}
