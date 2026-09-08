//
//  NotifyHTTPClient.swift
//  Claude Usage
//
//  The one seam that lets the gateway client be tested without a network.
//

import Foundation

/// Somewhere to send a request and get an answer back.
///
/// `URLSession` already does this; the protocol exists so a test can hand
/// `NotifyGatewayClient` a stub and drive every status code the gateway can
/// answer with, without a network and without a real device.
protocol NotifyHTTPClient: Sendable {
    func request(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: NotifyHTTPClient {
    func request(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}
