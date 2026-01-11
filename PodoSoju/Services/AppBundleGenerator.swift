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

/// Wine 프로그램을 macOS .app 번들로 생성 (포도주스)
class AppBundleGenerator {

    enum GeneratorError: LocalizedError {
        case createDirectoryFailed(String)
        case writePlistFailed(String)
        case writeLauncherFailed(String)
        case writeConfigFailed(String)
        case copyBinaryFailed(String)
        case binaryNotFound
        case iconConversionFailed

        var errorDescription: String? {
            switch self {
            case .createDirectoryFailed(let path):
                return "Failed to create directory: \(path)"
            case .writePlistFailed(let path):
                return "Failed to write Info.plist: \(path)"
            case .writeLauncherFailed(let path):
                return "Failed to write launcher: \(path)"
            case .writeConfigFailed(let path):
                return "Failed to write config.json: \(path)"
            case .copyBinaryFailed(let path):
                return "Failed to copy PodoJuice binary: \(path)"
            case .binaryNotFound:
                return "PodoJuice binary not found in app bundle"
            case .iconConversionFailed:
                return "Failed to convert icon to icns"
            }
        }
    }

    /// PodoJuice 버전 조회 (빌드된 바이너리에서)
    static func getPodoJuiceVersion() -> String {
        guard let podoJuiceURL = Bundle.main.url(forResource: "PodoJuice", withExtension: nil) else {
            return "1.0.0"
        }

        let process = Process()
        process.executableURL = podoJuiceURL
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "1.0.0"
        } catch {
            return "1.0.0"
        }
    }

    /// PodoJuice config.json 구조
    struct JuiceConfig: Codable {
        let workspaceId: String
        let workspacePath: String
        let targetLnk: String
        let exePath: String
    }

    /// 포도주스 앱 번들 생성 (Native Swift wrapper)
    /// - Parameters:
    ///   - name: 앱 이름 (e.g., "NetFile")
    ///   - workspaceId: Workspace UUID
    ///   - workspacePath: Workspace 경로 (WINEPREFIX)
    ///   - targetLnk: 바로가기 파일명 (e.g., "NetFile.lnk")
    ///   - exePath: Windows exe 경로 (e.g., "C:\Program Files\NetFile\NetFile.exe")
    ///   - icon: 앱 아이콘 (optional)
    ///   - destination: 저장 위치 (기본: workspace 바탕화면)
    /// - Returns: 생성된 .app 번들 URL
    static func createAppBundle(
        name: String,
        workspaceId: String,
        workspacePath: String,
        targetLnk: String,
        exePath: String,
        icon: NSImage? = nil,
        destination: URL? = nil
    ) throws -> URL {
        let fileManager = FileManager.default

        // 저장 위치 결정 (기본: workspace 바탕화면)
        let desktopDir = destination ?? URL(fileURLWithPath: workspacePath)
            .appendingPathComponent("drive_c/users/Public/Desktop")

        // 디렉토리 생성
        try? fileManager.createDirectory(at: desktopDir, withIntermediateDirectories: true)

        // 앱 번들 경로
        let sanitizedName = name.replacingOccurrences(of: "/", with: "-")
        let appURL = desktopDir.appendingPathComponent("\(sanitizedName).app")

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

        // PodoJuice 바이너리 복사
        guard let podoJuiceBinary = Bundle.main.url(forResource: "PodoJuice", withExtension: nil) else {
            throw GeneratorError.binaryNotFound
        }

        let executableURL = macOSURL.appendingPathComponent("PodoJuice")
        do {
            try fileManager.copyItem(at: podoJuiceBinary, to: executableURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        } catch {
            throw GeneratorError.copyBinaryFailed(executableURL.path)
        }

        // config.json 생성
        let config = JuiceConfig(
            workspaceId: workspaceId,
            workspacePath: workspacePath,
            targetLnk: targetLnk,
            exePath: exePath
        )

        let configURL = resourcesURL.appendingPathComponent("config.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let configData = try encoder.encode(config)
            try configData.write(to: configURL)
        } catch {
            throw GeneratorError.writeConfigFailed(configURL.path)
        }

        // Bundle identifier 생성
        let bundleId = "com.podosoju.juice.\(sanitizedName.lowercased().replacingOccurrences(of: " ", with: "-")).\(workspaceId.prefix(8))"

        // PodoJuice 버전 (빌드된 바이너리에서 조회)
        let podoJuiceVersion = Self.getPodoJuiceVersion()

        // Info.plist 생성
        var infoPlist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": "PodoJuice",
            "CFBundleIdentifier": bundleId,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": podoJuiceVersion,
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "13.0",
            "NSHighResolutionCapable": true,
            "LSUIElement": false,  // Dock에 표시
            // 커스텀 키 (포도주스용)
            "PodoJuiceVersion": podoJuiceVersion,
            "PodoJuiceWorkspaceId": workspaceId,
            "PodoJuiceExePath": exePath,
            "PodoJuiceTargetLnk": targetLnk
        ]

        // 아이콘 저장 (있는 경우)
        if let icon = icon {
            let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")
            if let icnsData = icon.icnsData() {
                try? icnsData.write(to: icnsURL)
                infoPlist["CFBundleIconFile"] = "AppIcon"
            }
        }

        let plistURL = contentsURL.appendingPathComponent("Info.plist")
        do {
            let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
            try plistData.write(to: plistURL)
        } catch {
            throw GeneratorError.writePlistFailed(plistURL.path)
        }

        Logger.podoSojuKit.info("Created PodoJuice app: \(appURL.path)", category: "AppBundleGenerator")

        return appURL
    }

    // MARK: - Legacy AppleScript method (deprecated)

    /// 앱 번들 생성 (Legacy - AppleScript 방식)
    @available(*, deprecated, message: "Use createAppBundle with workspacePath instead")
    static func createAppBundleLegacy(
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

        // launcher 스크립트 생성 - AppleScript로 PodoSoju URL scheme 실행
        let launcherScript = """
        #!/usr/bin/osascript

        set workspaceId to "\(workspaceId)"
        set theURL to "\(launchURL)"

        -- Wine 프로세스 확인 (해당 workspace)
        set wineRunning to do shell script "pgrep -f 'Workspaces/" & workspaceId & "' 2>/dev/null || echo ''"

        if wineRunning is "" then
            -- 실행 중 아님 - PodoSoju로 실행
            tell application "System Events"
                set isRunning to (count of (every process whose name is "PodoSoju")) > 0
            end tell

            if not isRunning then
                do shell script "open -g -a PodoSoju"
                delay 1.5
            end if

            do shell script "open '" & theURL & "'"
        else
            -- 이미 실행 중 - PodoSoju 포커스만
            tell application "PodoSoju" to activate
        end if
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
