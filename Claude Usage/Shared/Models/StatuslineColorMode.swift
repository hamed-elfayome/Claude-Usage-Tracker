//
//  StatuslineColorMode.swift
//  Claude Usage
//
//  Statusline color mode for Claude Code integration
//

import Foundation

/// Statusline color mode for Claude Code integration
enum StatuslineColorMode: String, Codable, CaseIterable {
    /// Multi-colored elements (default terminal colors)
    case colored = "colored"

    /// Monochrome/adaptive (uses terminal's default text color)
    case monochrome = "monochrome"

    /// Single user-selected color for all elements
    case singleColor = "singleColor"

    var displayName: String {
        switch self {
        case .colored:
            return "Multi-Color"
        case .monochrome:
            return "Greyscale"
        case .singleColor:
            return "Single Color"
        }
    }

    var description: String {
        switch self {
        case .colored:
            return "Threshold-based colors"
        case .monochrome:
            return "Adapts to system theme"
        case .singleColor:
            return "Custom color for all"
        }
    }

    var icon: String {
        switch self {
        case .colored:
            return "paintpalette.fill"
        case .monochrome:
            return "circle.lefthalf.filled"
        case .singleColor:
            return "eyedropper.halffull"
        }
    }
}
