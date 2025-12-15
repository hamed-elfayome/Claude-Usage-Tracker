import XCTest
@testable import Claude_Usage

final class ClaudeUsageTests: XCTestCase {
    
    // MARK: - Status Level Tests
    
    func testStatusLevelSafe() {
        let usage = createUsage(sessionPercentage: 0)
        XCTAssertEqual(usage.statusLevel, .safe)
        
        let usage25 = createUsage(sessionPercentage: 25)
        XCTAssertEqual(usage25.statusLevel, .safe)
        
        let usage49 = createUsage(sessionPercentage: 49.9)
        XCTAssertEqual(usage49.statusLevel, .safe)
    }
    
    func testStatusLevelModerate() {
        let usage50 = createUsage(sessionPercentage: 50)
        XCTAssertEqual(usage50.statusLevel, .moderate)
        
        let usage65 = createUsage(sessionPercentage: 65)
        XCTAssertEqual(usage65.statusLevel, .moderate)
        
        let usage79 = createUsage(sessionPercentage: 79.9)
        XCTAssertEqual(usage79.statusLevel, .moderate)
    }
    
    func testStatusLevelCritical() {
        let usage80 = createUsage(sessionPercentage: 80)
        XCTAssertEqual(usage80.statusLevel, .critical)
        
        let usage95 = createUsage(sessionPercentage: 95)
        XCTAssertEqual(usage95.statusLevel, .critical)
        
        let usage100 = createUsage(sessionPercentage: 100)
        XCTAssertEqual(usage100.statusLevel, .critical)
    }
    
    // MARK: - Empty Usage Tests
    
    func testEmptyUsage() {
        let empty = ClaudeUsage.empty
        
        XCTAssertEqual(empty.sessionTokensUsed, 0)
        XCTAssertEqual(empty.sessionPercentage, 0)
        XCTAssertEqual(empty.weeklyTokensUsed, 0)
        XCTAssertEqual(empty.weeklyPercentage, 0)
        XCTAssertEqual(empty.statusLevel, .safe)
        XCTAssertNil(empty.costUsed)
        XCTAssertNil(empty.costLimit)
    }
    
    // MARK: - Codable Tests
    
    func testEncodeDecode() throws {
        let original = createUsage(sessionPercentage: 45.5)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClaudeUsage.self, from: data)
        
        XCTAssertEqual(original, decoded)
    }
    
    // MARK: - Helpers
    
    private func createUsage(sessionPercentage: Double) -> ClaudeUsage {
        ClaudeUsage(
            sessionTokensUsed: Int(sessionPercentage * 1000),
            sessionLimit: 100000,
            sessionPercentage: sessionPercentage,
            sessionResetTime: Date().addingTimeInterval(3600),
            weeklyTokensUsed: 500000,
            weeklyLimit: 1000000,
            weeklyPercentage: 50,
            weeklyResetTime: Date().addingTimeInterval(86400),
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: 0,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: Date(),
            userTimezone: .current
        )
    }
}
