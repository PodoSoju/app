//
//  SojuManager.swift
//  PodoSojuKit
//
//  Created on 2026-01-07.
//

import Foundation
import os.log
import CoreGraphics
import Darwin
import AppKit

/// Soju (Wine alternative) 관리자
/// - Soju 바이너리 경로 관리
/// - 환경 변수 설정 (WINEPREFIX, DXVK 등)
/// - 프로세스 실행 관리
public final class SojuManager: ObservableObject, @unchecked Sendable {
    // MARK: - Singleton

    public static let shared = SojuManager()

    // MARK: - Properties

    /// Soju 설치 루트 디렉토리
    /// ~/Library/Application Support/com.soju.app/Soju
    public let sojuRoot: URL

    /// Soju bin 디렉토리
    public let binFolder: URL

    /// Soju lib 디렉토리
    public let libFolder: URL

    /// wine64 바이너리 경로
    public let wineBinary: URL

    /// wineserver 바이너리 경로
    public let wineserverBinary: URL

    /// wineboot 바이너리 경로
    public let winebootBinary: URL

    /// winetricks 스크립트 경로
    public let winetricksBinary: URL

    /// Soju 버전 정보
    @Published public private(set) var version: SojuVersion?

    // MARK: - Initialization

    private init() {
        // Use FileManager API that automatically resolves to containerized paths
        // This ensures the app works correctly within its sandbox
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Cannot access Application Support directory")
        }

        // Soju (Wine packaging) is always installed under com.soju.app
        let sojuBundleId = "com.soju.app"

        self.sojuRoot = appSupport
            .appending(path: sojuBundleId)
            .appending(path: "Libraries")
            .appending(path: "Soju")

        self.binFolder = sojuRoot.appending(path: "bin")
        self.libFolder = sojuRoot.appending(path: "lib")
        self.wineBinary = binFolder.appending(path: "wine")
        self.wineserverBinary = binFolder.appending(path: "wineserver")
        self.winebootBinary = binFolder.appending(path: "wineboot")
        self.winetricksBinary = binFolder.appending(path: "winetricks")


        // Debug logging
        Logger.podoSojuKit.info("🏠 App Support: \(appSupport.path)", category: "Soju")
        Logger.podoSojuKit.info("🍇 Soju root: \(sojuRoot.path)", category: "Soju")
        Logger.podoSojuKit.info("🍷 Wine binary: \(wineBinary.path)", category: "Soju")

        // Check if files exist
        let wineExists = FileManager.default.fileExists(atPath: wineBinary.path)
        let isExecutable = FileManager.default.isExecutableFile(atPath: wineBinary.path)
        Logger.podoSojuKit.info("✅ Wine exists: \(wineExists), executable: \(isExecutable)", category: "Soju")

