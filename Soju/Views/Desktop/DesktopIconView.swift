//
//  DesktopIconView.swift
//  Soju
//
//  Created on 2026-01-07.
//

import SwiftUI

/// Individual desktop icon view with Windows-like styling
struct DesktopIconView: View {
    let icon: DesktopIcon
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            // Icon image
            Image(systemName: icon.iconImage)
                .font(.system(size: 48))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                .frame(width: 64, height: 64)

            // Icon label
            Text(icon.name)
                .font(.system(size: 11))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 80)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isSelected ? Color.blue.opacity(0.5) : Color.clear)
                )
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
        }
        .frame(width: 90, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isSelected ? Color.blue.opacity(0.7) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .position(icon.position)
    }
}

#Preview("Desktop Icon - Unselected") {
    ZStack {
        Color.blue.opacity(0.3)
            .ignoresSafeArea()

        DesktopIconView(
            icon: DesktopIcon.sampleIcons[0],
            isSelected: false,
            onTap: {},
            onDoubleTap: {}
        )
    }
    .frame(width: 400, height: 300)
}

#Preview("Desktop Icon - Selected") {
    ZStack {
        Color.blue.opacity(0.3)
            .ignoresSafeArea()

        DesktopIconView(
            icon: DesktopIcon.sampleIcons[1],
            isSelected: true,
            onTap: {},
            onDoubleTap: {}
        )
    }
    .frame(width: 400, height: 300)
}
