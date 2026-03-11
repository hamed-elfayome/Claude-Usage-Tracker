//
//  ColorModeSelector.swift
//  Claude Usage
//
//  Reusable color mode selection component for menu bar appearance settings
//

import SwiftUI

/// Reusable color mode selection component
struct ColorModeSelector: View {
    @Binding var colorMode: MenuBarColorMode
    @Binding var singleColorHex: String
    let onConfigChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("appearance.color_mode".localized)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                ForEach(MenuBarColorMode.allCases, id: \.rawValue) { mode in
                    ColorModeButton(
                        mode: mode,
                        isSelected: colorMode == mode,
                        customColor: mode == .singleColor ? Color(hex: singleColorHex) : nil,
                        action: {
                            colorMode = mode
                            onConfigChanged()
                        }
                    )
                }

                // Color picker (separate, always visible)
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { Color(hex: singleColorHex) ?? .blue },
                        set: { newColor in
                            singleColorHex = newColor.hexString
                            if colorMode != .singleColor {
                                colorMode = .singleColor
                            }
                            onConfigChanged()
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 28, height: 28)

                Spacer()
            }
        }
    }
}

// MARK: - Color Mode Button

struct ColorModeButton: View {
    let mode: MenuBarColorMode
    let isSelected: Bool
    var customColor: Color? = nil
    let action: () -> Void

    private var iconColor: Color {
        switch mode {
        case .multiColor:
            return .green
        case .monochrome:
            return .secondary
        case .singleColor:
            return customColor ?? .cyan
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(.system(size: 10))
                    .foregroundColor(iconColor)

                Text(mode.displayName)
                    .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .help(mode.description)
    }
}

// MARK: - Previews

#Preview {
    ColorModeSelector(
        colorMode: .constant(.multiColor),
        singleColorHex: .constant("#00BFFF"),
        onConfigChanged: {}
    )
    .padding()
}