        // 버전 정보 로드
        self.version = loadVersion()
    }

    // MARK: - Version Loading

    /// SojuVersion.plist에서 버전 정보 로드
    private func loadVersion() -> SojuVersion? {
        let versionPlistURL = sojuRoot.deletingLastPathComponent()
            .appending(path: "SojuVersion.plist")

        guard FileManager.default.fileExists(atPath: versionPlistURL.path) else {
            Logger.podoSojuKit.warning("SojuVersion.plist not found at \(versionPlistURL.path)")
            return nil
        }

        do {
            let data = try Data(contentsOf: versionPlistURL)
            let decoder = PropertyListDecoder()
            let versionDict = try decoder.decode([String: SojuVersion].self, from: data)
            return versionDict["version"]
        } catch {
            Logger.podoSojuKit.error("Failed to load Soju version: \(error)")
            return nil
        }
    }

    /// 버전 정보 리로드 (설치 후 호출)
    @MainActor
    public func reloadVersion() {
        self.version = loadVersion()
        Logger.podoSojuKit.info("Version reloaded: \(version?.versionString ?? "nil")", category: "Soju")
    }

    // MARK: - Installation Check

    /// Soju가 설치되어 있는지 확인
    public var isInstalled: Bool {
        return FileManager.default.fileExists(atPath: wineBinary.path)
    }

    /// Soju 설치 여부 및 실행 가능 여부 검증
    public func validate() throws {
        guard isInstalled else {
            throw SojuError.notInstalled
        }

        guard FileManager.default.isExecutableFile(atPath: wineBinary.path) else {
            throw SojuError.notExecutable(wineBinary.path)
        }
    }

    // MARK: - Environment Construction

    /// Workspace에 대한 Soju 환경 변수 생성
    /// - Parameters:
    ///   - workspace: 대상 Workspace
    ///   - additionalEnv: 추가 환경 변수 (선택)
    /// - Returns: 전체 환경 변수 딕셔너리
    public func constructEnvironment(
        for workspace: Workspace,
        additionalEnv: [String: String] = [:]
    ) -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        // WINEPREFIX 설정
        env["WINEPREFIX"] = workspace.winePrefixPath

        // WINEDLLPATH 설정 (시스템 DLL 검색 경로)
        let wineDllPath = [
            libFolder.appending(path: "wine/x86_64-windows").path,
            libFolder.appending(path: "wine/i386-windows").path
        ].joined(separator: ":")
        env["WINEDLLPATH"] = wineDllPath

        // DYLD_FALLBACK_LIBRARY_PATH 설정 (동적 라이브러리 검색 경로)
        // Wine이 FreeType, gnutls 등을 dlopen으로 로드할 때 필요
        env["DYLD_FALLBACK_LIBRARY_PATH"] = libFolder.path

        // TMPDIR 설정 (샌드박스 호환성)
        // Wine이 /tmp 대신 컨테이너 내부 임시 디렉토리 사용하도록 설정
        let containerTmp = FileManager.default.temporaryDirectory.path
        env["TMPDIR"] = containerTmp
        Logger.podoSojuKit.debug("TMPDIR set to: \(containerTmp)", category: "Soju")

        // WINEDEBUG는 workspace.settings.environmentVariables()에서 설정됨

        // GStreamer 로그 설정 (2 = 경고 및 에러만)
        env["GST_DEBUG"] = "2"

        // Workspace 설정 반영
        workspace.settings.environmentVariables(wineEnv: &env)

        // 추가 환경 변수 병합 (installer detection 등을 위한 WINEDEBUG 오버라이드 가능)
        env.merge(additionalEnv, uniquingKeysWith: { $1 })

        return env
    }

    // MARK: - Process Execution

    /// wine64 프로세스 실행
    /// - Parameters:
    ///   - args: wine 인자 (예: ["--version"])
    ///   - workspace: 대상 Workspace
    ///   - additionalEnv: 추가 환경 변수
    ///   - captureOutput: 출력 캡처 여부 (GUI 프로그램은 false로 설정)
    /// - Returns: 프로세스 출력 스트림
    public func runWine(
        args: [String],
        workspace: Workspace,
        additionalEnv: [String: String] = [:],
        captureOutput: Bool = true
    ) throws -> AsyncStream<ProcessOutput> {
        try validate()

        Logger.podoSojuKit.info("🍷 Running Wine with args: \(args.joined(separator: " "))", category: "Soju")
        Logger.podoSojuKit.debug("Wine binary: \(wineBinary.path(percentEncoded: false))", category: "Soju")
        Logger.podoSojuKit.debug("Working directory: \(workspace.url.path(percentEncoded: false))", category: "Soju")
        Logger.podoSojuKit.debug("Capture output: \(captureOutput)", category: "Soju")

        // SOJU 패치용 환경변수 추가
        var envWithSoju = additionalEnv

        // exe 경로 추출 및 정규화 (첫 번째 .exe 인자)
        if let exePath = args.first(where: { $0.lowercased().hasSuffix(".exe") }) {
            // Unix 경로로 정규화
            let unixPath: String
            if exePath.hasPrefix("/") {
                // 이미 Unix 경로
                unixPath = exePath
            } else {
                // Windows 경로 → Unix 경로 변환
                // C:\path\to\app.exe → {workspace}/drive_c/path/to/app.exe
                let winPath = exePath.replacingOccurrences(of: "\\", with: "/")
                if winPath.count >= 2,
                   let drive = winPath.first?.lowercased,
                   winPath.dropFirst().first == ":" {
                    let relativePath = String(winPath.dropFirst(3)) // Remove "C:/"
                    unixPath = workspace.url
                        .appendingPathComponent("drive_\(drive)")
                        .appendingPathComponent(relativePath)
                        .path(percentEncoded: false)
                } else {
                    // 알 수 없는 형식은 그대로
                    unixPath = exePath
                }
            }

            // SOJU_APP_PATH: Unix 경로
            envWithSoju["SOJU_APP_PATH"] = unixPath
            Logger.podoSojuKit.debug("SOJU_APP_PATH set to: \(unixPath)", category: "Soju")

            // SOJU_APP_NAME: 파일명 (확장자 제외)
            let appName = URL(fileURLWithPath: unixPath)
                .deletingPathExtension()
                .lastPathComponent
            envWithSoju["SOJU_APP_NAME"] = appName
            Logger.podoSojuKit.debug("SOJU_APP_NAME set to: \(appName)", category: "Soju")
        }

        // 워크스페이스 ID 설정 (URL의 마지막 컴포넌트가 UUID)
        let workspaceId = workspace.url.lastPathComponent
        envWithSoju["SOJU_WORKSPACE_ID"] = workspaceId
        Logger.podoSojuKit.debug("SOJU_WORKSPACE_ID set to: \(workspaceId)", category: "Soju")

        let process = Process()
        process.executableURL = wineBinary
        process.arguments = args
        process.currentDirectoryURL = workspace.url
        process.environment = constructEnvironment(for: workspace, additionalEnv: envWithSoju)
        process.qualityOfService = .userInitiated

        if captureOutput {
            // 기존 runStream() 사용
            Logger.podoSojuKit.info("🚀 Starting Wine process with output capture...", category: "Soju")
            return try process.runStream(name: args.joined(separator: " "))
        } else {
            // GUI 모드: 파이프 없이 직접 실행
            process.standardOutput = nil
            process.standardError = nil
            Logger.podoSojuKit.info("🎨 GUI mode: running without pipes", category: "Soju")

            return AsyncStream { continuation in
                Task {
                    continuation.yield(.started)
                    do {
                        try process.run()
                        Logger.podoSojuKit.info("🚀 Wine process started (GUI mode)", category: "Soju")
                        // GUI 앱은 fork 후 바로 반환되므로 기다리지 않음
                        continuation.yield(.terminated(0))
                    } catch {
                        Logger.podoSojuKit.error("💥 Wine process failed: \(error)", category: "Soju")
                        continuation.yield(.terminated(-1))
                    }
                    continuation.finish()
                }
            }
        }
    }

    /// wineboot 실행 (prefix 초기화)
    /// - Parameter workspace: 대상 Workspace
    public func runWineboot(workspace: Workspace) async throws {
        try validate()

        Logger.podoSojuKit.info("Initializing Wine prefix at \(workspace.winePrefixPath)")

        let process = Process()
        process.executableURL = winebootBinary
        process.arguments = ["--init"]
        process.currentDirectoryURL = workspace.url
        process.environment = constructEnvironment(for: workspace)
        process.qualityOfService = .userInitiated

        // wineboot은 백그라운드에서 실행되므로 출력을 무시하고 분리 모드로 실행
        process.standardOutput = nil
        process.standardError = nil

        do {
            try process.run()
            Logger.podoSojuKit.info("wineboot process started in background")
        } catch {
            Logger.podoSojuKit.error("Failed to start wineboot: \(error.localizedDescription)")
            throw SojuError.winebootFailed(-1)
        }

        // drive_c 디렉토리가 생성될 때까지 대기 (최대 10초)
        let driveCPath = (workspace.winePrefixPath as NSString).appendingPathComponent("drive_c")
        let maxAttempts = 100 // 100 * 100ms = 10초
        var attempts = 0

        while attempts < maxAttempts {
            if FileManager.default.fileExists(atPath: driveCPath) {
                Logger.podoSojuKit.info("Wine prefix initialized successfully (drive_c created)")
                return
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            attempts += 1
        }

        // 타임아웃 후에도 drive_c가 없으면 실패
        Logger.podoSojuKit.error("wineboot timeout: drive_c directory not created after 10 seconds")
        throw SojuError.winebootFailed(-1)
    }

    /// wineserver 실행
    /// - Parameters:
    ///   - args: wineserver 인자 (예: ["-k"] for kill)
    ///   - workspace: 대상 Workspace
    public func runWineserver(
        args: [String],
        workspace: Workspace
    ) throws -> AsyncStream<ProcessOutput> {
        try validate()

        let process = Process()
        process.executableURL = wineserverBinary
        process.arguments = args
        process.currentDirectoryURL = workspace.url
        process.environment = constructEnvironment(for: workspace)
        process.qualityOfService = .userInitiated

        return try process.runStream(name: "wineserver " + args.joined(separator: " "))
    }

    /// winetricks 실행 (여러 컴포넌트 일괄 설치)
    /// - Parameters:
    ///   - workspace: 대상 Workspace
    ///   - components: 설치할 컴포넌트들 (예: ["vcrun2019", "d3dx9"])
    ///   - progressHandler: 진행 상황 콜백 (현재 컴포넌트, 완료된 개수)
    public func runWinetricks(
        workspace: Workspace,
        components: [String],
        progressHandler: (@Sendable (String, Int) -> Void)? = nil
    ) async throws {
        try validate()

        guard FileManager.default.fileExists(atPath: winetricksBinary.path) else {
            throw SojuError.winetricksNotFound
        }

        guard !components.isEmpty else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [winetricksBinary.path, "-q", "--force"] + components
        process.currentDirectoryURL = workspace.url

        // winetricks용 환경변수 설정
        var env = constructEnvironment(for: workspace)
        env["WINE"] = wineBinary.path
        env["WINESERVER"] = wineserverBinary.path
        env["PATH"] = "\(binFolder.path):" + (env["PATH"] ?? "/usr/bin:/bin")
        env["TERM"] = "xterm"  // wget 진행률 출력을 위해

        process.environment = env
        process.qualityOfService = .userInitiated

        let componentsStr = components.joined(separator: ", ")
        Logger.podoSojuKit.info("🔧 Running winetricks: \(componentsStr)", category: "Soju")
        Logger.podoSojuKit.debug("WINE=\(wineBinary.path)", category: "Soju")
        Logger.podoSojuKit.debug("WINESERVER=\(wineserverBinary.path)", category: "Soju")

        var currentIndex = 0
        progressHandler?(components[0], 0)

        for await output in try process.runStream(name: "winetricks \(componentsStr)") {
            switch output {
            case .message(let message):
                Logger.podoSojuKit.debug("winetricks: \(message)", category: "Soju")
                // 다음 컴포넌트 시작 감지 (winetricks 출력에서 "Executing" 패턴)
                for (index, component) in components.enumerated() where index > currentIndex {
                    if message.contains(component) || message.contains("Executing \(component)") {
                        currentIndex = index
                        progressHandler?(component, index)
                        break
                    }
                }
            case .terminated(let code):
                if code != 0 {
                    throw SojuError.winetricksFailed(code)
                }
            case .started, .error:
                break
            }
        }

        Logger.podoSojuKit.info("✅ winetricks completed: \(componentsStr)", category: "Soju")
    }

    /// winetricks 실행 (단일 컴포넌트 - 하위 호환성)
    /// - Parameters:
    ///   - workspace: 대상 Workspace
    ///   - component: 설치할 컴포넌트 (예: "vcrun2019", "d3dx9")
    public func runWinetricks(
        workspace: Workspace,
        component: String
    ) async throws {
        try await runWinetricks(workspace: workspace, components: [component])
    }

    /// winetricks 실행 (단일 컴포넌트 + 진행률 콜백)
    /// - Parameters:
    ///   - workspace: 대상 Workspace
    ///   - component: 설치할 컴포넌트 (예: "vcrun2019", "d3dx9")
    ///   - onProgress: 진행 상황 콜백 (downloading/installing)
    public func runWinetricks(
        workspace: Workspace,
        component: String,
        onProgress: @escaping @Sendable (InstallProgress) -> Void
    ) async throws {
        try validate()

        guard FileManager.default.fileExists(atPath: winetricksBinary.path) else {
            throw SojuError.winetricksNotFound
        }

        // winetricks용 환경변수 설정
        var env = constructEnvironment(for: workspace)
        env["WINE"] = wineBinary.path
        env["WINESERVER"] = wineserverBinary.path
        env["PATH"] = "\(binFolder.path):" + (env["PATH"] ?? "/usr/bin:/bin")
        env["TERM"] = "xterm-256color"  // wget 진행률 출력을 위해

        Logger.podoSojuKit.info("🔧 Running winetricks with pty: \(component)", category: "Soju")

        // 상태 추적 변수
        let startTime = Date()
        var lastProgressLogTime = startTime
        var isDownloading = false
        var isInstalling = false
        var lastDownloadPercent = -1

        for await output in try runWithPty(
            command: "/bin/bash",
            args: [winetricksBinary.path, "-q", "--force", component],
            env: env,
            workingDirectory: workspace.url,
            name: "winetricks \(component)"
        ) {
            switch output {
            case .message(let message), .error(let message):
                // 1. 전체 출력 DEBUG 로깅
                Logger.podoSojuKit.debug("winetricks output: \(message)", category: "Soju")

                // 경과 시간 계산
                let elapsed = Date().timeIntervalSince(startTime)

                // 3. 5초마다 "running for X seconds" 로깅
                let timeSinceLastLog = Date().timeIntervalSince(lastProgressLogTime)
                if timeSinceLastLog >= 5.0 {
                    let seconds = Int(elapsed)
                    Logger.podoSojuKit.info("winetricks \(component): running for \(seconds)s...", category: "Soju")
                    lastProgressLogTime = Date()

                    // 4. 30초 이상 시 경고 로깅
                    if elapsed >= 30.0 {
                        Logger.podoSojuKit.warning("winetricks \(component): running for \(seconds)s (long operation)", category: "Soju")
                    }
                }

                // 1. "Downloading" 문자열 감지 -> downloading 상태
                if message.contains("Downloading") || message.lowercased().contains("download") {
                    if !isDownloading {
                        isDownloading = true
                        Logger.podoSojuKit.info("winetricks \(component): downloading...", category: "Soju")
                        onProgress(.downloading(percent: -1))  // -1은 "진행률 모름" 의미
                    }
                }

                // 2. wget 진행률 파싱: "50K .......... 45% 2.5M" 또는 " 45%" 패턴
                // pty를 사용하므로 wget이 진행률을 출력함
                if let range = message.range(of: #"\d+%"#, options: .regularExpression) {
                    let percentStr = message[range].dropLast() // % 제거
                    if let percent = Int(percentStr) {
                        // 다운로드 상태 업데이트 (% 포함)
                        if !isDownloading {
                            isDownloading = true
                            Logger.podoSojuKit.info("winetricks \(component): downloading started", category: "Soju")
                        }

                        // 진행률 변화 로깅 (10% 단위로만)
                        if percent != lastDownloadPercent && percent % 10 == 0 {
                            Logger.podoSojuKit.info("winetricks \(component): downloading \(percent)%", category: "Soju")
                            lastDownloadPercent = percent
                        }

                        onProgress(.downloading(percent: percent))
                    }
                }

                // 3. "Executing wine" 또는 "Running" 감지 -> installing 상태
                if message.contains("Executing wine") || message.contains("Executing /") ||
                   message.contains("Running") {
                    // 설치 시작 로깅 (처음 감지 시)
                    if !isInstalling {
                        isInstalling = true
                        Logger.podoSojuKit.info("winetricks \(component): installing...", category: "Soju")
                    }
                    onProgress(.installing)
                }

            case .terminated(let code):
                let totalElapsed = Int(Date().timeIntervalSince(startTime))
                if code != 0 {
                    Logger.podoSojuKit.error("winetricks \(component): failed with code \(code) after \(totalElapsed)s", category: "Soju")
                    throw SojuError.winetricksFailed(code)
                }
                Logger.podoSojuKit.info("winetricks \(component): terminated with code \(code) after \(totalElapsed)s", category: "Soju")
            case .started:
                Logger.podoSojuKit.debug("winetricks \(component): process started", category: "Soju")
            }
        }

        let totalElapsed = Int(Date().timeIntervalSince(startTime))
        Logger.podoSojuKit.info("✅ winetricks completed: \(component) (took \(totalElapsed)s)", category: "Soju")
    }

    // MARK: - Winetricks Verb Listing

    /// Parse winetricks verbs from `winetricks list-all` output
    /// - Returns: Array of WinetricksCategory containing all available verbs
    public func listWinetricksVerbs() async throws -> [WinetricksCategory] {
        try validate()

        guard FileManager.default.fileExists(atPath: winetricksBinary.path) else {
            throw SojuError.winetricksNotFound
        }

        Logger.podoSojuKit.info("📋 Listing winetricks verbs...", category: "Soju")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [winetricksBinary.path, "list-all"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            Logger.podoSojuKit.error("Failed to decode winetricks output", category: "Soju")
            return []
        }

        return parseWinetricksOutput(output)
    }

    /// Parse winetricks list-all output into categories and verbs
    /// Output format:
    /// ```
    /// ===== apps =====
    /// 7zip                     7-Zip 24.09 (Igor Pavlov, 2024) [downloadable]
    /// ===== dlls =====
    /// vcrun2019                Visual C++ 2015-2019 ...
    /// ```
    private func parseWinetricksOutput(_ output: String) -> [WinetricksCategory] {
        let lines = output.components(separatedBy: "\n")
        var categories: [WinetricksCategory] = []
        var currentCategory: WinetricksCategory?

        for line in lines {
            // Categories are labeled as "===== <name> ====="
            if line.starts(with: "=====") {
                // If we have a current category, add it to the list
                if let existingCategory = currentCategory {
                    categories.append(existingCategory)
                }

                // Create a new category
                let categoryName = line
                    .replacingOccurrences(of: "=====", with: "")
                    .trimmingCharacters(in: .whitespaces)

                if let category = WinetricksCategories(rawValue: categoryName) {
                    currentCategory = WinetricksCategory(category: category, verbs: [])
                } else {
                    currentCategory = nil
                }
            } else {
                guard currentCategory != nil else { continue }

                // Parse verb line: "verbname                Description text here"
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard !trimmedLine.isEmpty else { continue }

                // Split on first whitespace sequence
                let components = trimmedLine.components(separatedBy: " ")
                guard !components.isEmpty else { continue }

                let verbName = components[0]
                guard !verbName.isEmpty else { continue }

                let verbDescription = trimmedLine
                    .replacingOccurrences(of: "\(verbName) ", with: "")
                    .trimmingCharacters(in: .whitespaces)

                currentCategory?.verbs.append(
                    WinetricksVerb(name: verbName, description: verbDescription)
                )
            }
        }

        // Add the last category
        if let existingCategory = currentCategory {
            categories.append(existingCategory)
        }

        Logger.podoSojuKit.info("📋 Parsed \(categories.count) categories", category: "Soju")
        return categories
    }

    /// Run winetricks command in Terminal.app (Whisky-style)
    /// - Parameters:
    ///   - command: The winetricks verb/command to run (e.g., "vcrun2019")
    ///   - workspace: Target workspace for WINEPREFIX
    public func runWinetricksInTerminal(command: String, workspace: Workspace) async {
        guard FileManager.default.fileExists(atPath: winetricksBinary.path) else {
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Winetricks Not Found"
                alert.informativeText = "winetricks is not installed in the Soju installation."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }

        // Build the winetricks command with proper environment (escape quotes for AppleScript)
        let winetricksCmd = "DYLD_FALLBACK_LIBRARY_PATH='\(libFolder.path)' WINE='\(wineBinary.path)' WINESERVER='\(wineserverBinary.path)' WINEPREFIX='\(workspace.winePrefixPath)' PATH='\(binFolder.path)':$PATH '\(winetricksBinary.path)' \(command)"

        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(winetricksCmd)\"\nend tell"

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if let error = error {
                Logger.podoSojuKit.error("AppleScript error: \(error)", category: "Soju")
                if let description = error["NSAppleScriptErrorMessage"] as? String {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Winetricks Error"
                        alert.informativeText = "Failed to run winetricks \(command): \(description)"
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            } else {
                Logger.podoSojuKit.info("🔧 Launched winetricks '\(command)' in Terminal", category: "Soju")
            }
        }
    }

    // MARK: - PTY Execution

    /// pseudo-terminal을 사용하여 프로세스 실행
    /// wget 등 tty를 확인하는 프로그램의 진행률 출력을 캡처하기 위해 사용
    /// - Parameters:
    ///   - command: 실행할 명령 경로
    ///   - args: 명령 인자들
    ///   - env: 환경 변수
    ///   - workingDirectory: 작업 디렉토리
    ///   - name: 로깅용 프로세스 이름
    /// - Returns: 프로세스 출력 스트림
    private func runWithPty(
        command: String,
        args: [String],
        env: [String: String],
        workingDirectory: URL,
        name: String
    ) throws -> AsyncStream<ProcessOutput> {
        var masterFd: Int32 = 0
        var slaveFd: Int32 = 0

        // pty 생성
        guard openpty(&masterFd, &slaveFd, nil, nil, nil) == 0 else {
            Logger.podoSojuKit.error("Failed to create pty", category: "Soju")
            throw SojuError.ptyCreationFailed
        }

        // Swift 6 concurrency 안전성을 위해 로컬 상수로 복사
        let master = masterFd
        let slave = slaveFd

        Logger.podoSojuKit.debug("PTY created: master=\(master), slave=\(slave)", category: "Soju")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        process.environment = env
        process.currentDirectoryURL = workingDirectory
        process.qualityOfService = .userInitiated

        // slave를 stdin/stdout/stderr로 사용
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        return AsyncStream { continuation in
            Task {
                continuation.yield(.started)

                do {
                    try process.run()
                    Logger.podoSojuKit.info("🚀 PTY process started: \(name)", category: "Soju")

                    // slave는 process에서 사용하므로 여기서 닫음
                    close(slave)

                    // master에서 출력 읽기
                    let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: false)

                    // 읽기와 프로세스 대기를 병렬로 수행
                    await withTaskGroup(of: Void.self) { group in
                        // master에서 출력 읽기
                        group.addTask {
                            var buffer = Data()

                            do {
                                for try await byte in masterHandle.bytes {
                                    // \r (0x0D) 또는 \n (0x0A)을 줄 구분자로 처리
                                    if byte == 0x0D || byte == 0x0A {
                                        if buffer.isEmpty { continue }

                                        if let line = String(data: buffer, encoding: .utf8) {
                                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                                            if !trimmed.isEmpty {
                                                Logger.podoSojuKit.debug("📤 pty: \(trimmed)", category: "Process")
                                                continuation.yield(.message(trimmed))
                                            }
                                        }
                                        buffer.removeAll(keepingCapacity: true)
                                    } else {
                                        buffer.append(byte)
                                    }
                                }

                                // 남은 버퍼 처리
                                if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                                    if !trimmed.isEmpty {
                                        continuation.yield(.message(trimmed))
                                    }
                                }
                            } catch {
                                // 프로세스 종료 시 EIO 에러 발생 - 정상
                                if (error as NSError).domain == NSPOSIXErrorDomain &&
                                   (error as NSError).code == Int(EIO) {
                                    Logger.podoSojuKit.debug("PTY read completed (EIO)", category: "Process")
                                } else {
                                    Logger.podoSojuKit.error("PTY read error: \(error)", category: "Process")
                                }
                            }
                        }

                        // 프로세스 종료 대기
                        group.addTask {
                            process.waitUntilExit()
                        }

                        await group.waitForAll()
                    }

                    // 리소스 정리
                    close(master)

                    let exitCode = process.terminationStatus
                    Logger.podoSojuKit.info("PTY process '\(name)' terminated with code \(exitCode)", category: "Process")
                    continuation.yield(.terminated(exitCode))

                } catch {
                    Logger.podoSojuKit.error("💥 PTY process failed: \(error)", category: "Soju")
                    close(slave)
                    close(master)
                    continuation.yield(.terminated(-1))
                }

                continuation.finish()
            }
        }
    }

    /// Soju 버전 확인
    public func checkVersion() async throws -> String {
        let process = Process()
        process.executableURL = wineBinary
        process.arguments = ["--version"]
        process.environment = ProcessInfo.processInfo.environment

        var output: [String] = []
        for await processOutput in try process.runStream(name: "wine --version") {
            switch processOutput {
            case .message(let message):
                output.append(message)
            default:
                break
            }
        }

        var version = output.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        version = version.replacingOccurrences(of: "wine-", with: "")

        return version
    }

    /// Convert Unix path to Windows path using winepath
    /// - Parameters:
    ///   - unixPath: macOS/Unix file path
    ///   - workspace: Target workspace for WINEPREFIX
    /// - Returns: Windows-style path (e.g., "C:\\users\\Public\\Desktop\\file.lnk")
    public func convertToWindowsPath(_ unixPath: String, workspace: Workspace) async throws -> String {
        try validate()

        let winepathBinary = binFolder.appending(path: "winepath")

        let process = Process()
        process.executableURL = winepathBinary
        process.arguments = ["-w", unixPath]
        process.environment = constructEnvironment(for: workspace)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let windowsPath = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !windowsPath.isEmpty else {
            throw SojuError.pathConversionFailed(unixPath)
        }

        Logger.podoSojuKit.debug("Path converted: \(unixPath) -> \(windowsPath)", category: "Soju")
        return windowsPath
    }

    /// Workspace prefix 초기화 (wineboot --init)
    public func initializeWorkspace(_ workspace: Workspace) async throws {
        // prefix 디렉토리가 없으면 생성
        if !FileManager.default.fileExists(atPath: workspace.winePrefixPath) {
            try FileManager.default.createDirectory(
                at: workspace.url,
                withIntermediateDirectories: true
            )
        }

        // wineboot --init 실행
        try await runWineboot(workspace: workspace)

        Logger.podoSojuKit.info("Workspace initialized at \(workspace.winePrefixPath)")
    }

    // MARK: - GPTK Detection and D3DMetal Installation

    /// GPTK (Game Porting Toolkit) 설치 여부 확인
    public func isGPTKInstalled() -> Bool {
        return FileManager.default.fileExists(atPath: "/Applications/Game Porting Toolkit.app")
    }

    /// GPTK 설치 상태 확인
    public func checkGPTKStatus() -> GPTKInstallationStatus {
        let gptkAppPath = "/Applications/Game Porting Toolkit.app"
        let d3dmetalPath = "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external/D3DMetal.framework"

        if !FileManager.default.fileExists(atPath: gptkAppPath) {
            return .notInstalled
        }

        if FileManager.default.fileExists(atPath: d3dmetalPath) {
            // Try to get version from Info.plist
            let infoPlistPath = "\(gptkAppPath)/Contents/Info.plist"
            if let plistData = FileManager.default.contents(atPath: infoPlistPath),
               let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
               let version = plist["CFBundleShortVersionString"] as? String {
                return .installed(version: version)
            }
            return .installed(version: nil)
        }

        return .partiallyInstalled
    }

    /// GPTK에서 D3DMetal 프레임워크를 Soju lib으로 복사
    /// - Returns: 복사된 D3DMetal 경로
    @discardableResult
    public func installD3DMetalFromGPTK() throws -> URL {
        let gptkD3DMetalPath = URL(fileURLWithPath: "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external/D3DMetal.framework")
        let destPath = libFolder.appending(path: "external").appending(path: "D3DMetal.framework")

        guard FileManager.default.fileExists(atPath: gptkD3DMetalPath.path) else {
            throw D3DMetalError.gptkNotInstalled
        }

        // external 디렉토리 생성
        let externalDir = libFolder.appending(path: "external")
        if !FileManager.default.fileExists(atPath: externalDir.path) {
            try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        }

        // 기존 D3DMetal 제거
        if FileManager.default.fileExists(atPath: destPath.path) {
            try FileManager.default.removeItem(at: destPath)
        }

        // 복사
        try FileManager.default.copyItem(at: gptkD3DMetalPath, to: destPath)

        Logger.podoSojuKit.info("D3DMetal.framework installed from GPTK", category: "Soju")
        return destPath
    }

    /// D3DMetal 설치 여부 확인
    public var isD3DMetalInstalled: Bool {
        let d3dmetalPath = libFolder.appending(path: "external").appending(path: "D3DMetal.framework")
        return FileManager.default.fileExists(atPath: d3dmetalPath.path)
    }

    /// D3DMetal 삭제
    public func uninstallD3DMetal() throws {
        let d3dmetalPath = libFolder.appending(path: "external").appending(path: "D3DMetal.framework")
        if FileManager.default.fileExists(atPath: d3dmetalPath.path) {
            try FileManager.default.removeItem(at: d3dmetalPath)
            Logger.podoSojuKit.info("D3DMetal.framework removed", category: "Soju")
        }
    }

    // MARK: - CJK Font Installation

    /// Install CJK (Korean/Japanese/Chinese) fonts to Wine prefix
    /// Copies macOS system Korean fonts to Wine's Fonts directory
    /// - Parameter workspace: Target workspace
    public func installCJKFonts(workspace: Workspace) throws {
        let fontsDest = workspace.winePrefixURL.appending(path: "windows/Fonts")

        // Create Fonts directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: fontsDest.path) {
            try FileManager.default.createDirectory(
                at: fontsDest,
                withIntermediateDirectories: true
            )
        }

        var installedCount = 0

        // 기본 폰트 (다이얼로그, 메뉴 등에 필요)
        let baseFonts: [(path: String, name: String)] = [
            ("/System/Library/Fonts/Helvetica.ttc", "Helvetica.ttc"),
            ("/System/Library/Fonts/Geneva.ttf", "Geneva.ttf"),
            ("/Library/Fonts/Arial Unicode.ttf", "Arial Unicode.ttf"),
            ("/System/Library/Fonts/Supplemental/Tahoma.ttf", "Tahoma.ttf"),
            ("/System/Library/Fonts/Supplemental/Tahoma Bold.ttf", "Tahoma Bold.ttf")
        ]

        for font in baseFonts {
            let source = URL(fileURLWithPath: font.path)
            let dest = fontsDest.appending(path: font.name)

            if FileManager.default.fileExists(atPath: dest.path) {
                continue
            }

            if FileManager.default.fileExists(atPath: source.path) {
                do {
                    try FileManager.default.copyItem(at: source, to: dest)
                    installedCount += 1
                    Logger.podoSojuKit.debug("Installed base font: \(font.name)", category: "Soju")
                } catch {
                    Logger.podoSojuKit.warning("Failed to copy \(font.name): \(error.localizedDescription)", category: "Soju")
                }
            }
        }

        // macOS system Korean fonts to install
        let systemFontsPath = "/System/Library/Fonts/Supplemental"
        let fontsToInstall = [
            "AppleGothic.ttf",
            "AppleMyungjo.ttf"
        ]
        for fontName in fontsToInstall {
            let source = URL(fileURLWithPath: systemFontsPath).appending(path: fontName)
            let dest = fontsDest.appending(path: fontName)

            // Skip if already installed
            if FileManager.default.fileExists(atPath: dest.path) {
                Logger.podoSojuKit.debug("Font already exists: \(fontName)", category: "Soju")
                continue
            }

            // Copy if source exists
            if FileManager.default.fileExists(atPath: source.path) {
                do {
                    try FileManager.default.copyItem(at: source, to: dest)
                    installedCount += 1
                    Logger.podoSojuKit.debug("Installed font: \(fontName)", category: "Soju")
                } catch {
                    Logger.podoSojuKit.warning("Failed to copy font \(fontName): \(error.localizedDescription)", category: "Soju")
                }
            } else {
                Logger.podoSojuKit.warning("System font not found: \(fontName)", category: "Soju")
            }
        }

        // Soju fonts 경로
        let sojuFonts = sojuRoot.appending(path: "share/wine/fonts")

        // msyh.ttf (Microsoft YaHei - Wine 기본 폰트, FontLink에서 참조됨)
        let msyhSource = sojuFonts.appending(path: "msyh.ttf")
        let msyhDest = fontsDest.appending(path: "msyh.ttf")
        if FileManager.default.fileExists(atPath: msyhSource.path) &&
           !FileManager.default.fileExists(atPath: msyhDest.path) {
            do {
                try FileManager.default.copyItem(at: msyhSource, to: msyhDest)
                installedCount += 1
                Logger.podoSojuKit.info("Installed msyh.ttf from Soju", category: "Soju")
            } catch {
                Logger.podoSojuKit.warning("Failed to copy msyh.ttf: \(error.localizedDescription)", category: "Soju")
            }
        }

        // GULIM.TTC (Google Open Source Gulim - 한글 폰트, OFL-1.1 라이센스)
        let gulimSource = sojuFonts.appending(path: "GULIM.TTC")
        let gulimDest = fontsDest.appending(path: "GULIM.TTC")
        if FileManager.default.fileExists(atPath: gulimSource.path) &&
           !FileManager.default.fileExists(atPath: gulimDest.path) {
            do {
                try FileManager.default.copyItem(at: gulimSource, to: gulimDest)
                installedCount += 1
                Logger.podoSojuKit.info("Installed GULIM.TTC from Soju", category: "Soju")
            } catch {
                Logger.podoSojuKit.warning("Failed to copy GULIM.TTC: \(error.localizedDescription)", category: "Soju")
            }
        }

        if installedCount > 0 {
            Logger.podoSojuKit.info("CJK fonts installed: \(installedCount) fonts", category: "Soju")
        } else {
            Logger.podoSojuKit.debug("No new CJK fonts to install", category: "Soju")
        }
    }

    // MARK: - Process Detection

    /// 특정 exe가 실행 중인지 확인
    public func isProcessRunning(exeName: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", exeName]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 특정 exe의 PID 가져오기
    public func getProcessPID(exeName: String) -> pid_t? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", exeName]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let pid = Int32(output.components(separatedBy: .newlines).first ?? "") {
                return pid
            }
        } catch { }
        return nil
    }

    // MARK: - Process Cleanup

    /// 모든 Wine 관련 프로세스 종료
    /// 앱 종료 시 호출하여 orphan 프로세스 방지
    public func killAllWineProcesses() {
        Logger.podoSojuKit.info("🧹 killAllWineProcesses() called", category: "Soju")

        // 1. CGWindowList에서 Wine 창 소유자 PID 찾아서 직접 종료 (좀비 방지)
        Logger.podoSojuKit.debug("Killing Wine window owners...", category: "Soju")
        killWineWindowOwners()

        // 2. Windows 프로세스 강제 종료 (C:\ 경로로 실행된 프로세스)
        Logger.podoSojuKit.debug("Killing Windows processes...", category: "Soju")
        forceKillProcess(pattern: "C:\\\\Program")
        forceKillProcess(pattern: "C:\\\\windows")
        forceKillProcess(pattern: "C:\\\\users")

        // 3. macOS 경로로 실행된 portable exe 종료
        Logger.podoSojuKit.debug("Killing portable exe processes...", category: "Soju")
        forceKillProcess(pattern: "/unix/")  // Wine이 macOS 경로를 /unix/로 참조
        forceKillProcess(pattern: "start /unix")  // wine start /unix 명령
        forceKillProcess(pattern: "com.podosoju.app")  // Programs 폴더 내 exe

        // 4. Wine 관련 프로세스 강제 종료
        Logger.podoSojuKit.debug("Killing Wine processes...", category: "Soju")
        forceKillProcess(pattern: "wineserver")
        forceKillProcess(pattern: "wine64")
        forceKillProcess(pattern: "winedevice")
        forceKillProcess(pattern: "services.exe")
        forceKillProcess(pattern: "plugplay.exe")
        forceKillProcess(pattern: "svchost.exe")
        forceKillProcess(pattern: "rpcss.exe")
        forceKillProcess(pattern: "explorer.exe")

        Logger.podoSojuKit.info("✅ killAllWineProcesses() completed", category: "Soju")
    }

    /// CGWindowList에서 Wine 창 소유자를 찾아 종료
    private func killWineWindowOwners() {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        var killedPIDs: Set<pid_t> = []

        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }

            // Wine 관련 창 찾기
            if ownerName.lowercased().contains("wine") && !killedPIDs.contains(ownerPID) {
                Logger.podoSojuKit.debug("Killing Wine window owner: \(ownerName) (PID: \(ownerPID))", category: "Soju")
                kill(ownerPID, SIGKILL)
                killedPIDs.insert(ownerPID)
            }
        }
    }

    /// 프로세스 강제 종료 (SIGKILL)
    private func forceKillProcess(pattern: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-9", "-f", pattern]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let status = process.terminationStatus
            Logger.podoSojuKit.debug("pkill -9 -f '\(pattern)' → exit \(status)", category: "Soju")
        } catch {
            Logger.podoSojuKit.error("pkill failed for '\(pattern)': \(error)", category: "Soju")
        }
    }

    /// 특정 이름의 프로세스 종료
    /// - Parameter name: 프로세스 이름 (pkill -f 패턴)
    private func killProcess(named name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", name]

        // 출력 무시
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                Logger.podoSojuKit.debug("Killed processes matching '\(name)'", category: "Soju")
            }
        } catch {
            // pkill 실패는 무시 (프로세스가 없는 경우 등)
            Logger.podoSojuKit.debug("No processes matching '\(name)' to kill", category: "Soju")
        }
    }
}

