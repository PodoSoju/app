//
//  LogModalView.swift
//  PodoSoju
//
//  Created on 2026-01-11.
//

import SwiftUI
import PodoSojuKit
import os.log

/// 로그 파일 내용을 모달로 표시하는 뷰
struct LogModalView: View {
    let logURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var logContent: String = ""
    @State private var isLoading: Bool = true
    @State private var searchText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Wine Log")
                    .font(.headline)
                Spacer()
                Text(logURL.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Log content
            if isLoading {
                Spacer()
                ProgressView("Loading logs...")
                Spacer()
            } else if logContent.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No log content")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                TextEditor(text: .constant(filteredContent))
                    .font(.system(.caption, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
            }

            Divider()

            // Footer buttons
            HStack {
                Button("Clear Logs") {
                    clearLogs()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)

                Spacer()

                Button("Open in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([logURL])
                }
                .buttonStyle(.bordered)

                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logContent, forType: .string)
                }
                .buttonStyle(.bordered)

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.escape)
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            loadLogContent()
        }
    }

    // MARK: - Computed Properties

    private var filteredContent: String {
        guard !searchText.isEmpty else { return logContent }
        return logContent
            .components(separatedBy: "\n")
            .filter { $0.localizedCaseInsensitiveContains(searchText) }
            .joined(separator: "\n")
    }

    // MARK: - Actions

    private func loadLogContent() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // 파일 크기 확인 - 1MB 초과 시 마지막 부분만 읽기
                let attributes = try FileManager.default.attributesOfItem(atPath: logURL.path)
                let fileSize = attributes[.size] as? Int ?? 0
                let maxSize = 1_000_000 // 1MB

                var content: String
                if fileSize > maxSize {
                    // 마지막 1MB만 읽기
                    let fileHandle = try FileHandle(forReadingFrom: logURL)
                    fileHandle.seek(toFileOffset: UInt64(fileSize - maxSize))
                    let data = fileHandle.readDataToEndOfFile()
                    content = "[... 앞부분 생략 (파일 크기: \(fileSize / 1024)KB) ...]\n\n"
                    content += String(data: data, encoding: .utf8) ?? "Unable to decode"
                    fileHandle.closeFile()
                } else {
                    content = try String(contentsOf: logURL, encoding: .utf8)
                }

                DispatchQueue.main.async {
                    self.logContent = content
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.logContent = "Failed to load log: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func clearLogs() {
        do {
            try "".write(to: logURL, atomically: true, encoding: .utf8)
            logContent = ""
            Logger.podoSojuKit.info("Log file cleared: \(logURL.lastPathComponent)", category: "LogModal")
        } catch {
            Logger.podoSojuKit.error("Failed to clear log: \(error.localizedDescription)", category: "LogModal")
        }
    }
}

// MARK: - Preview

#Preview {
    LogModalView(logURL: Logger.logFileURL)
}
