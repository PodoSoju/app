//
//  SojuDownloadManager.swift
//  PodoSojuKit
//
//  Created on 2026-01-09.
//

import Foundation
import os.log

// MARK: - Download State

/// 다운로드 상태
public enum DownloadState: Sendable {
    case idle
    case checking
    case downloading(progress: Double)
    case extracting
    case installing
    case completed
    case failed(Error)

    public var isInProgress: Bool {
        switch self {
        case .checking, .downloading, .extracting, .installing:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }
}

// MARK: - Download Error

/// 다운로드 관련 에러
public enum DownloadError: LocalizedError {
    case networkError(Error)
    case noReleaseFound
    case noCompatibleAsset
    case downloadFailed(String)
    case extractionFailed(String)
    case installationFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .noReleaseFound:
            return "No release found on GitHub"
        case .noCompatibleAsset:
            return "No compatible download asset found"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .extractionFailed(let reason):
            return "Extraction failed: \(reason)"
        case .installationFailed(let reason):
            return "Installation failed: \(reason)"
        case .cancelled:
            return "Download was cancelled"
        }
    }
}

// MARK: - Soju Download Manager

/// Soju GitHub 릴리즈 다운로드 및 설치 관리자
@MainActor
public final class SojuDownloadManager: ObservableObject {
    // MARK: - Singleton

    public static let shared = SojuDownloadManager()

    // MARK: - Constants

    private let githubOwner = "PodoSoju"
    private let githubRepo = "soju"
    private let assetNamePattern = "Soju"  // tar.gz 파일명에 포함될 패턴

    // MARK: - Published Properties

    @Published public private(set) var state: DownloadState = .idle
    @Published public private(set) var downloadProgress: Double = 0
    @Published public private(set) var currentVersion: String?
    @Published public private(set) var latestRelease: GitHubRelease?
    @Published public private(set) var allReleases: [GitHubRelease] = []

    // MARK: - Private Properties

    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    // MARK: - Initialization

    private init() {
        // 현재 설치된 버전 확인
        loadCurrentVersion()
    }

    // MARK: - Public Methods

    /// 최신 릴리즈 확인
    /// - Returns: 새 버전이 있으면 GitHubRelease, 없으면 nil
    public func checkForUpdate() async throws -> GitHubRelease? {
        state = .checking

        do {
            let release = try await fetchLatestRelease()
            latestRelease = release

            // 현재 버전과 비교
            if let current = currentVersion {
                if release.version != current {
                    Logger.podoSojuKit.info("Update available: \(current) -> \(release.version)", category: "Download")
                    state = .idle
                    return release
                } else {
                    Logger.podoSojuKit.info("Already up to date: \(current)", category: "Download")
                    state = .idle
                    return nil
                }
            } else {
                // 설치 안됨
                Logger.podoSojuKit.info("Soju not installed, latest version: \(release.version)", category: "Download")
                state = .idle
                return release
            }
        } catch {
            state = .failed(error)
            throw error
        }
    }

    /// 최신 버전 다운로드 및 설치
    public func downloadLatest() async throws {
        let release: GitHubRelease
        if let cached = latestRelease {
            release = cached
        } else {
            release = try await fetchLatestRelease()
        }

        // tar.gz 에셋 찾기
        guard let asset = release.assets.first(where: {
            $0.name.contains(assetNamePattern) && $0.name.hasSuffix(".tar.gz")
        }) else {
            throw DownloadError.noCompatibleAsset
        }

        guard let downloadURL = asset.downloadURL else {
            throw DownloadError.noCompatibleAsset
        }

        Logger.podoSojuKit.info("Starting download: \(asset.name) (\(asset.formattedSize))", category: "Download")

        // 다운로드 시작
        state = .downloading(progress: 0)
        downloadProgress = 0

        let tempURL = try await downloadFile(from: downloadURL, expectedSize: asset.size)

        // 압축 해제 및 설치
        state = .extracting
        try await extractAndInstall(tempURL, version: release.version)

        // 완료
        currentVersion = release.version
        await SojuManager.shared.reloadVersion()
        state = .completed
        Logger.podoSojuKit.info("Soju \(release.version) installed successfully", category: "Download")
    }