// MARK: - Soju Version

/// Soju 버전 정보 (SemVer)
public struct SojuVersion: Codable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let preRelease: String?
    public let build: String?

    public var versionString: String {
        var version = "\(major).\(minor).\(patch)"
        if let preRelease = preRelease, !preRelease.isEmpty {
            version += "-\(preRelease)"
        }
        if let build = build, !build.isEmpty {
            version += "+\(build)"
        }
        return version
    }
}

// MARK: - Errors

public enum SojuError: LocalizedError {
    case notInstalled
    case notExecutable(String)
    case winebootFailed(Int32)
    case pathConversionFailed(String)
    case winetricksNotFound
    case winetricksFailed(Int32)
    case ptyCreationFailed

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Soju is not installed. Please install Soju first."
        case .notExecutable(let path):
            return "Soju binary at \(path) is not executable."
        case .winebootFailed(let code):
            return "wineboot failed with exit code \(code)"
        case .pathConversionFailed(let path):
            return "Failed to convert path to Windows format: \(path)"
        case .winetricksNotFound:
            return "winetricks not found in Soju installation."
        case .winetricksFailed(let code):
            return "winetricks failed with exit code \(code)"
        case .ptyCreationFailed:
            return "Failed to create pseudo-terminal for process execution."
        }
    }
}

