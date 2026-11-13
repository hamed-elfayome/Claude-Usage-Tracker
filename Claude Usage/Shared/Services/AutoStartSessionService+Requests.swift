import Foundation

extension AutoStartSessionService {
    func fetchExtraUsageEnabled(for profile: Profile) async throws -> Bool {
        guard let sessionKey = profile.claudeSessionKey,
              let orgId = profile.organizationId else {
            throw AppError(code: .sessionKeyNotFound, message: "Missing credentials", isRecoverable: false)
        }

        let url = try URLBuilder(baseURL: Constants.APIEndpoints.claudeBase)
            .appendingPath("/organizations/\(orgId)/overage_spend_limit")
            .build()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue(
            ClaudeAPIService.sessionCookieHeader(sessionKey: sessionKey, url: url),
            forHTTPHeaderField: "Cookie"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AppError(
                code: .apiInvalidResponse,
                message: "Invalid extra usage permission response",
                isRecoverable: true
            )
        }
        guard response.statusCode == 200 else {
            throw AppError(
                code: .apiGenericError,
                message: "Could not check extra usage permission (HTTP \(response.statusCode))",
                isRecoverable: true
            )
        }

        let extraUsage: ClaudeAPIService.OverageSpendLimitResponse
        do {
            extraUsage = try JSONDecoder().decode(ClaudeAPIService.OverageSpendLimitResponse.self, from: data)
        } catch let error as DecodingError {
            throw AppError(
                code: .apiParsingFailed,
                message: "Could not read extra usage permission: \(error.localizedDescription)",
                isRecoverable: true
            )
        }
        guard let isEnabled = extraUsage.isEnabled else {
            throw AppError(
                code: .apiParsingFailed,
                message: "Extra usage permission is unknown; auto-start skipped",
                isRecoverable: true
            )
        }
        return isEnabled
    }

    func fetchUsageForProfile(_ profile: Profile) async throws -> (usage: ClaudeUsage, hasOpenWindow: Bool) {
        // Fetch usage data using the profile's specific credentials
        let (usage, hasOpenWindow) = try await fetchUsageData(for: profile)

        // Save usage to profile
        saveUsage(usage, profile.id)

        return (usage, hasOpenWindow)
    }

    private func fetchUsageData(for profile: Profile) async throws -> (usage: ClaudeUsage, hasOpenWindow: Bool) {
        // Get credentials from the specific profile
        guard let sessionKey = profile.claudeSessionKey,
              let orgId = profile.organizationId else {
            throw AppError(
                code: .sessionKeyNotFound,
                message: "Missing credentials for profile '\(profile.name)'",
                isRecoverable: false
            )
        }

        // Build URL
        let url = try URLBuilder(baseURL: Constants.APIEndpoints.claudeBase)
            .appendingPath("/organizations/\(orgId)/usage")
            .build()

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(
            ClaudeAPIService.sessionCookieHeader(sessionKey: sessionKey, url: url),
            forHTTPHeaderField: "Cookie"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError(code: .apiInvalidResponse, message: "Invalid response", isRecoverable: true)
        }

        guard httpResponse.statusCode == 200 else {
            throw AppError(
                code: .apiGenericError,
                message: "API returned status \(httpResponse.statusCode)",
                isRecoverable: true
            )
        }

        // Parse usage response
        return try parseUsageResponse(data)  // (usage, hasOpenWindow)
    }

    func sendInitializationMessage(for profile: Profile) async throws -> Data {
        guard let sessionKey = profile.claudeSessionKey,
              let orgId = profile.organizationId else {
            throw AppError(
                code: .sessionKeyNotFound,
                message: "Missing credentials",
                isRecoverable: false
            )
        }

        // Create a new conversation
        let conversationURL = try URLBuilder(baseURL: Constants.APIEndpoints.claudeBase)
            .appendingPathComponents(["/organizations", orgId, "/chat_conversations"])
            .build()

        var conversationRequest = URLRequest(url: conversationURL)
        conversationRequest.setValue(
            ClaudeAPIService.sessionCookieHeader(sessionKey: sessionKey, url: conversationURL),
            forHTTPHeaderField: "Cookie"
        )
        conversationRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        conversationRequest.httpMethod = "POST"

        let conversationBody: [String: Any] = [
            "uuid": UUID().uuidString.lowercased(),
            "name": ""
        ]
        conversationRequest.httpBody = try JSONSerialization.data(withJSONObject: conversationBody)

        let (conversationData, conversationResponse) = try await session.data(for: conversationRequest)

        guard let httpResponse = conversationResponse as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw AppError(code: .apiGenericError, message: "Failed to create conversation", isRecoverable: true)
        }

