//
//  DropZoneOverlay.swift
//  Soju
//
//  Created on 2026-01-07.
//

import SwiftUI
import UniformTypeIdentifiers

/// Overlay view for drag and drop functionality
struct DropZoneOverlay: View {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Bool

    var body: some View {
        Rectangle()
            .fill(isTargeted ? Color.blue.opacity(0.2) : Color.clear)
            .overlay {
                if isTargeted {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.white)
                            .shadow(radius: 10)

                        Text("Drop executable here to add to desktop")
                            .font(.title2)
                            .foregroundColor(.white)
                            .shadow(radius: 5)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .dropDestination(for: URL.self) { items, location in
                isTargeted = false
                return handleDrop(items)
            } isTargeted: { targeted in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isTargeted = targeted
                }
            }
            .accessibilityLabel("Drop zone for executable files")
            .accessibilityHint("Drag and drop .exe files here to add them to the desktop")
    }

    // MARK: - Drop Handling

    private func handleDrop(_ items: [URL]) -> Bool {
        // Filter for executable files (.exe)
        let executableURLs = items.filter { url in
            url.pathExtension.lowercased() == "exe"
        }

        guard !executableURLs.isEmpty else {
            return false
        }

        return onDrop(executableURLs)
    }
}

#Preview("Drop Zone - Inactive") {
    ZStack {
        Color.blue.opacity(0.3)
            .ignoresSafeArea()

        DropZoneOverlay(isTargeted: .constant(false)) { urls in
            print("Dropped: \(urls)")
            return true
        }
    }
    .frame(width: 800, height: 600)
}

#Preview("Drop Zone - Active") {
    ZStack {
        Color.blue.opacity(0.3)
            .ignoresSafeArea()

        DropZoneOverlay(isTargeted: .constant(true)) { urls in
            print("Dropped: \(urls)")
            return true
        }
    }
    .frame(width: 800, height: 600)
}
