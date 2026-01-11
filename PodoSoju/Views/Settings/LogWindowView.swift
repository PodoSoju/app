//
//  LogWindowView.swift
//  PodoSoju
//
//  Created on 2026-01-11.
//

import SwiftUI
import PodoSojuKit
import os.log

/// 별도 창으로 로그를 표시하는 뷰 (실시간 업데이트)
struct LogWindowView: View {
    @State private var logLines: [String] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var autoScroll = true

    private let logURL = Logger.logFileURL
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search...", text: $searchText)
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
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .frame(maxWidth: 300)

                Spacer()

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)

                Text("\(filteredLines.count) lines")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    clearLogs()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Clear Logs")

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([logURL])
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open in Finder")

                Button {
                    loadLogs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
            .padding(8)

            Divider()

            // Log content (newest first)
            if isLoading {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else if logLines.isEmpty {
                Spacer()
                Text("No logs")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                // 최신 로그가 위로 오도록 역순 + 복사 가능하게 TextEditor 사용
                let reversedContent = filteredLines.reversed().joined(separator: "\n")
                TextEditor(text: .constant(reversedContent))
                    .font(.system(.caption, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            loadLogs()
        }
        .onReceive(timer) { _ in
            if autoScroll {
                loadLogs()
            }
        }
    }

    // MARK: - Computed

    private var filteredLines: [String] {
        guard !searchText.isEmpty else { return logLines }
        return logLines.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private func lineColor(for line: String) -> Color {
        if line.contains(":err:") || line.contains("ERROR") || line.contains("error:") {
            return .red
        } else if line.contains(":warn:") || line.contains("WARNING") {
            return .orange
        } else if line.contains(":fixme:") {
            return .yellow
        }
        return .primary
    }

    // MARK: - Actions

    private func loadLogs() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let content = try String(contentsOf: logURL, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines)
                    .filter { !$0.isEmpty }

                // 최대 5000줄만 유지
                let truncatedLines = lines.count > 5000
                    ? Array(lines.suffix(5000))
                    : lines

                DispatchQueue.main.async {
                    self.logLines = truncatedLines
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.logLines = ["Failed to load: \(error.localizedDescription)"]
                    self.isLoading = false
                }
            }
        }
    }

    private func clearLogs() {
        do {
            try "".write(to: logURL, atomically: true, encoding: .utf8)
            logLines = []
        } catch {
            Logger.podoSojuKit.error("Failed to clear logs: \(error)")
        }
    }
}

#Preview {
    LogWindowView()
}
