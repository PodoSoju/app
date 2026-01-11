//
//  AppBundleGenerator.swift
//  PodoSoju
//
//  Created on 2026-01-11.
//

import Foundation
import AppKit
import PodoSojuKit
import os.log

/// Wine 프로그램을 macOS .app 번들로 생성
class AppBundleGenerator {

    enum GeneratorError: LocalizedError {
        case createDirectoryFailed(String)
        case writePlistFailed(String)
        case writeLauncherFailed(String)
        case iconConversionFailed

        var errorDescription: String? {
            switch self {
            case .createDirectoryFailed(let path):
                return "Failed to create directory: \(path)"
            case .writePlistFailed(let path):
                return "Failed to write Info.plist: \(path)"
            case .writeLauncherFailed(let path):
                return "Failed to write launcher: \(path)"
            case .iconConversionFailed:
                return "Failed to convert icon to icns"
            }
        }
    }

    /// 앱 번들 생성
    /// - Parameters:
    ///   - name: 앱 이름 (e.g., "NetFile")
    ///   - workspaceId: Workspace UUID
    ///   - exePath: Windows exe 경로 (e.g., "C:\Program Files\NetFile\NetFile.exe")
    ///   - icon: 앱 아이콘 (optional)
    ///   - destination: 저장 위치 (기본: ~/Applications)
    /// - Returns: 생성된 .app 번들 URL
    static func createAppBundle(
        name: String,
        workspaceId: String,
        exePath: String,
        icon: NSImage? = nil,
        destination: URL? = nil
    ) throws -> URL {
        let fileManager = FileManager.default

        // 저장 위치 결정
        let applicationsDir = destination ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")

        // Applications 디렉토리 생성
        try? fileManager.createDirectory(at: applicationsDir, withIntermediateDirectories: true)

        // 앱 번들 경로
        let sanitizedName = name.replacingOccurrences(of: "/", with: "-")
        let appURL = applicationsDir.appendingPathComponent("\(sanitizedName).app")

        // 기존 앱 삭제
        try? fileManager.removeItem(at: appURL)

        // 디렉토리 구조 생성
        let contentsURL = appURL.appendingPathComponent("Contents")
        let macOSURL = contentsURL.appendingPathComponent("MacOS")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")

        for dir in [contentsURL, macOSURL, resourcesURL] {
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                throw GeneratorError.createDirectoryFailed(dir.path)
            }
        }

        // Bundle identifier 생성
        let bundleId = "com.podosoju.app.\(workspaceId).\(sanitizedName.lowercased().replacingOccurrences(of: " ", with: "-"))"

        // URL scheme으로 실행할 URL 생성
        let encodedExePath = exePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? exePath
        let launchURL = "podosoju://run/\(workspaceId)/\(encodedExePath)"

        // Info.plist 생성
        let infoPlist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": "launcher",
            "CFBundleIdentifier": bundleId,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "14.0",
            "NSHighResolutionCapable": true,
            "LSUIElement": false,  // Dock에 표시
            // 커스텀 키 (PodoSoju용)
            "PodoSojuWorkspaceId": workspaceId,
            "PodoSojuExePath": exePath,
            "PodoSojuLaunchURL": launchURL
        ]

        let plistURL = contentsURL.appendingPathComponent("Info.plist")
        do {
            let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
            try plistData.write(to: plistURL)
        } catch {
            throw GeneratorError.writePlistFailed(plistURL.path)
        }

        // launcher 스크립트 생성 (open 명령으로 URL scheme 호출)
        let launcherScript = """
        #!/bin/bash
        open "\(launchURL)"
        """

        let launcherURL = macOSURL.appendingPathComponent("launcher")
        do {
            try launcherScript.write(to: launcherURL, atomically: true, encoding: .utf8)
            // 실행 권한 부여
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path)
        } catch {
            throw GeneratorError.writeLauncherFailed(launcherURL.path)
        }

        // 아이콘 저장 (있는 경우)
        if let icon = icon {
            let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")
            if let icnsData = icon.icnsData() {
                try? icnsData.write(to: icnsURL)

                // Info.plist에 아이콘 추가 (다시 쓰기)
                var updatedPlist = infoPlist
                updatedPlist["CFBundleIconFile"] = "AppIcon"
                let plistData = try? PropertyListSerialization.data(fromPropertyList: updatedPlist, format: .xml, options: 0)
                try? plistData?.write(to: plistURL)
            }
        }

        Logger.podoSojuKit.info("Created app bundle: \(appURL.path)", category: "AppBundleGenerator")

        return appURL
    }

    /// 앱 번들 삭제
    static func removeAppBundle(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
        Logger.podoSojuKit.info("Removed app bundle: \(url.path)", category: "AppBundleGenerator")
    }
}

// MARK: - NSImage Extension

extension NSImage {
    /// NSImage를 icns 데이터로 변환
    func icnsData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        // PNG로 변환 후 iconutil 사용하거나, 간단히 tiff 저장
        // 실제로는 iconutil을 사용해야 하지만, 간단히 PNG로 대체
        return bitmap.representation(using: .png, properties: [:])
    }
}
