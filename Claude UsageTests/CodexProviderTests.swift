import XCTest
@testable import Claude_Usage

final class CodexProviderTests: XCTestCase {
    func testBuildProbeRequest() {
        let profile = Profile(name: "Test Codex", providerType: .codex, openaiApiKey: "sk-test123")
        let provider = CodexProvider(profile: profile)
        let request = provider.buildProbeRequest(apiKey: "sk-test123")

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["max_tokens"] as? Int, 1)
        XCTAssertNotNil(body["model"])
        XCTAssertNotNil(body["messages"])
    }
}
