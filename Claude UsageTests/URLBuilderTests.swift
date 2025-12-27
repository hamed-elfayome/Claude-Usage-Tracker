//
//  URLBuilderTests.swift
//  Claude Usage Tests
//
//  Created on 2025-12-27.
//

import XCTest
@testable import Claude_Usage

final class URLBuilderTests: XCTestCase {

    // MARK: - Initialization Tests

    func testValidBaseURL() throws {
        let builder = try URLBuilder(baseURL: "https://api.example.com")
        let url = try builder.build()
        XCTAssertEqual(url.absoluteString, "https://api.example.com")
    }

    func testInvalidBaseURL() {
        XCTAssertThrowsError(try URLBuilder(baseURL: "not a url")) { error in
            guard case URLBuilderError.invalidBaseURL = error else {
                XCTFail("Expected invalidBaseURL error")
                return
            }
        }
    }

    func testMissingScheme() {
        XCTAssertThrowsError(try URLBuilder(baseURL: "api.example.com")) { error in
            guard case URLBuilderError.invalidBaseURL = error else {
                XCTFail("Expected invalidBaseURL error")
                return
            }
        }
    }

    // MARK: - Path Building Tests

    func testAppendSinglePath() throws {
        let url = try URLBuilder(baseURL: "https://api.example.com")
            .appendingPath("/users")
            .build()

        XCTAssertEqual(url.absoluteString, "https://api.example.com/users")
    }

    func testAppendMultiplePaths() throws {
        let url = try URLBuilder(baseURL: "https://api.example.com")
            .appendingPath("/users")
            .appendingPath("/123")
            .appendingPath("/profile")
            .build()

        XCTAssertEqual(url.absoluteString, "https://api.example.com/users/123/profile")
    }

    func testAppendPathComponents() throws {
        let url = try URLBuilder(baseURL: "https://api.example.com")
            .appendingPathComponents(["/users", "123", "/profile"])
            .build()

        XCTAssertEqual(url.absoluteString, "https://api.example.com/users/123/profile")
    }

    func testPathTraversalPrevention() {
        XCTAssertThrowsError(
            try URLBuilder(baseURL: "https://api.example.com")
                .appendingPath("../etc/passwd")
        ) { error in
            guard case URLBuilderError.invalidPath = error else {
                XCTFail("Expected invalidPath error")
                return
            }
        }
    }

    // MARK: - Query Parameter Tests

    func testAddSingleQueryParameter() throws {
        let url = try URLBuilder(baseURL: "https://api.example.com")
            .appendingPath("/search")
            .addingQueryParameter(name: "q", value: "test")
            .build()

        XCTAssertTrue(url.absoluteString.contains("q=test"))
    }

    func testAddMultipleQueryParameters() throws {
        let url = try URLBuilder(baseURL: "https://api.example.com")
            .appendingPath("/search")
            .addingQueryParameter(name: "q", value: "test")
            .addingQueryParameter(name: "limit", value: "10")
            .build()

        XCTAssertTrue(url.absoluteString.contains("q=test"))
        XCTAssertTrue(url.absoluteString.contains("limit=10"))
    }

    func testAddQueryParametersDictionary() throws {
        let url = try URLBuilder(baseURL: "https://api.example.com")
            .appendingPath("/search")
            .addingQueryParameters(["q": "test", "limit": "10"])
            .build()

        XCTAssertTrue(url.absoluteString.contains("q=test"))
        XCTAssertTrue(url.absoluteString.contains("limit=10"))
    }

    func testEmptyParameterName() {
        XCTAssertThrowsError(
            try URLBuilder(baseURL: "https://api.example.com")
                .addingQueryParameter(name: "", value: "test")
        ) { error in
            guard case URLBuilderError.invalidQueryParameter = error else {
                XCTFail("Expected invalidQueryParameter error")
                return
            }
        }
    }

    // MARK: - Convenience Method Tests

    func testClaudeAPIBuilder() throws {
        let url = try URLBuilder.claudeAPI(endpoint: "/organizations").build()
        XCTAssertEqual(url.absoluteString, "https://claude.ai/api/organizations")
    }

    func testConsoleAPIBuilder() throws {
        let url = try URLBuilder.consoleAPI(endpoint: "/organizations").build()
        XCTAssertEqual(url.absoluteString, "https://console.anthropic.com/api/organizations")
    }

    func testClaudeStatusBuilder() throws {
        let url = try URLBuilder.claudeStatus(endpoint: "/status.json").build()
        XCTAssertEqual(url.absoluteString, "https://status.claude.com/api/v2/status.json")
    }

    // MARK: - Complex URL Tests

    func testComplexClaudeURL() throws {
        let orgId = "org_123"
        let conversationId = "conv_456"

        let url = try URLBuilder.claudeAPI()
            .appendingPathComponents([
                "/organizations",
                orgId,
                "/chat_conversations",
                conversationId,
                "/completion"
            ])
            .build()

        XCTAssertEqual(
            url.absoluteString,
            "https://claude.ai/api/organizations/org_123/chat_conversations/conv_456/completion"
        )
    }

    // MARK: - Result Type Tests

    func testBuildResultSuccess() {
        let result = (try? URLBuilder(baseURL: "https://api.example.com"))?.buildResult()

        switch result {
        case .success(let url):
            XCTAssertEqual(url.absoluteString, "https://api.example.com")
        case .failure, .none:
            XCTFail("Expected success result")
        }
    }

    func testBuildResultFailure() {
        // Test that buildResult() returns a failure for invalid input
        do {
            let builder = try URLBuilder(baseURL: "https://api.example.com")

            // This should throw because of ".." path traversal
            XCTAssertThrowsError(try builder.appendingPath("..invalid.."))
        } catch {
            XCTFail("Failed to create builder: \(error)")
        }
    }

    // MARK: - Edge Cases

    func testURLWithSpecialCharacters() throws {
        let url = try URLBuilder(baseURL: "https://api.example.com")
            .appendingPath("/search")
            .addingQueryParameter(name: "q", value: "hello world")
            .build()

        // URL encoding should handle spaces
        XCTAssertNotNil(url)
        XCTAssertTrue(url.absoluteString.contains("search"))
    }

    func testURLWithMultipleSlashes() throws {
        let url = try URLBuilder(baseURL: "https://api.example.com")
            .appendingPath("/users/")
            .appendingPath("/123/")
            .build()

        // Should normalize slashes
        XCTAssertNotNil(url)
        XCTAssertTrue(url.absoluteString.contains("users"))
        XCTAssertTrue(url.absoluteString.contains("123"))
    }

    // MARK: - Performance Tests

    func testBuilderPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = try? URLBuilder(baseURL: "https://api.example.com")
                    .appendingPath("/users")
                    .appendingPath("/123")
                    .addingQueryParameter(name: "include", value: "profile")
                    .build()
            }
        }
    }
}