// MARK: - D3DMetal Errors

public enum D3DMetalError: LocalizedError {
    case gptkNotInstalled
    case d3dmetalNotFound
    case installationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .gptkNotInstalled:
            return "Game Porting Toolkit is not installed. Please install GPTK from Apple Developer website."
        case .d3dmetalNotFound:
            return "D3DMetal.framework not found in GPTK installation."
        case .installationFailed(let reason):
            return "D3DMetal installation failed: \(reason)"
        }
    }
}

// MARK: - Process Extensions

extension Process {
    /// Process 실행 후 AsyncStream으로 출력 스트림 반환
    func runStream(name: String, fileHandle: FileHandle? = nil) throws -> AsyncStream<ProcessOutput> {
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        self.standardOutput = stdoutPipe
        self.standardError = stderrPipe

        return AsyncStream { continuation in
            Task {
                continuation.yield(.started)

                // Start process
                do {
                    try self.run()
                } catch {
                    Logger.podoSojuKit.error("Failed to start process: \(error.localizedDescription)", category: "Process")
                    continuation.yield(.terminated(-1))
                    continuation.finish()
                    return
                }

                // Use TaskGroup to ensure all output is read before termination
                await withTaskGroup(of: Void.self) { group in
                    // Read stdout - use custom line reader that handles \r (for wget progress)
                    group.addTask {
                        await Self.readLines(
                            from: stdoutPipe.fileHandleForReading,
                            isError: false,
                            continuation: continuation,
                            fileHandle: fileHandle
                        )
                    }

                    // Read stderr - use custom line reader that handles \r (for wget progress)
                    group.addTask {
                        await Self.readLines(
                            from: stderrPipe.fileHandleForReading,
                            isError: true,
                            continuation: continuation,
                            fileHandle: fileHandle
                        )
                    }

                    // Wait for process to finish
                    group.addTask {
                        self.waitUntilExit()
                    }

                    // Wait for all tasks to complete
                    await group.waitForAll()
                }

                // Only send terminated after all output is read
                Logger.podoSojuKit.info("Process '\(name)' terminated with code \(self.terminationStatus)", category: "Process")
                continuation.yield(.terminated(self.terminationStatus))
                continuation.finish()
            }
        }
    }

