import XCTest
@testable import Claude_Usage

/// The sponsor placement reads remote JSON, so parsing has to be strict.
final class SponsorSlotTests: XCTestCase {

    private func parse(_ json: String) -> SponsorSlot? {
        SponsorSlot.parse(Data(json.utf8))
    }

    func testOpenPlacement() {
        let slot = parse(#"{"sponsor": null, "contactUrl": "https://claudetracker.com/sponsor"}"#)
        XCTAssertNil(slot?.sponsor)
        XCTAssertEqual(slot?.contactURL?.absoluteString, "https://claudetracker.com/sponsor")
    }

    func testSponsorIsRead() {
        let slot = parse(#"""
        {"sponsor": {"name": " Acme ", "tagline": "Ship faster", "cta": "Try it",
                     "url": "https://acme.example/?ref=ct", "logo": "https://acme.example/logo.png"}}
        """#)
        XCTAssertEqual(slot?.sponsor?.name, "Acme")
        XCTAssertEqual(slot?.sponsor?.tagline, "Ship faster")
        XCTAssertEqual(slot?.sponsor?.callToAction, "Try it")
        XCTAssertEqual(slot?.sponsor?.url.host, "acme.example")
        XCTAssertEqual(slot?.sponsor?.logoURL?.absoluteString, "https://acme.example/logo.png")
    }

    func testOnlyHTTPSLinksAreAccepted() {
        for link in ["http://acme.example", "javascript:alert(1)", "file:///etc/passwd", "acme.example", ""] {
            let slot = parse(#"{"sponsor": {"name": "Acme", "url": "\#(link)"}}"#)
            XCTAssertNotNil(slot, "still a well-formed answer")
            XCTAssertNil(slot?.sponsor, "\(link) must not be shown")
        }
        let slot = parse(#"{"sponsor": {"name": "Acme", "url": "https://acme.example", "logo": "http://acme.example/l.png"}}"#)
        XCTAssertNotNil(slot?.sponsor)
        XCTAssertNil(slot?.sponsor?.logoURL)
    }

    func testSponsorWithoutANameIsDropped() {
        XCTAssertNil(parse(#"{"sponsor": {"name": "   ", "url": "https://acme.example"}}"#)?.sponsor)
        XCTAssertNil(parse(#"{"sponsor": {"url": "https://acme.example"}}"#)?.sponsor)
    }

    func testTextIsCappedAndStrippedOfControlCharacters() {
        let long = String(repeating: "x", count: 500)
        let slot = parse(#"{"sponsor": {"name": "Ac\u0007me\n", "tagline": "\#(long)", "cta": "\#(long)", "url": "https://acme.example"}}"#)
        XCTAssertEqual(slot?.sponsor?.name, "Acme")
        XCTAssertEqual(slot?.sponsor?.tagline?.count, SponsorSlot.maxTaglineLength)
        XCTAssertEqual(slot?.sponsor?.callToAction?.count, SponsorSlot.maxCallToActionLength)
    }

    func testAnythingThatIsNotTheExpectedObjectIsRejected() {
        XCTAssertNil(parse("<html>Just a moment...</html>"))
        XCTAssertNil(parse("[]"))
        XCTAssertNil(parse(""))
    }

    // MARK: - Service

    private func makeDefaults() -> UserDefaults {
        let name = "SponsorSlotTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func response(_ status: Int) -> URLResponse {
        HTTPURLResponse(url: SponsorService.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    @MainActor
    func testGoodAnswerIsShownAndRememberedAcrossLaunches() async {
        let defaults = makeDefaults()
        let body = Data(#"{"sponsor": {"name": "Acme", "url": "https://acme.example"}}"#.utf8)
        let service = SponsorService(defaults: defaults, fetch: { _ in (body, self.response(200)) })
        XCTAssertNil(service.slot.sponsor)

        await service.refresh()
        XCTAssertEqual(service.slot.sponsor?.name, "Acme")

        let relaunched = SponsorService(defaults: defaults, fetch: { _ in throw URLError(.notConnectedToInternet) })
        XCTAssertEqual(relaunched.slot.sponsor?.name, "Acme")
    }

    @MainActor
    func testFailuresKeepWhatIsShowing() async {
        let defaults = makeDefaults()
        var body = Data(#"{"sponsor": {"name": "Acme", "url": "https://acme.example"}}"#.utf8)
        var status = 200
        let service = SponsorService(defaults: defaults, fetch: { _ in (body, self.response(status)) })
        await service.refresh()

        status = 503
        await service.refresh()
        XCTAssertEqual(service.slot.sponsor?.name, "Acme", "an outage must not blank the placement")

        status = 200
        body = Data("<html>challenge</html>".utf8)
        await service.refresh()
        XCTAssertEqual(service.slot.sponsor?.name, "Acme")

        body = Data(#"{"sponsor": null}"#.utf8)
        await service.refresh()
        XCTAssertNil(service.slot.sponsor, "a well-formed 'no sponsor' clears it")
    }
}
