//
//  LanguageManager.swift
//  Claude Usage - Language Management System
//
//  Created by Claude Code on 2025-12-27.
//

import Foundation
import SwiftUI
import Combine

/// Manages app language selection and switching
class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var currentLanguage: SupportedLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.code, forKey: Constants.UserDefaultsKeys.appLanguage)
            applyLanguage()
        }
    }

    private init() {
        // Load saved language or use system default
        if let savedCode = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.appLanguage),
           let language = SupportedLanguage(rawValue: savedCode) {
            currentLanguage = language
        } else {
            // Detect system language and match to supported languages
            let systemLanguage = Locale.current.language.languageCode?.identifier ?? "en"
            currentLanguage = SupportedLanguage.allCases.first { $0.code == systemLanguage } ?? .english
        }

        applyLanguage()
    }

    /// Apply the selected language to the app
    private func applyLanguage() {
        UserDefaults.standard.set([currentLanguage.code], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()

        // Post notification for views that need to refresh
        NotificationCenter.default.post(name: .languageChanged, object: nil)
    }

    /// Supported languages (LTR only for simplicity)
    enum SupportedLanguage: String, CaseIterable, Identifiable {
        case english = "en"
        case spanish = "es"
        case french = "fr"
        case german = "de"
        case italian = "it"
        case portuguese = "pt"
        case japanese = "ja"
        case korean = "ko"
        case chinese = "zh-Hans"

        var id: String { rawValue }

        /// Language code for localization
        var code: String { rawValue }

        /// Display name in the language itself (native name)
        var displayName: String {
            switch self {
            case .english: return "English"
            case .spanish: return "Español"
            case .french: return "Français"
            case .german: return "Deutsch"
            case .italian: return "Italiano"
            case .portuguese: return "Português"
            case .japanese: return "日本語"
            case .korean: return "한국어"
            case .chinese: return "简体中文"
            }
        }

        /// English name of the language (for reference)
        var englishName: String {
            switch self {
            case .english: return "English"
            case .spanish: return "Spanish"
            case .french: return "French"
            case .german: return "German"
            case .italian: return "Italian"
            case .portuguese: return "Portuguese"
            case .japanese: return "Japanese"
            case .korean: return "Korean"
            case .chinese: return "Chinese (Simplified)"
            }
        }

        /// Flag emoji for visual representation
        var flag: String {
            switch self {
            case .english: return "🇬🇧"
            case .spanish: return "🇪🇸"
            case .french: return "🇫🇷"
            case .german: return "🇩🇪"
            case .italian: return "🇮🇹"
            case .portuguese: return "🇵🇹"
            case .japanese: return "🇯🇵"
            case .korean: return "🇰🇷"
            case .chinese: return "🇨🇳"
            }
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let languageChanged = Notification.Name("LanguageChanged")
}
