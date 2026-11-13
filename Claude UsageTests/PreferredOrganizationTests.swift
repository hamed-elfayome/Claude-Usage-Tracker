import XCTest
@testable import Claude_Usage

/// Picking the organization after sign-in (#266).
final class PreferredOrganizationTests: XCTestCase {
    private typealias Org = ClaudeAPIService.AccountInfo

    private let api = Org(uuid: "api-org", name: "API", capabilities: ["api"])
    private let chat = Org(uuid: "chat-org", name: "Personal", capabilities: ["chat", "claude_pro"])

    func testCurrentSelectionIsKeptWhileTheAccountBelongsToIt() {
        let other = Org(uuid: "team-org", name: "Team", capabilities: ["chat"])
        XCTAssertEqual(ClaudeAPIService.preferredOrganization(from: [chat, other], current: "team-org")?.uuid, "team-org")
    }

    func testStaleSelectionFromAPreviousSignInIsReplaced() {
        XCTAssertEqual(ClaudeAPIService.preferredOrganization(from: [chat], current: "old-account-org")?.uuid, "chat-org")
    }

    func testChatOrganizationIsPreferredOverAnAPIOnlyOne() {
        XCTAssertEqual(ClaudeAPIService.preferredOrganization(from: [api, chat])?.uuid, "chat-org")
    }

    func testFirstOrganizationIsTheFallback() {
        XCTAssertEqual(ClaudeAPIService.preferredOrganization(from: [api])?.uuid, "api-org")
        XCTAssertNil(ClaudeAPIService.preferredOrganization(from: []))
    }
}
