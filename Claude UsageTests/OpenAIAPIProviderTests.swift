import XCTest
@testable import Claude_Usage

final class OpenAIAPIProviderTests: XCTestCase {
    func testParseCostsResponse() throws {
        let json = """
        {
            "object": "page",
            "data": [
                {
                    "object": "bucket",
                    "start_time": 1743638400,
                    "end_time": 1743724800,
                    "results": [
                        {"object": "organization.costs.result", "amount": {"value": 350, "currency": "usd"}, "line_item": "Tokens"}
                    ]
                },
                {
                    "object": "bucket",
                    "start_time": 1743724800,
                    "end_time": 1743811200,
                    "results": [
                        {"object": "organization.costs.result", "amount": {"value": 480, "currency": "usd"}, "line_item": "Tokens"}
                    ]
                }
            ],
            "has_more": false
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(OpenAIAPIProvider.CostsPageResponse.self, from: json)
        XCTAssertEqual(response.data.count, 2)
        XCTAssertFalse(response.hasMore)
        XCTAssertEqual(response.data[0].results[0].amount.value, 350)
        XCTAssertEqual(response.data[0].results[0].amount.currency, "usd")
    }

    func testParseCompletionsUsageResponse() throws {
        let json = """
        {
            "object": "page",
            "data": [
                {
                    "object": "bucket",
                    "start_time": 1743638400,
                    "end_time": 1743724800,
                    "results": [
                        {
                            "object": "organization.usage.completions.result",
                            "input_tokens": 5000,
                            "output_tokens": 2000,
                            "input_cached_tokens": 1000,
                            "model": "gpt-4o"
                        }
                    ]
                }
            ],
            "has_more": false
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(OpenAIAPIProvider.CompletionsPageResponse.self, from: json)
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data[0].results[0].model, "gpt-4o")
        XCTAssertEqual(response.data[0].results[0].inputTokens, 5000)
    }
}
