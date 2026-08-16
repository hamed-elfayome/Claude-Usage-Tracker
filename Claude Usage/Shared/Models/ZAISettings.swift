import Foundation

/// Per-profile configuration for a z.ai (GLM Coding Plan) profile.
///
/// The API key itself is a credential: it lives in the Keychain on the
/// `Profile` (`zaiAPIKey`), never inside this configuration or the plist.
/// Presentation-only choices (the selected bucket) must not invalidate cached
/// usage, so they are excluded from `targetsSameAccount`.
struct ZAIProfileConfiguration: Codable, Equatable {
    /// Which quota window drives the tray icon, popover headline, and alerts.
    var selectedLimitID: String?

    init(selectedLimitID: String? = nil) {
        self.selectedLimitID = selectedLimitID?.nilIfBlank
    }

    private enum CodingKeys: String, CodingKey {
        case selectedLimitID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedLimitID = try container.decodeIfPresent(
            String.self,
            forKey: .selectedLimitID
        )?.nilIfBlank
    }
}

/// z.ai quota API shapes. Only the pieces the tracker consumes are modeled;
/// unknown fields are ignored so schema growth on the server is harmless.
struct ZAIQuotaResponse: Decodable {
    var code: Int?
    var msg: String?
    var success: Bool?
    var data: ZAIQuotaData?
}

struct ZAIQuotaData: Decodable {
    var level: String?
    var limits: [ZAIQuotaLimit]?
}

struct ZAIQuotaLimit: Decodable {
    var type: String?
    var unit: Int?
    var number: Int?
    var usage: Double?
    var currentValue: Double?
    var remaining: Double?
    var percentage: Double?
    var nextResetTime: Int64?
}
