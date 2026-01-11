//
//  WineAppMonitor.swift
//  PodoSoju
//
//  Created on 2026-01-11.
//

import AppKit
import Combine
import PodoSojuKit
import os.log

/// Wine 앱 실행/종료 실시간 감시
@MainActor
public class WineAppMonitor: ObservableObject {
    public static let shared = WineAppMonitor()

    /// 현재 실행 중인 Wine 관련 프로세스
    @Published public private(set) var runningWineProcesses: [NSRunningApplication] = []

    /// Wine 앱 실행 알림
    public let appLaunched = PassthroughSubject<NSRunningApplication, Never>()

    /// Wine 앱 종료 알림
    public let appTerminated = PassthroughSubject<NSRunningApplication, Never>()

    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// 감시 시작
    public func startMonitoring() {
        Logger.podoSojuKit.info("WineAppMonitor: Starting monitoring", category: "WineAppMonitor")

        // 현재 실행 중인 Wine 프로세스 수집
        updateRunningWineProcesses()

        // 앱 시작 감시
        let launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }

            if self.isWineRelatedProcess(app) {
                self.runningWineProcesses.append(app)
                self.appLaunched.send(app)
                Logger.podoSojuKit.info("Wine process launched: \(app.localizedName ?? "unknown") (PID: \(app.processIdentifier))", category: "WineAppMonitor")
            }
        }
        observers.append(launchObserver)

        // 앱 종료 감시
        let terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }

            if let index = self.runningWineProcesses.firstIndex(where: { $0.processIdentifier == app.processIdentifier }) {
                self.runningWineProcesses.remove(at: index)
                self.appTerminated.send(app)
                Logger.podoSojuKit.info("Wine process terminated: \(app.localizedName ?? "unknown") (PID: \(app.processIdentifier))", category: "WineAppMonitor")
            }
        }
        observers.append(terminateObserver)
    }

    /// 감시 중지
    public func stopMonitoring() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        Logger.podoSojuKit.info("WineAppMonitor: Stopped monitoring", category: "WineAppMonitor")
    }

    /// 현재 실행 중인 Wine 프로세스 갱신
    public func updateRunningWineProcesses() {
        runningWineProcesses = NSWorkspace.shared.runningApplications.filter { isWineRelatedProcess($0) }
        Logger.podoSojuKit.debug("Wine processes count: \(runningWineProcesses.count)", category: "WineAppMonitor")
    }

    /// Wine 관련 프로세스인지 확인
    private func isWineRelatedProcess(_ app: NSRunningApplication) -> Bool {
        let name = app.localizedName?.lowercased() ?? ""
        let execName = app.executableURL?.lastPathComponent.lowercased() ?? ""

        let wineKeywords = ["wine", "wineserver", "winedevice", "start.exe", "explorer.exe", "services.exe"]

        return wineKeywords.contains { name.contains($0) || execName.contains($0) }
    }

    /// 특정 PID의 Wine 프로세스가 실행 중인지 확인
    public func isWineProcessRunning(pid: pid_t) -> Bool {
        return runningWineProcesses.contains { $0.processIdentifier == pid }
    }

}
