//
//  NotchCompactViews.swift
//  Claude Usage
//
//  Compact (notch-flanking) presentation of the Claude Code HUD: one glance —
//  status symbol + project on the left, status verb (+ session count) on the
//  right. Deliberately minimal; details live in the expanded view.
//

import SwiftUI

struct NotchCompactLeadingView: View {
    @ObservedObject private var store = NotchSessionStore.shared

    var body: some View {
        if let session = store.primarySession {
            HStack(spacing: 5) {
                Image(systemName: session.status.sfSymbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(session.status.tintColor)
                    .symbolEffect(.pulse, isActive: session.status == .needsAttention)
                    .contentTransition(.symbolEffect(.replace))

                Text(session.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    // Long project names shrink a little before truncating,
                    // so the bar never grows past its cap.
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                    .frame(maxWidth: 150, alignment: .leading)
            }
            .help(session.displayName)
            .contentShape(Rectangle())
            .onTapGesture { NotchHUDController.shared.toggleExpanded() }
        }
    }
}

struct NotchCompactTrailingView: View {
    @ObservedObject private var store = NotchSessionStore.shared

    var body: some View {
        if let session = store.primarySession {
            HStack(spacing: 5) {
                Text(session.status.displayText)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)

                if store.sessions.count > 1 {
                    Text("×\(store.sessions.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(.white.opacity(0.15)))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { NotchHUDController.shared.toggleExpanded() }
        }
    }
}
