//
//  SponsorService.swift
//  Claude Usage
//
//  The settings sidebar has one sponsor placement. What it shows comes from
//  an endpoint on the project's own site, so a sponsor can be added, changed
//  or removed without shipping a release. With no network, or no sponsor, the
//  placement falls back to the built-in "available" card.
//

import Foundation
import Combine

/// What the sponsor placement shows.
struct SponsorSlot: Equatable {
    struct Sponsor: Equatable {
        let name: String
        let tagline: String?
        let callToAction: String?
        /// Page opened inside the settings window when the card is clicked.
        let url: URL
        let logoURL: URL?
    }

    /// The current sponsor, or nil while the placement is open.
    let sponsor: Sponsor?
    /// Page describing sponsorship, opened for the open placement. With none,
    /// the card writes an email as it always did.
    let contactURL: URL?

    static let empty = SponsorSlot(sponsor: nil, contactURL: nil)

    static let maxNameLength = 40
    static let maxTaglineLength = 90
    static let maxCallToActionLength = 28

    /// Reads the endpoint's JSON:
    ///
    ///     { "sponsor": { "name": "...", "tagline": "...", "cta": "...",
    ///                    "url": "https://...", "logo": "https://..." } | null,
    ///       "contactUrl": "https://..." | null }
    ///
    /// Everything remote is treated as untrusted: text is trimmed, stripped of
    /// control characters and length-capped, and only https links are kept. A
    /// sponsor without a name or a usable link is dropped, not half-shown.
    /// Returns nil when the body is not the expected JSON object at all.
    static func parse(_ data: Data) -> SponsorSlot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var sponsor: Sponsor?
        if let raw = object["sponsor"] as? [String: Any],
           let name = cleanText(raw["name"], limit: maxNameLength),
           let url = secureURL(raw["url"]) {
            sponsor = Sponsor(
                name: name,
                tagline: cleanText(raw["tagline"], limit: maxTaglineLength),
                callToAction: cleanText(raw["cta"], limit: maxCallToActionLength),
                url: url,
                logoURL: secureURL(raw["logo"])
            )
        }
        return SponsorSlot(sponsor: sponsor, contactURL: secureURL(object["contactUrl"]))
    }

    private static func cleanText(_ value: Any?, limit: Int) -> String? {
        guard let string = value as? String else { return nil }
        let scalars = string.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(limit))
    }

    private static func secureURL(_ value: Any?) -> URL? {
        guard let string = value as? String,
              let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }
}

@MainActor
final class SponsorService: ObservableObject {
    static let shared = SponsorService()

    static let endpoint = URL(string: "https://claudetracker.com/api/sponsor")!
    /// How long a fetched answer is reused before asking again.
    static let refreshInterval: TimeInterval = 6 * 60 * 60

    private static let cachedBodyKey = "sponsorSlotCachedBody"
    private static let cachedAtKey = "sponsorSlotCachedAt"

    @Published private(set) var slot: SponsorSlot = .empty

    private let defaults: UserDefaults
    private let fetch: (URL) async throws -> (Data, URLResponse)
    private let now: () -> Date
    private var isFetching = false

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        fetch: ((URL) async throws -> (Data, URLResponse))? = nil
    ) {
        self.defaults = defaults
        self.now = now
        self.fetch = fetch ?? { url in
            // No cookies, no cache, nothing identifying beyond the request itself.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return try await URLSession(configuration: configuration).data(for: request)
        }
        if let body = defaults.data(forKey: Self.cachedBodyKey), let cached = SponsorSlot.parse(body) {
            slot = cached
        }
    }

    /// Called when the settings window appears. Shows the cached answer at
    /// once and asks the endpoint again only when the cache has aged out.
    func refreshIfNeeded() {
        let cachedAt = defaults.object(forKey: Self.cachedAtKey) as? Date ?? .distantPast
        guard !isFetching, now().timeIntervalSince(cachedAt) >= Self.refreshInterval else { return }
        isFetching = true
        Task {
            await refresh()
            isFetching = false
        }
    }

    /// A failed or malformed answer keeps whatever is showing; only a
    /// well-formed one replaces it, so an outage never blanks a sponsor and a
    /// well-formed "no sponsor" still clears one.
    func refresh() async {
        guard let (data, response) = try? await fetch(Self.endpoint),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let fetched = SponsorSlot.parse(data) else {
            return
        }
        slot = fetched
        defaults.set(data, forKey: Self.cachedBodyKey)
        defaults.set(now(), forKey: Self.cachedAtKey)
    }
}
