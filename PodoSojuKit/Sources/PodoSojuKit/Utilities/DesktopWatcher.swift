//
//  DesktopWatcher.swift
//  PodoSojuKit
//
//  Created on 2026-01-10.
//

import Foundation
import Combine
import os.log

/// Watches Wine Desktop folders for new .lnk files and notifies when changes occur
public final class DesktopWatcher: @unchecked Sendable {

    private var fileDescriptors: [Int32] = []
    private var dispatchSources: [DispatchSourceFileSystemObject] = []
    private var watchedPaths: [URL] = []
    private var isWatching = false
    private let queue = DispatchQueue(label: "com.podosoju.desktopwatcher", qos: .utility)

    /// Publisher that emits when desktop contents change
    public let desktopChanged = PassthroughSubject<Void, Never>()

    public init() {}

    deinit {
        stopWatching()
    }

    // MARK: - Public API

    /// Start watching Desktop folders for a workspace
    public func startWatching(prefixURL: URL) {
        guard !isWatching else { return }
        isWatching = true

        // Get desktop paths to watch
        let desktopPaths = getDesktopPaths(prefixURL: prefixURL)
        watchedPaths = desktopPaths

        Logger.podoSojuKit.info("Starting desktop watch for \(desktopPaths.count) paths", category: "DesktopWatcher")

        for path in desktopPaths {
            watchDirectory(at: path)
        }
    }

    /// Stop watching
    public func stopWatching() {
        isWatching = false

        for source in dispatchSources {
            source.cancel()
        }
        dispatchSources.removeAll()

        for fd in fileDescriptors {
            close(fd)
        }
        fileDescriptors.removeAll()
        watchedPaths.removeAll()

        Logger.podoSojuKit.info("Stopped desktop watch", category: "DesktopWatcher")
    }

    // MARK: - Private Methods

    private func getDesktopPaths(prefixURL: URL) -> [URL] {
        var paths: [URL] = []

        // Common desktop paths
        let desktopPaths = [
            "users/Public/Desktop",
            "ProgramData/Microsoft/Windows/Start Menu/Programs"
        ]

        for relativePath in desktopPaths {
            let url = prefixURL.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: url.path) {
                paths.append(url)
            }
        }

        // User-specific desktops
        let usersDir = prefixURL.appendingPathComponent("users")
        if let userDirs = try? FileManager.default.contentsOfDirectory(
            at: usersDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for userDir in userDirs {
                let username = userDir.lastPathComponent
                if username != "Public" && username != "crossover" {
                    let desktopURL = userDir.appendingPathComponent("Desktop")
                    // Skip symlinks to avoid watching macOS folders
                    if FileManager.default.fileExists(atPath: desktopURL.path),
                       let attrs = try? FileManager.default.attributesOfItem(atPath: desktopURL.path),
                       let fileType = attrs[.type] as? FileAttributeType,
                       fileType != .typeSymbolicLink {
                        paths.append(desktopURL)
                    }
                }
            }
        }

        return paths
    }

    private func watchDirectory(at url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            Logger.podoSojuKit.warning("Failed to open \(url.path) for watching", category: "DesktopWatcher")
            return
        }

        fileDescriptors.append(fd)

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.handleDirectoryChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        dispatchSources.append(source)

        Logger.podoSojuKit.debug("Watching: \(url.path)", category: "DesktopWatcher")
    }

    private func handleDirectoryChange() {
        Logger.podoSojuKit.debug("Desktop folder changed, notifying...", category: "DesktopWatcher")

        // Debounce - wait a bit for file operations to complete
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.desktopChanged.send()
        }
    }
}