    /// Read lines from file handle, treating both \r and \n as line separators
    /// This is necessary for wget progress which uses \r to update the same line
    private static func readLines(
        from handle: FileHandle,
        isError: Bool,
        continuation: AsyncStream<ProcessOutput>.Continuation,
        fileHandle: FileHandle?
    ) async {
        var buffer = Data()
        let streamType = isError ? "stderr" : "stdout"

        do {
            for try await byte in handle.bytes {
                // Check for line separators: \r (0x0D) or \n (0x0A)
                if byte == 0x0D || byte == 0x0A {
                    // Skip empty lines
                    if buffer.isEmpty { continue }

                    if let line = String(data: buffer, encoding: .utf8) {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            Logger.podoSojuKit.debug("📤 \(streamType): \(trimmed)", category: "Process")
                            if isError {
                                continuation.yield(.error(trimmed))
                                fileHandle?.write(Data(("[ERROR] " + trimmed + "\n").utf8))
                            } else {
                                continuation.yield(.message(trimmed))
                                fileHandle?.write(Data((trimmed + "\n").utf8))
                            }
                        }
                    }
                    buffer.removeAll(keepingCapacity: true)
                } else {
                    buffer.append(byte)
                }
            }

            // Handle any remaining data in buffer
            if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    Logger.podoSojuKit.debug("📤 \(streamType): \(trimmed)", category: "Process")
                    if isError {
                        continuation.yield(.error(trimmed))
                    } else {
                        continuation.yield(.message(trimmed))
                    }
                }
            }
        } catch {
            Logger.podoSojuKit.error("Error reading \(streamType): \(error.localizedDescription)", category: "Process")
        }
    }
}

// MARK: - Process Output

/// 프로세스 출력 타입
public enum ProcessOutput {
    case started
    case message(String)
    case error(String)
    case terminated(Int32)
}

// MARK: - Install Progress

/// winetricks 설치 진행 상황
public enum InstallProgress: Sendable {
    case downloading(percent: Int)
    case installing
}
