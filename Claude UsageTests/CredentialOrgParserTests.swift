import XCTest
@testable import Claude_Usage

final class CredentialOrgParserTests: XCTestCase {
    // AC21
    func testOrgIdRootAndNested() {
        XCTAssertEqual(CredentialOrgParser.orgId(fromCredentialsJSON: TeamFixtures.credentialsOrgA), "org-a")
        let nested = #"{"claudeAiOauth":{"organizationUuid":"org-n"}}"#
        XCTAssertEqual(CredentialOrgParser.orgId(fromCredentialsJSON: nested), "org-n")
        XCTAssertNil(CredentialOrgParser.orgId(fromCredentialsJSON: TeamFixtures.credentialsNoOrg))
    }

    func testGarbageAndEmpty() {
        for bad in ["", "nope", "[]", "{}", #"{"organizationUuid":""}"#] {
            XCTAssertNil(CredentialOrgParser.orgId(fromCredentialsJSON: bad), bad)
            XCTAssertNil(CredentialOrgParser.orgId(fromOAuthAccountJSON: bad), bad)
            XCTAssertNil(CredentialOrgParser.orgName(fromOAuthAccountJSON: bad), bad)
            XCTAssertNil(CredentialOrgParser.seat(fromCredentialsJSON: bad), bad)
        }
        XCTAssertNil(CredentialOrgParser.orgId(fromCredentialsJSON: nil))
    }

    func testOAuthAccountTopAndNested() {
        XCTAssertEqual(CredentialOrgParser.orgId(fromOAuthAccountJSON: TeamFixtures.oauthAccountOrgA), "org-a")
        XCTAssertEqual(CredentialOrgParser.orgName(fromOAuthAccountJSON: TeamFixtures.oauthAccountOrgA), "Team A")
        let nested = #"{"oauthAccount":{"organizationUuid":"org-x","organizationName":"X"}}"#
        XCTAssertEqual(CredentialOrgParser.orgId(fromOAuthAccountJSON: nested), "org-x")
        XCTAssertEqual(CredentialOrgParser.orgName(fromOAuthAccountJSON: nested), "X")
    }

    func testSeatFromCredentials() {
        let json = #"{"claudeAiOauth":{"rateLimitTier":"tier1","subscriptionType":"team"}}"#
        XCTAssertEqual(CredentialOrgParser.seat(fromCredentialsJSON: json),
                       SeatFingerprint(source: .credentials, value: "tier1|team"))
        XCTAssertEqual(CredentialOrgParser.seat(fromCredentialsJSON: TeamFixtures.credentialsOrgA),
                       SeatFingerprint(source: .credentials, value: "team"))
        XCTAssertNil(CredentialOrgParser.seat(fromCredentialsJSON: #"{"claudeAiOauth":{"rateLimitTier":""}}"#))
    }

    func testSeatFromOrgList() {
        XCTAssertEqual(CredentialOrgParser.seat(rateLimitTier: "t", ravenType: "r", billingType: "b"),
                       SeatFingerprint(source: .orgList, value: "t|r|b"))
        XCTAssertEqual(CredentialOrgParser.seat(rateLimitTier: nil, ravenType: "", billingType: "b"),
                       SeatFingerprint(source: .orgList, value: "b"))
        XCTAssertNil(CredentialOrgParser.seat(rateLimitTier: nil, ravenType: nil, billingType: nil))
    }
}
