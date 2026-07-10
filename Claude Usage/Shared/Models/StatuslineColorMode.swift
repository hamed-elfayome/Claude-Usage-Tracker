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

    /// Individual custom color for each statusline element
    case perElement = "perElement"

    var displayName: String {
        switch self {
        case .colored:
            return "Multi-Color"
        case .monochrome:
            return "Greyscale"
        case .singleColor:
            return "Single Color"
        case .perElement:
            return "Per Element"
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
        case .perElement:
            return "Custom color per item"
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
        case .perElement:
            return "paintpalette"
        }
    }
}
