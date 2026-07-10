//
//  StatuslineElementColors.swift
//  Claude Usage
//
//  Created by Andrea Mario Lufino on 05/04/26.
//  Copyright © 2026 Andrea Mario Lufino. All rights reserved.
//

import Foundation

/// Per-element color configuration for the Claude Code statusline.
///
/// Used when `StatuslineColorMode` is `.perElement`. Each field stores a hex color
/// string for the corresponding statusline element. The defaults match the ANSI
/// palette used by `.colored` mode, so switching to `.perElement` without any
/// customization produces identical output.
///
/// `usageBaseHex` and `paceBaseHex` are optional: `nil` preserves the dynamic
/// behaviour (10-level gradient and 6-tier pace colors respectively); a non-nil
/// value overrides all levels with a single fixed color.
struct StatuslineElementColors: Codable, Equatable {
    /// Hex color for the directory element. Default: ANSI blue.
    var directoryHex: String = "#0000EE"

    /// Hex color for the git branch element. Default: ANSI green.
    var branchHex: String = "#00BB00"

    /// Hex color for the model element. Default: ANSI yellow.
    var modelHex: String = "#BBBB00"

    /// Hex color for the profile element. Default: ANSI magenta.
    var profileHex: String = "#BB00BB"

    /// Hex color for the context element. Default: ANSI cyan.
    var contextHex: String = "#00BBBB"

    /// Hex color for separators between elements. Default: ANSI gray.
    var separatorHex: String = "#808080"

    /// Optional override for the usage gradient. `nil` = use the 10-level gradient.
    var usageBaseHex: String? = nil

    /// Optional override for pace marker colors. `nil` = use the 6-tier standard colors.
    var paceBaseHex: String? = nil

    /// Optional override for the weekly usage gradient. `nil` = use the 10-level gradient
    /// (or `usageBaseHex` if set, matching the session gradient).
    var weeklyBaseHex: String? = nil

    /// Optional override for the extra usage (cost) gradient. `nil` = use the 10-level
    /// gradient (or `usageBaseHex` if set, matching the session gradient).
    var extraUsageBaseHex: String? = nil
}
