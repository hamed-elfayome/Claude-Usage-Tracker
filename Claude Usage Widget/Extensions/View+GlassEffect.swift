//
//  View+GlassEffect.swift
//  Claude Usage Widget
//
//  Liquid Glass card background for widget views (macOS 26+)
//

import SwiftUI

extension View {
    /// Applies a subtle card background to a widget card/tile.
    /// Uses a semi-transparent white tint that stays visible in both active and idle widget states.
    /// Note: Materials (.ultraThinMaterial) go opaque in idle state, hiding content.
    func widgetCardBackground() -> some View {
        self.background(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: WidgetDesign.Spacing.cardCornerRadius)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .cornerRadius(WidgetDesign.Spacing.cardCornerRadius)
    }
}
