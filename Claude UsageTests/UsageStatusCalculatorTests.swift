import XCTest
@testable import Claude_Usage

final class UsageStatusCalculatorTests: XCTestCase {

    // MARK: - Used-Based Thresholds (showRemaining = false)

    func testUsedBasedThresholds_Safe() {
        // 0-49% used should be safe (green)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 0, showRemaining: false),
            .safe
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 25, showRemaining: false),
            .safe
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 49, showRemaining: false),
            .safe
        )
    }

    func testUsedBasedThresholds_Moderate() {
        // 50-79% used should be moderate (orange)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 50, showRemaining: false),
            .moderate
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 65, showRemaining: false),
            .moderate
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 79, showRemaining: false),
            .moderate
        )
    }

    func testUsedBasedThresholds_Critical() {
        // 80-100% used should be critical (red)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 80, showRemaining: false),
            .critical
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 95, showRemaining: false),
            .critical
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 100, showRemaining: false),
            .critical
        )
    }

    // MARK: - Remaining-Based Thresholds (showRemaining = true)

    func testRemainingBasedThresholds_Safe() {
        // >20% remaining (0-79% used) should be safe
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 0, showRemaining: true),
            .safe
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 50, showRemaining: true),
            .safe
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 79, showRemaining: true),
            .safe
        )
    }

    func testRemainingBasedThresholds_Moderate() {
        // 10-19% remaining (81-90% used) should be moderate
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 81, showRemaining: true),
            .moderate
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 85, showRemaining: true),
            .moderate
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 90, showRemaining: true),
            .moderate
        )
    }

    func testRemainingBasedThresholds_Critical() {
        // <10% remaining (>90% used) should be critical
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 91, showRemaining: true),
            .critical
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 95, showRemaining: true),
            .critical
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 100, showRemaining: true),
            .critical
        )
    }

    // MARK: - Display Percentage Calculation

    func testGetDisplayPercentage_UsedMode() {
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: 65, showRemaining: false),
            65.0
        )
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: 0, showRemaining: false),
            0.0
        )
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: 100, showRemaining: false),
            100.0
        )
    }

    func testGetDisplayPercentage_RemainingMode() {
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: 65, showRemaining: true),
            35.0
        )
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: 0, showRemaining: true),
            100.0
        )
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: 100, showRemaining: true),
            0.0
        )
    }

    // MARK: - Edge Cases

    func testBoundaryConditions_UsedMode() {
        // Test exact boundary values for used-based thresholds
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 49.9, showRemaining: false),
            .safe
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 50.0, showRemaining: false),
            .moderate
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 79.9, showRemaining: false),
            .moderate
        )
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 80.0, showRemaining: false),
            .critical
        )
    }

    func testBoundaryConditions_RemainingMode() {
        // Test exact boundary values for remaining-based thresholds
        // 21% remaining (79% used) = safe
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 79, showRemaining: true),
            .safe
        )
        // 20% remaining (80% used) = safe (20 is included in 20... range)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 80, showRemaining: true),
            .safe
        )
        // 19% remaining (81% used) = moderate
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 81, showRemaining: true),
            .moderate
        )
        // 10% remaining (90% used) = moderate (10 is included in 10..<20 range)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 90, showRemaining: true),
            .moderate
        )
        // 9% remaining (91% used) = critical
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 91, showRemaining: true),
            .critical
        )
    }

    func testNegativePercentage() {
        // Should handle negative used percentages gracefully (edge case, shouldn't happen in practice)
        // With -10% used, remaining would be 110%, clamped to 110 (max doesn't apply here)
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: -10, showRemaining: true),
            110.0  // max(0, 100 - (-10)) = max(0, 110) = 110
        )
    }

    func testOverOneHundredPercentage() {
        // Should handle over 100% gracefully
        XCTAssertEqual(
            UsageStatusCalculator.getDisplayPercentage(usedPercentage: 110, showRemaining: true),
            0.0  // max(0, 100 - 110) = 0
        )
    }

    // MARK: - Pacing (elapsedFraction provided)

    func testPacing_Safe_LowProjected() {
        // 30% used at 50% elapsed → projected 0.60 → safe
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 30, showRemaining: false, elapsedFraction: 0.5),
            .safe
        )
    }

    func testPacing_Moderate_MediumProjected() {
        // 40% used at 50% elapsed → projected 0.80 → moderate
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 40, showRemaining: false, elapsedFraction: 0.5),
            .moderate
        )
    }

    func testPacing_Critical_HighProjected() {
        // 60% used at 50% elapsed → projected 1.20 → critical
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 60, showRemaining: false, elapsedFraction: 0.5),
            .critical
        )
    }

    func testPacing_HighUsedLateSession_Moderate() {
        // 80% used at 90% elapsed → projected 0.89 → moderate (not red as absolute would give)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 80, showRemaining: false, elapsedFraction: 0.9),
            .moderate
        )
    }

    func testPacing_EarlySession_FallsBackToAbsolute() {
        // 60% used at only 10% elapsed (too early) → fallback → moderate (absolute 50–80%)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 60, showRemaining: false, elapsedFraction: 0.10),
            .moderate
        )
    }

    func testPacing_NilElapsed_FallsBackToAbsolute() {
        // nil elapsed → absolute thresholds
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 60, showRemaining: false, elapsedFraction: nil),
            .moderate
        )
    }

    func testPacing_ZeroUsage_AlwaysSafe() {
        // 0% used at high elapsed → safe (no data to project a rate from)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 0, showRemaining: false, elapsedFraction: 0.9),
            .safe
        )
    }

    func testPacing_BoundaryAtExactly15Percent_Activates() {
        // Exactly 15% elapsed → pacing activates
        // 10% used at 15% elapsed → projected 0.667 → safe
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 10, showRemaining: false, elapsedFraction: 0.15),
            .safe
        )
    }

    func testPacing_JustBelow15Percent_FallsBack() {
        // 14% elapsed → fallback; 60% used → moderate (absolute 50–80%)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 60, showRemaining: false, elapsedFraction: 0.14),
            .moderate
        )
    }

    func testPacing_ProjectedBoundary_75Percent_IsModerate() {
        // 37.5% used at 50% elapsed → projected exactly 0.75 → moderate
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 37.5, showRemaining: false, elapsedFraction: 0.5),
            .moderate
        )
    }

    func testPacing_ProjectedBoundary_95Percent_IsCritical() {
        // 47.5% used at 50% elapsed → projected exactly 0.95 → critical
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 47.5, showRemaining: false, elapsedFraction: 0.5),
            .critical
        )
    }

    func testPacing_ShowRemaining_Safe() {
        // 30% used at 50% elapsed → projected 0.60 → safe (display mode does not affect pacing)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 30, showRemaining: true, elapsedFraction: 0.5),
            .safe
        )
    }

    func testPacing_ShowRemaining_Moderate() {
        // 40% used at 50% elapsed → projected 0.80 → moderate (display mode does not affect pacing)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 40, showRemaining: true, elapsedFraction: 0.5),
            .moderate
        )
    }

    func testPacing_ShowRemaining_HighProjected_Critical() {
        // 55% used at 50% elapsed → projected 1.10 → critical (regardless of display mode)
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 55, showRemaining: true, elapsedFraction: 0.5),
            .critical
        )
    }

    func testPacing_FullSession_FallsBackToAbsolute() {
        // t = 1.0 is excluded from pacing (avoid division artefacts at the boundary)
        // 80% used → critical via absolute
        XCTAssertEqual(
            UsageStatusCalculator.calculateStatus(usedPercentage: 80, showRemaining: false, elapsedFraction: 1.0),
            .critical
        )
    }

    // MARK: - elapsedFraction edge cases

    func testElapsedFraction_ExpiredSession_ReturnsNil() {
        // resetTime in the past → nil (session expired, pending refresh)
        let resetTime = Date().addingTimeInterval(-60)
        let fraction = UsageStatusCalculator.elapsedFraction(
            resetTime: resetTime,
            duration: Constants.sessionWindow,
            showRemaining: false
        )
        XCTAssertNil(fraction)
    }

    func testElapsedFraction_ZeroDuration_ReturnsNil() {
        // duration == 0 → nil (avoid division by zero)
        let resetTime = Date().addingTimeInterval(3600)
        let fraction = UsageStatusCalculator.elapsedFraction(
            resetTime: resetTime,
            duration: 0,
            showRemaining: false
        )
        XCTAssertNil(fraction)
    }

    func testElapsedFraction_NilResetTime_ReturnsNil() {
        let fraction = UsageStatusCalculator.elapsedFraction(
            resetTime: nil,
            duration: Constants.sessionWindow,
            showRemaining: false
        )
        XCTAssertNil(fraction)
    }

    // MARK: - elapsedFraction with shared period constants

    func testElapsedFraction_SessionPeriod_HalfwayThrough() {
        // 2.5 hours into a 5-hour session = 0.5
        let resetTime = Date().addingTimeInterval(Constants.sessionWindow / 2)
        let fraction = UsageStatusCalculator.elapsedFraction(
            resetTime: resetTime,
            duration: Constants.sessionWindow,
            showRemaining: false
        )
        XCTAssertEqual(fraction ?? 0, 0.5, accuracy: 0.01)
    }

    func testElapsedFraction_WeeklyPeriod_HalfwayThrough() {
        // 3.5 days into a 7-day week = 0.5
        let resetTime = Date().addingTimeInterval(Constants.weeklyWindow / 2)
        let fraction = UsageStatusCalculator.elapsedFraction(
            resetTime: resetTime,
            duration: Constants.weeklyWindow,
            showRemaining: false
        )
        XCTAssertEqual(fraction ?? 0, 0.5, accuracy: 0.01)
    }

    func testElapsedFraction_WeeklyPeriod_NearStart() {
        // Just started (reset in ~7 days) → ~0% elapsed
        let resetTime = Date().addingTimeInterval(Constants.weeklyWindow - 60)
        let fraction = UsageStatusCalculator.elapsedFraction(
            resetTime: resetTime,
            duration: Constants.weeklyWindow,
            showRemaining: false
        )
        XCTAssertEqual(fraction ?? 0, 0.0, accuracy: 0.01)
    }

    func testElapsedFraction_WeeklyPeriod_NearEnd() {
        // 60 seconds left → ~1.0 elapsed
        let resetTime = Date().addingTimeInterval(60)
        let fraction = UsageStatusCalculator.elapsedFraction(
            resetTime: resetTime,
            duration: Constants.weeklyWindow,
            showRemaining: false
        )
        XCTAssertEqual(fraction ?? 0, 1.0, accuracy: 0.01)
    }
}
