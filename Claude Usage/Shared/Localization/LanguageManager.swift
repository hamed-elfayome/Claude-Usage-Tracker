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
            let langCode = Locale.current.language.languageCode?.identifier ?? "en"
            let regionCode = Locale.current.language.region?.identifier ?? ""
            // Build full locale identifier for region-specific matching (e.g. pt-BR)
            let fullCode = regionCode.isEmpty ? langCode : "\(langCode)-\(regionCode)"
            currentLanguage = SupportedLanguage.allCases.first { $0.code == fullCode }
                ?? SupportedLanguage.allCases.first { $0.code == langCode }
                ?? .english
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
        case brazilianPortuguese = "pt-BR"
        case japanese = "ja"
        case korean = "ko"
        case zhCn = "zh-cn"
        case zhHant = "zh-Hant"
        case ukrainian = "uk"
        case turkish = "tr"

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
            case .brazilianPortuguese: return "Português (Brasil)"
            case .japanese: return "日本語"
            case .korean: return "한국어"
            case .zhCn: return "简体中文"
            case .zhHant: return "繁體中文"
            case .ukrainian: return "Українська"
            case .turkish: return "Türkçe"
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
            case .brazilianPortuguese: return "Brazilian Portuguese"
            case .japanese: return "Japanese"
            case .korean: return "Korean"
            case .zhCn: return "Simplified Chinese"
            case .zhHant: return "Traditional Chinese"
            case .ukrainian: return "Ukrainian"
            case .turkish: return "Turkish"
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
            case .brazilianPortuguese: return "🇧🇷"
            case .japanese: return "🇯🇵"
            case .korean: return "🇰🇷"
            case .zhCn: return "🇨🇳"
            case .zhHant: return "🇹🇼"
            case .ukrainian: return "🇺🇦"
            case .turkish: return "🇹🇷"
            }
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let languageChanged = Notification.Name("LanguageChanged")
}
