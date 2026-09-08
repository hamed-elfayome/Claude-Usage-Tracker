import XCTest
@testable import Claude_Usage

/// The id namespaces, what each one can carry, and every shape of credential
/// the user might paste in.
///
/// `@MainActor` because the app target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so everything under test is
/// main-actor isolated while the test target's own default is not. Same
/// reason `NotchHUDCoreTests` and `NotchHookServerTests` carry it.
@MainActor
final class NotifyDeviceLinkTests: XCTestCase {

    // MARK: - ID validation

    func testAcceptsIdsBetweenEightAndThirtyTwoCharacters() {
        XCTAssertTrue(NotifyDeviceLink.isValidDeviceId("ABC12345"))
        XCTAssertTrue(NotifyDeviceLink.isValidDeviceId("IO12345678901234"))
        XCTAssertTrue(NotifyDeviceLink.isValidDeviceId(String(repeating: "A", count: 32)))
    }

    func testRefusesIdsOutsideTheLengthRange() {
        XCTAssertFalse(NotifyDeviceLink.isValidDeviceId("ABC1234"))
        XCTAssertFalse(NotifyDeviceLink.isValidDeviceId(String(repeating: "A", count: 33)))
        XCTAssertFalse(NotifyDeviceLink.isValidDeviceId(""))
    }

    func testRefusesNonAlphanumericIds() {
        XCTAssertFalse(NotifyDeviceLink.isValidDeviceId("ABC-1234"))
        XCTAssertFalse(NotifyDeviceLink.isValidDeviceId("ABC 1234"))
    }

    func testRefusesAnEmptyToken() {
        XCTAssertNil(NotifyDeviceLink(deviceId: "ABC12345", token: ""))
        XCTAssertNil(NotifyDeviceLink(deviceId: "ABC12345", token: "   "))
    }

    func testTrimsBothHalves() {
        let link = NotifyDeviceLink(deviceId: "  ABC12345 ", token: " secret ")
        XCTAssertEqual(link?.deviceId, "ABC12345")
        XCTAssertEqual(link?.token, "secret")
    }

    // MARK: - Pasted text

    /// The three shapes a user actually has on the clipboard all have to yield
    /// the same link, because none of them is wrong.
    func testAllPastedShapesYieldTheSameLink() {
        let expected = NotifyDeviceLink(deviceId: "ABC12345", token: "s3cret")

        XCTAssertEqual(NotifyDeviceLink(pastedText: "ABC12345 s3cret"), expected)
        XCTAssertEqual(NotifyDeviceLink(pastedText: "ABC12345,s3cret"), expected)
        XCTAssertEqual(
            NotifyDeviceLink(pastedText: "https://push.getnotifyapp.com/notify/ABC12345?token=s3cret"),
            expected
        )
        XCTAssertEqual(
            NotifyDeviceLink(pastedText: "https://push.getnotifyapp.com/live-activity/ABC12345?token=s3cret"),
            expected
        )
        XCTAssertEqual(
            NotifyDeviceLink(pastedText: "https://push.getnotifyapp.com/widgets/ABC12345?token=s3cret"),
            expected
        )
    }

    func testRefusesPastedTextWithNoToken() {
        XCTAssertNil(NotifyDeviceLink(pastedText: "ABC12345"))
        XCTAssertNil(NotifyDeviceLink(pastedText: "https://push.getnotifyapp.com/notify/ABC12345"))
    }

    /// The gateway's own `/link` response hands back a notification URL with the
    /// token deliberately stripped. Half an answer is still worth having in a
    /// pane with a field per value.
    func testReadsTheIdOutOfATokenlessURL() {
        XCTAssertEqual(
            NotifyDeviceLink.deviceId(inPastedText: "https://push.getnotifyapp.com/notify/ABC12345"),
            "ABC12345"
        )
        XCTAssertEqual(NotifyDeviceLink.deviceId(inPastedText: "ABC12345"), "ABC12345")
        XCTAssertNil(NotifyDeviceLink.deviceId(inPastedText: "short"))
    }

    // MARK: - Namespaces

    func testClassifiesEachNamespace() {
        XCTAssertEqual(NotifyDeviceKind.kind(ofDeviceId: "GRP12345"), .group)
        XCTAssertEqual(NotifyDeviceKind.kind(ofDeviceId: "WB12345678901234"), .web)
        XCTAssertEqual(NotifyDeviceKind.kind(ofDeviceId: "MC12345678901234"), .mac)
        XCTAssertEqual(NotifyDeviceKind.kind(ofDeviceId: "IO12345678901234"), .appDevice)
        XCTAssertEqual(NotifyDeviceKind.kind(ofDeviceId: "abc12345"), .appDevice)
    }

