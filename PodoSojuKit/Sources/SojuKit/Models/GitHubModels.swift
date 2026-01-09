//
//  GitHubModels.swift
//  SojuKit
//
//  Created on 2026-01-09.
//

import Foundation

// MARK: - GitHub Release

/// GitHub Release 정보
public struct GitHubRelease: Codable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let prerelease: Bool
    public let createdAt: Date
    public let publishedAt: Date?
    public let assets: [ReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case prerelease
        case createdAt = "created_at"
        case publishedAt = "published_at"
        case assets
    }

    /// 버전 문자열 (v 접두사 제거)
    public var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
}

// MARK: - Release Asset

/// GitHub Release Asset 정보
public struct ReleaseAsset: Codable, Sendable {
    public let id: Int
    public let name: String
    public let contentType: String
    public let size: Int64
    public let downloadCount: Int
    public let browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case contentType = "content_type"
        case size
        case downloadCount = "download_count"
        case browserDownloadUrl = "browser_download_url"
    }

    /// 다운로드 URL
    public var downloadURL: URL? {
        URL(string: browserDownloadUrl)
    }

    /// 사람이 읽기 쉬운 파일 크기
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - GitHub API Response

/// GitHub API 에러 응답
public struct GitHubErrorResponse: Codable, Sendable {
    public let message: String
    public let documentationUrl: String?

    enum CodingKeys: String, CodingKey {
        case message
        case documentationUrl = "documentation_url"
    }
}
