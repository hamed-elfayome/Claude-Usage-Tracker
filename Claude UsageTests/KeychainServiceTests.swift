//
//  KeychainServiceTests.swift
//  Claude UsageTests
//
//  Created by Claude Code on 2025-12-22.
//

import XCTest
@testable import Claude_Usage

final class KeychainServiceTests: XCTestCase {

    let testKey = "test_api_key"
    let testValue = "sk-ant-test-value-12345"

    override func tearDown() {
        // Clean up test data
        try? KeychainService.shared.delete(key: testKey)
        super.tearDown()
    }

    func testSaveAndLoad() throws {
        try KeychainService.shared.save(key: testKey, value: testValue)

        let loaded = KeychainService.shared.load(key: testKey)
        XCTAssertEqual(loaded, testValue)
    }

    func testLoadNonexistent() {
        let loaded = KeychainService.shared.load(key: "nonexistent_key_\(UUID().uuidString)")
        XCTAssertNil(loaded)
    }

    func testDelete() throws {
        try KeychainService.shared.save(key: testKey, value: testValue)
        try KeychainService.shared.delete(key: testKey)

        let loaded = KeychainService.shared.load(key: testKey)
        XCTAssertNil(loaded)
    }

    func testOverwrite() throws {
        try KeychainService.shared.save(key: testKey, value: "first_value")
        try KeychainService.shared.save(key: testKey, value: "second_value")

        let loaded = KeychainService.shared.load(key: testKey)
        XCTAssertEqual(loaded, "second_value")
    }

    func testDeleteNonexistent() throws {
        // Should not throw when deleting a key that doesn't exist
        XCTAssertNoThrow(try KeychainService.shared.delete(key: "nonexistent_key_\(UUID().uuidString)"))
    }

    func testEmptyValue() throws {
        try KeychainService.shared.save(key: testKey, value: "")

        let loaded = KeychainService.shared.load(key: testKey)
        XCTAssertEqual(loaded, "")
    }

    func testSpecialCharacters() throws {
        let specialValue = "sk-ant-sid01-abc123!@#$%^&*()_+-=[]{}|;':\",./<>?"
        try KeychainService.shared.save(key: testKey, value: specialValue)

        let loaded = KeychainService.shared.load(key: testKey)
        XCTAssertEqual(loaded, specialValue)
    }

    func testUnicodeValue() throws {
        let unicodeValue = "sk-ant-测试-🔐-émoji-日本語"
        try KeychainService.shared.save(key: testKey, value: unicodeValue)

        let loaded = KeychainService.shared.load(key: testKey)
        XCTAssertEqual(loaded, unicodeValue)
    }
}
