#!/usr/bin/env swift

import Foundation

// PodoSoju 설치 확인 스크립트

let podoSojuPath = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Library")
    .appendingPathComponent("Application Support")
    .appendingPathComponent("com.soju.app")
    .appendingPathComponent("Libraries")
    .appendingPathComponent("PodoSoju")

let wineBinary = podoSojuPath.appendingPathComponent("bin").appendingPathComponent("wine")
let versionPlist = podoSojuPath.deletingLastPathComponent().appendingPathComponent("PodoSojuVersion.plist")

print("=== PodoSoju 설치 확인 ===")
print("PodoSoju Path: \(podoSojuPath.path)")
print("Wine Binary: \(wineBinary.path)")

// 1. 설치 확인
let fileManager = FileManager.default
guard fileManager.fileExists(atPath: wineBinary.path) else {
    print("❌ PodoSoju가 설치되지 않았습니다.")
    exit(1)
}

print("✅ PodoSoju 설치 확인")

// 2. 실행 권한 확인
guard fileManager.isExecutableFile(atPath: wineBinary.path) else {
    print("❌ Wine 바이너리 실행 권한 없음")
    exit(1)
}

print("✅ 실행 권한 확인")

// 3. 버전 정보 로드
if fileManager.fileExists(atPath: versionPlist.path) {
    do {
        let data = try Data(contentsOf: versionPlist)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]

        if let versionDict = plist["version"] as? [String: Any] {
            let major = versionDict["major"] as? Int ?? 0
            let minor = versionDict["minor"] as? Int ?? 0
            let patch = versionDict["patch"] as? Int ?? 0
            let preRelease = versionDict["preRelease"] as? String ?? ""
            let build = versionDict["build"] as? String ?? ""

            var version = "\(major).\(minor).\(patch)"
            if !preRelease.isEmpty {
                version += "-\(preRelease)"
            }
            if !build.isEmpty {
                version += "+\(build)"
            }

            print("✅ PodoSoju 버전: \(version)")
        }
    } catch {
        print("⚠️ 버전 정보 로드 실패: \(error)")
    }
} else {
    print("⚠️ 버전 정보 파일 없음")
}

// 4. wine --version 실행 테스트
print("\n=== wine --version 테스트 ===")

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
process.arguments = ["-x86_64", wineBinary.path, "--version"]

let pipe = Pipe()
process.standardOutput = pipe

do {
    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
        print("✅ Wine 버전: \(output)")
    }

    if process.terminationStatus == 0 {
        print("✅ 모든 테스트 성공")
    } else {
        print("❌ wine 실행 실패 (exit code: \(process.terminationStatus))")
        exit(1)
    }
} catch {
    print("❌ wine 실행 오류: \(error)")
    exit(1)
}