        // Parse conversation UUID
        guard let json = try? JSONSerialization.jsonObject(with: conversationData) as? [String: Any],
              let conversationUUID = json["uuid"] as? String else {
            throw AppError(code: .apiParsingFailed, message: "Failed to parse conversation", isRecoverable: false)
        }

        do {
            let data = try await sendInitializationCompletion(
                conversationUUID: conversationUUID, organizationId: orgId, sessionKey: sessionKey
            )
            await deleteTemporaryConversation(conversationUUID, for: profile)
            return data
        } catch {
            // Clean up on both HTTP and transport failure, preserving the original error.
            await deleteTemporaryConversation(conversationUUID, for: profile)
            throw error
        }
    }

    private func sendInitializationCompletion(
        conversationUUID: String, organizationId: String, sessionKey: String
    ) async throws -> Data {
        // Send a minimal "Hi" message to initialize the session
        let messageURL = try URLBuilder(baseURL: Constants.APIEndpoints.claudeBase)
            .appendingPathComponents([
                "/organizations", organizationId, "/chat_conversations", conversationUUID, "/completion"
            ])
            .build()

        var messageRequest = URLRequest(url: messageURL)
        messageRequest.setValue(
            ClaudeAPIService.sessionCookieHeader(sessionKey: sessionKey, url: messageURL),
            forHTTPHeaderField: "Cookie"
        )
        messageRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        messageRequest.httpMethod = "POST"

        let messageBody: [String: Any] = [
            "prompt": "Hi",
            "model": "claude-haiku-4-5-20251001",
            "timezone": "UTC"
        ]
        messageRequest.httpBody = try JSONSerialization.data(withJSONObject: messageBody)

        let (messageData, messageResponse) = try await session.data(for: messageRequest)

        guard let messageHTTPResponse = messageResponse as? HTTPURLResponse else {
            throw AppError(code: .apiInvalidResponse, message: "Invalid initialization response", isRecoverable: true)
        }
        guard messageHTTPResponse.statusCode == 200 else {
            throw AppError(
                code: .apiGenericError,
                message: "Failed to send initialization message (HTTP \(messageHTTPResponse.statusCode))",
                isRecoverable: true
            )
        }

        return messageData
    }

    private func deleteTemporaryConversation(_ conversationUUID: String, for profile: Profile) async {
        do {
            guard let sessionKey = profile.claudeSessionKey,
                  let orgId = profile.organizationId else {
                throw AppError(code: .sessionKeyNotFound, message: "Missing cleanup credentials", isRecoverable: false)
            }
            let url = try URLBuilder(baseURL: Constants.APIEndpoints.claudeBase)
                .appendingPathComponents(["/organizations", orgId, "/chat_conversations", conversationUUID])
                .build()
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue(
                ClaudeAPIService.sessionCookieHeader(sessionKey: sessionKey, url: url),
                forHTTPHeaderField: "Cookie"
            )
            request.timeoutInterval = 30

            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw AppError(code: .apiInvalidResponse, message: "Invalid cleanup response", isRecoverable: true)
            }
            guard (200..<300).contains(response.statusCode) else {
                throw AppError(
                    code: .apiGenericError,
                    message: "Cleanup returned HTTP \(response.statusCode)",
                    isRecoverable: true
                )
            }
        } catch {
            // Cleanup must report all failures without replacing the initialization result.
            logError(
                "Failed to delete temporary auto-start conversation for profile '\(profile.name)': "
                    + error.localizedDescription
            )
        }
    }
}