    /// 다운로드 취소
    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        progressObservation?.invalidate()
        progressObservation = nil
        state = .idle
        downloadProgress = 0
        Logger.podoSojuKit.info("Download cancelled", category: "Download")
    }

    /// 설치 여부 확인
    public var isInstalled: Bool {
        return SojuManager.shared.isInstalled
    }

    /// 모든 릴리즈 가져오기
    public func fetchAllReleases() async throws {
        state = .checking

        do {
            let releases = try await fetchReleases()
            allReleases = releases
            if let first = releases.first {
                latestRelease = first
            }
            state = .idle
            Logger.podoSojuKit.info("Fetched \(releases.count) releases", category: "Download")
        } catch {
            state = .failed(error)
            throw error
        }
    }

    /// 특정 릴리즈 다운로드 및 설치
    public func downloadRelease(_ release: GitHubRelease) async throws {
        // tar.gz 에셋 찾기
        guard let asset = release.assets.first(where: {
            $0.name.contains(assetNamePattern) && $0.name.hasSuffix(".tar.gz")
        }) else {
            throw DownloadError.noCompatibleAsset
        }

        guard let downloadURL = asset.downloadURL else {
            throw DownloadError.noCompatibleAsset
        }

        Logger.podoSojuKit.info("Starting download: \(asset.name) (\(asset.formattedSize))", category: "Download")

        // 다운로드 시작
        state = .downloading(progress: 0)
        downloadProgress = 0

        let tempURL = try await downloadFile(from: downloadURL, expectedSize: asset.size)

        // 압축 해제 및 설치
        state = .extracting
        try await extractAndInstall(tempURL, version: release.version)

        // 완료
        currentVersion = release.version
        await SojuManager.shared.reloadVersion()
        state = .completed
        Logger.podoSojuKit.info("Soju \(release.version) installed successfully", category: "Download")
    }

    // MARK: - Private Methods

    /// GitHub API에서 모든 릴리즈 정보 가져오기 (prerelease 포함)
    private func fetchReleases() async throws -> [GitHubRelease] {
        let urlString = "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases"
        guard let url = URL(string: urlString) else {
            throw DownloadError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Soju-App", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(GitHubErrorResponse.self, from: data) {
                throw DownloadError.downloadFailed(errorResponse.message)
            }
            throw DownloadError.downloadFailed("HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let releases = try decoder.decode([GitHubRelease].self, from: data)

        // publishedAt 기준 내림차순 정렬 (최신순)
        return releases.sorted {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }
    }

    /// 최신 릴리즈 가져오기
    private func fetchLatestRelease() async throws -> GitHubRelease {
        let releases = try await fetchReleases()
        guard let latest = releases.first else {
            throw DownloadError.noReleaseFound
        }
        return latest
    }

    /// 파일 다운로드
    private func downloadFile(from url: URL, expectedSize: Int64) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let session = URLSession(configuration: .default)
            let task = session.downloadTask(with: url) { localURL, response, error in
                if let error = error {
                    if (error as NSError).code == NSURLErrorCancelled {
                        continuation.resume(throwing: DownloadError.cancelled)
                    } else {
                        continuation.resume(throwing: DownloadError.networkError(error))
                    }
                    return
                }

                guard let localURL = localURL else {
                    continuation.resume(throwing: DownloadError.downloadFailed("No file received"))
                    return
                }

                // 임시 디렉토리로 복사
                let tempDir = FileManager.default.temporaryDirectory
                let destURL = tempDir.appending(path: "soju-\(UUID().uuidString).tar.gz")

                do {
                    try FileManager.default.moveItem(at: localURL, to: destURL)
                    continuation.resume(returning: destURL)
                } catch {
                    continuation.resume(throwing: DownloadError.downloadFailed(error.localizedDescription))
                }
            }

            // 진행률 관찰
            self.progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                Task { @MainActor in
                    self?.downloadProgress = progress.fractionCompleted
                    self?.state = .downloading(progress: progress.fractionCompleted)
                }
            }

            self.downloadTask = task
            task.resume()
        }
    }

    /// tar.gz 압축 해제 및 설치
    private func extractAndInstall(_ archiveURL: URL, version: String) async throws {
        let librariesPath = SojuManager.shared.sojuRoot.deletingLastPathComponent()
        let sojuPath = SojuManager.shared.sojuRoot

        // 기존 설치 제거
        if FileManager.default.fileExists(atPath: sojuPath.path) {
            try FileManager.default.removeItem(at: sojuPath)
        }

        // Libraries 디렉토리 생성
        try FileManager.default.createDirectory(at: librariesPath, withIntermediateDirectories: true)

        state = .extracting

        // tar 명령어로 압축 해제
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archiveURL.path, "-C", librariesPath.path, "--strip-components=1"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw DownloadError.extractionFailed("tar command failed with exit code \(process.terminationStatus)")
        }

        // 압축 해제된 디렉토리 이름 확인 및 이름 변경
        // soju-x.x.x 형태로 압축 해제될 수 있음
        let contents = try FileManager.default.contentsOfDirectory(at: librariesPath, includingPropertiesForKeys: nil)
        if let extractedDir = contents.first(where: { $0.lastPathComponent.hasPrefix("soju") && $0.lastPathComponent != "Soju" }) {
            // Soju로 이름 변경
            try FileManager.default.moveItem(at: extractedDir, to: sojuPath)
        }

        state = .installing

        // 버전 정보 저장
        try saveVersion(version)

        // 임시 파일 정리
        try? FileManager.default.removeItem(at: archiveURL)

        Logger.podoSojuKit.info("Soju extracted to \(sojuPath.path)", category: "Download")
    }

    /// 현재 설치된 버전 로드
    private func loadCurrentVersion() {
        currentVersion = SojuManager.shared.version?.versionString
    }

    /// 버전 정보 저장
    private func saveVersion(_ version: String) throws {
        let versionPlistURL = SojuManager.shared.sojuRoot.deletingLastPathComponent()
            .appending(path: "SojuVersion.plist")

        // 버전 문자열 파싱
        let components = version.split(separator: ".")
        let major = Int(components[safe: 0] ?? "0") ?? 0
        let minor = Int(components[safe: 1] ?? "0") ?? 0
        let patch = Int(components[safe: 2]?.split(separator: "-").first ?? "0") ?? 0
        let preRelease = version.contains("-") ? String(version.split(separator: "-").last ?? "") : nil

        let versionInfo = SojuVersion(
            major: major,
            minor: minor,
            patch: patch,
            preRelease: preRelease,
            build: nil
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(["version": versionInfo])
        try data.write(to: versionPlistURL)
    }
}

// MARK: - Collection Extension

private extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
