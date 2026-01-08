//
//  PodoSojuManager.swift
//  SojuKit
//
//  Created on 2026-01-07.
//

import Foundation
import os.log

/// PodoSoju (Wine alternative) 관리자
/// - PodoSoju 바이너리 경로 관리
/// - 환경 변수 설정 (WINEPREFIX, DXVK 등)
/// - 프로세스 실행 관리
public final class PodoSojuManager: @unchecked Sendable {
    // MARK: - Singleton

    public static let shared = PodoSojuManager()

    // MARK: - Properties

    /// PodoSoju 설치 루트 디렉토리
    /// ~/Library/Application Support/com.soju.app/PodoSoju
    public let podoSojuRoot: URL

    /// PodoSoju bin 디렉토리
    public let binFolder: URL

    /// PodoSoju lib 디렉토리
    public let libFolder: URL

    /// wine64 바이너리 경로
    public let wineBinary: URL

    /// wineserver 바이너리 경로
    public let wineserverBinary: URL

    /// wineboot 바이너리 경로
    public let winebootBinary: URL

    /// PodoSoju 버전 정보
    public private(set) var version: PodoSojuVersion?

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

        let bundleId = Bundle.main.bundleIdentifier ?? "com.soju.app"

        self.podoSojuRoot = appSupport
            .appending(path: bundleId)
            .appending(path: "Libraries")
            .appending(path: "PodoSoju")

        self.binFolder = podoSojuRoot.appending(path: "bin")
        self.libFolder = podoSojuRoot.appending(path: "lib")
        self.wineBinary = binFolder.appending(path: "wine")
        self.wineserverBinary = binFolder.appending(path: "wineserver")
        self.winebootBinary = binFolder.appending(path: "wineboot")


        // Debug logging
        Logger.sojuKit.info("🏠 App Support: \(appSupport.path)", category: "PodoSoju")
        Logger.sojuKit.info("🍇 PodoSoju root: \(podoSojuRoot.path)", category: "PodoSoju")
        Logger.sojuKit.info("🍷 Wine binary: \(wineBinary.path)", category: "PodoSoju")

        // Check if files exist
        let wineExists = FileManager.default.fileExists(atPath: wineBinary.path)
        let isExecutable = FileManager.default.isExecutableFile(atPath: wineBinary.path)
        Logger.sojuKit.info("✅ Wine exists: \(wineExists), executable: \(isExecutable)", category: "PodoSoju")

