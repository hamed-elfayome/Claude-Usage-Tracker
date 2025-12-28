//
//  APIServiceProtocol.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-20.
//

import Foundation

/// Protocol defining API operations for Claude services
/// Enables dependency injection and testing with mock API services
protocol APIServiceProtocol {
    // MARK: - Session Key Management
    func saveSessionKey(_ key: String) throws

    // MARK: - Claude.ai API
    func fetchOrganizationId(sessionKey: String?) async throws -> String
    func fetchUsageData() async throws -> ClaudeUsage
    func sendInitializationMessage() async throws

    // MARK: - Console API
    func fetchConsoleOrganizations(apiSessionKey: String) async throws -> [APIOrganization]
    func fetchAPIUsageData(organizationId: String, apiSessionKey: String) async throws -> APIUsage
}