    /// `GRP` plus five is eight characters, exactly the length of a legacy id,
    /// so the two grammars genuinely overlap. The prefix wins, which is the
    /// gateway's own tie break.
    func testGroupPrefixWinsTheEightCharacterOverlap() {
        XCTAssertEqual(NotifyDeviceKind.kind(ofDeviceId: "GRPABCDE"), .group)
    }

    /// A prefix that is only a prefix by accident must not steal a real device.
    func testAPrefixAloneIsNotEnough() {
        XCTAssertEqual(NotifyDeviceKind.kind(ofDeviceId: "MCABCDEF"), .appDevice)
        XCTAssertEqual(NotifyDeviceKind.kind(ofDeviceId: "WBABCDEF"), .appDevice)
    }

    /// The rule names what cannot publish rather than what may, so a format
    /// Notify! mints after this was written still links.
    func testAnUnknownNamespaceCarriesEverySurface() {
        let kind = NotifyDeviceKind.kind(ofDeviceId: "ZZ999999999999999999")
        XCTAssertEqual(kind, .unrecognized)
        XCTAssertTrue(kind.supportsLiveActivity)
        XCTAssertTrue(kind.supportsWidget)
        XCTAssertTrue(kind.supportsScreenWidget)
    }

    // MARK: - Surface gating

    func testAMacAndABrowserKeepBothWidgetsAndNoLiveActivity() {
        for kind in [NotifyDeviceKind.mac, .web] {
            XCTAssertFalse(kind.supportsLiveActivity, "\(kind)")
            XCTAssertTrue(kind.supportsWidget, "\(kind)")
            XCTAssertTrue(kind.supportsScreenWidget, "\(kind)")
        }
    }

    func testAGroupKeepsNothing() {
        XCTAssertFalse(NotifyDeviceKind.group.supportsLiveActivity)
        XCTAssertFalse(NotifyDeviceKind.group.supportsWidget)
        XCTAssertFalse(NotifyDeviceKind.group.supportsScreenWidget)
        XCTAssertFalse(NotifyDeviceKind.group.supportsAnySurface)
    }

    func testAnAppDeviceKeepsEverything() {
        XCTAssertTrue(NotifyDeviceKind.appDevice.supportsLiveActivity)
        XCTAssertTrue(NotifyDeviceKind.appDevice.supportsWidget)
        XCTAssertTrue(NotifyDeviceKind.appDevice.supportsScreenWidget)
    }

    /// The two widgets must always answer alike, because the Home Screen rule
    /// IS the Lock Screen rule rather than a second copy of it.
    func testTheTwoWidgetsAlwaysAgree() {
        for kind in NotifyDeviceKind.allCases {
            XCTAssertEqual(kind.supportsWidget, kind.supportsScreenWidget, "\(kind)")
            XCTAssertEqual(
                kind.widgetUnsupportedReason,
                kind.screenWidgetUnsupportedReason,
                "\(kind)"
            )
        }
    }

    /// A reason is present exactly when its own surface is unavailable, so no
    /// working control is explained away and no dead one is left unaccounted for.
    func testEachReasonIsPresentExactlyWhenItsSurfaceIsUnavailable() {
        for kind in NotifyDeviceKind.allCases {
            XCTAssertEqual(kind.liveActivityUnsupportedReason == nil, kind.supportsLiveActivity, "\(kind)")
            XCTAssertEqual(kind.widgetUnsupportedReason == nil, kind.supportsWidget, "\(kind)")
        }
    }

    func testTheLinkForwardsTheKindsAnswers() {
        let mac = NotifyDeviceLink(deviceId: "MC12345678901234", token: "s")
        XCTAssertEqual(mac?.supportsLiveActivity, false)
        XCTAssertEqual(mac?.supportsWidget, true)
        XCTAssertEqual(mac?.supportsScreenWidget, true)
    }

    // MARK: - Device info

    func testDeviceInfoDescriptionNamesThePlatformWhenItHasOne() {
        XCTAssertEqual(
            NotifyDeviceInfo(deviceId: "ABC12345", name: "Apollo", platform: "iOS").displayDescription,
            "Apollo (iOS)"
        )
        XCTAssertEqual(
            NotifyDeviceInfo(deviceId: "ABC12345", name: "Apollo", platform: nil).displayDescription,
            "Apollo"
        )
        XCTAssertEqual(
            NotifyDeviceInfo(deviceId: "ABC12345", name: "Apollo", platform: "").displayDescription,
            "Apollo"
        )
    }
}