        // 버전 정보 로드
        self.version = loadVersion()
    }

    // MARK: - Version Loading

    /// PodoSojuVersion.plist에서 버전 정보 로드
    private func loadVersion() -> PodoSojuVersion? {
        let versionPlistURL = podoSojuRoot.deletingLastPathComponent()
            .appending(path: "PodoSojuVersion.plist")

        guard FileManager.default.fileExists(atPath: versionPlistURL.path) else {
            Logger.sojuKit.warning("PodoSojuVersion.plist not found at \(versionPlistURL.path)")
            return nil
        }

        do {
            let data = try Data(contentsOf: versionPlistURL)
            let decoder = PropertyListDecoder()
            let versionDict = try decoder.decode([String: PodoSojuVersion].self, from: data)
            return versionDict["version"]
        } catch {
            Logger.sojuKit.error("Failed to load PodoSoju version: \(error)")
            return nil
        }
    }

    // MARK: - Installation Check

    /// PodoSoju가 설치되어 있는지 확인
    public var isInstalled: Bool {
        return FileManager.default.fileExists(atPath: wineBinary.path)
    }

    /// PodoSoju 설치 여부 및 실행 가능 여부 검증
    public func validate() throws {
        guard isInstalled else {
            throw PodoSojuError.notInstalled
        }

        guard FileManager.default.isExecutableFile(atPath: wineBinary.path) else {
            throw PodoSojuError.notExecutable(wineBinary.path)
        }
    }

    // MARK: - Environment Construction

    /// Workspace에 대한 PodoSoju 환경 변수 생성
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

        // TMPDIR 설정 (샌드박스 호환성)
        // Wine이 /tmp 대신 컨테이너 내부 임시 디렉토리 사용하도록 설정
        let containerTmp = FileManager.default.temporaryDirectory.path
        env["TMPDIR"] = containerTmp
        Logger.sojuKit.debug("TMPDIR set to: \(containerTmp)", category: "PodoSoju")

        // Wine 디버그 출력 설정
        #if DEBUG
        // Debug 빌드: 상세한 디버그 출력
        env["WINEDEBUG"] = "+all"
        Logger.sojuKit.debug("Wine debug mode enabled: +all", category: "PodoSoju")
        #else
        // Release 빌드: 경고만 표시 (fixme 제외)
        env["WINEDEBUG"] = "warn+all,fixme-all"
        #endif

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
    /// - Returns: 프로세스 출력 스트림
    public func runWine(
        args: [String],
        workspace: Workspace,
        additionalEnv: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        try validate()
        
        Logger.sojuKit.info("🍷 Running Wine with args: \(args.joined(separator: " "))", category: "PodoSoju")
        Logger.sojuKit.debug("Wine binary: \(wineBinary.path(percentEncoded: false))", category: "PodoSoju")
        Logger.sojuKit.debug("Working directory: \(workspace.url.path(percentEncoded: false))", category: "PodoSoju")

        let process = Process()
        process.executableURL = wineBinary
        process.arguments = args
        process.currentDirectoryURL = workspace.url
        process.environment = constructEnvironment(for: workspace, additionalEnv: additionalEnv)
        process.qualityOfService = .userInitiated

        Logger.sojuKit.info("🚀 Starting Wine process...", category: "PodoSoju")

        return try process.runStream(name: args.joined(separator: " "))
    }

    /// wineboot 실행 (prefix 초기화)
    /// - Parameter workspace: 대상 Workspace
    public func runWineboot(workspace: Workspace) async throws {
        try validate()

        Logger.sojuKit.info("Initializing Wine prefix at \(workspace.winePrefixPath)")

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
            Logger.sojuKit.info("wineboot process started in background")
        } catch {
            Logger.sojuKit.error("Failed to start wineboot: \(error.localizedDescription)")
            throw PodoSojuError.winebootFailed(-1)
        }

        // drive_c 디렉토리가 생성될 때까지 대기 (최대 10초)
        let driveCPath = (workspace.winePrefixPath as NSString).appendingPathComponent("drive_c")
        let maxAttempts = 100 // 100 * 100ms = 10초
        var attempts = 0

        while attempts < maxAttempts {
            if FileManager.default.fileExists(atPath: driveCPath) {
                Logger.sojuKit.info("Wine prefix initialized successfully (drive_c created)")
                return
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            attempts += 1
        }

        // 타임아웃 후에도 drive_c가 없으면 실패
        Logger.sojuKit.error("wineboot timeout: drive_c directory not created after 10 seconds")
        throw PodoSojuError.winebootFailed(-1)
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

    /// PodoSoju 버전 확인
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

        Logger.sojuKit.info("Workspace initialized at \(workspace.winePrefixPath)")
    }
}

// MARK: - PodoSoju Version

/// PodoSoju 버전 정보 (SemVer)
public struct PodoSojuVersion: Codable {
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

public enum PodoSojuError: LocalizedError {
    case notInstalled
    case notExecutable(String)
    case winebootFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "PodoSoju is not installed. Please install PodoSoju first."
        case .notExecutable(let path):
            return "PodoSoju binary at \(path) is not executable."
        case .winebootFailed(let code):
            return "wineboot failed with exit code \(code)"
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
                    Logger.sojuKit.error("Failed to start process: \(error.localizedDescription)", category: "Process")
                    continuation.yield(.terminated(-1))
                    continuation.finish()
                    return
                }

                // Use TaskGroup to ensure all output is read before termination
                await withTaskGroup(of: Void.self) { group in
                    // Read stdout
                    group.addTask {
                        do {
                            for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                                Logger.sojuKit.debug("📤 stdout: \(line)", category: "Process")
                                continuation.yield(.message(line))
                                fileHandle?.write(Data((line + "\n").utf8))
                            }
                        } catch {
                            Logger.sojuKit.error("Error reading stdout: \(error.localizedDescription)", category: "Process")
                        }
                    }

                    // Read stderr
                    group.addTask {
                        do {
                            for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                                Logger.sojuKit.debug("📤 stderr: \(line)", category: "Process")
                                continuation.yield(.error(line))
                                fileHandle?.write(Data(("[ERROR] " + line + "\n").utf8))
                            }
                        } catch {
                            Logger.sojuKit.error("Error reading stderr: \(error.localizedDescription)", category: "Process")
                        }
                    }

                    // Wait for process to finish
                    group.addTask {
                        self.waitUntilExit()
                    }

                    // Wait for all tasks to complete
                    await group.waitForAll()
                }

                // Only send terminated after all output is read
                Logger.sojuKit.info("Process '\(name)' terminated with code \(self.terminationStatus)", category: "Process")
                continuation.yield(.terminated(self.terminationStatus))
                continuation.finish()
            }
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
