//
//  ShortcutRecorderView.swift
//  Claude Usage
//
//  Reusable keyboard shortcut recorder component
//

import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var keyCombo: KeyCombo?
    @State private var isRecording = false
    @State private var localMonitor: Any?

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            // Display area
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.extraSmall) {
                    if isRecording {
                        Text("shortcuts.recording".localized)
                            .font(DesignTokens.Typography.body)
                            .foregroundColor(.accentColor)
                    } else if let combo = keyCombo {
                        Text(combo.displayString)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                    } else {
                        Text("shortcuts.record".localized)
                            .font(DesignTokens.Typography.body)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minWidth: 120)
                .padding(.horizontal, DesignTokens.Spacing.medium)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .fill(isRecording ? Color.accentColor.opacity(0.1) : DesignTokens.Colors.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .strokeBorder(
                            isRecording ? Color.accentColor : DesignTokens.Colors.cardBorder,
                            lineWidth: isRecording ? 2 : 1
                        )
                )
            }
            .buttonStyle(.plain)

            // Clear button
            if keyCombo != nil {
                Button {
                    keyCombo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("shortcuts.clear".localized)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels recording
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            // Require at least one modifier key
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !modifiers.isEmpty else {
                return nil // Ignore plain keys
            }

            // Don't capture modifier-only presses (no actual key)
            let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            guard !modifierOnlyKeyCodes.contains(event.keyCode) else {
                return event
            }

            keyCombo = KeyCombo(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ShortcutRecorderView(keyCombo: .constant(nil))
        ShortcutRecorderView(keyCombo: .constant(
            KeyCombo(keyCode: 15, modifierFlags: [.command, .shift])
        ))
    }
    .padding()
    .frame(width: 300)
}
