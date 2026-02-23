//
//  OTelManager.swift
//  Claude Usage - OTel Collection Coordinator
//
//  Thin coordinator: starts/stops HTTP server + database.
//  Provides @Published properties for UI binding.
//

import Foundation
import Combine

final class OTelManager: ObservableObject {
    static let shared = OTelManager()

    @Published private(set) var isCollecting = false
    @Published private(set) var totalEventsReceived: Int = 0

    private var server: OTelHTTPServer?
    let database = OTelDatabase()

    private init() {}

    // MARK: - Lifecycle

    func startCollection() {
        guard !isCollecting else { return }

        do {
            try database.open()

            let port = UInt16(SharedDataStore.shared.loadOTelPort())
            server = OTelHTTPServer(database: database, port: port) { [weak self] in
                DispatchQueue.main.async {
                    self?.totalEventsReceived += 1
                }
            }
            try server?.start()

            // Prune old events on startup
            let retentionDays = SharedDataStore.shared.loadOTelRetentionDays()
            database.pruneOldEvents(olderThanDays: retentionDays)

            DispatchQueue.main.async {
                self.isCollecting = true
                self.refreshEventCount()
            }

            LoggingService.shared.log("OTelManager: Collection started on port \(port)")
        } catch {
            LoggingService.shared.logError("OTelManager: Failed to start collection: \(error)")
            // Clean up partial state
            server?.stop()
            server = nil
            database.close()
        }
    }

    func stopCollection() {
        server?.stop()
        server = nil
        database.close()

        DispatchQueue.main.async {
            self.isCollecting = false
        }

        LoggingService.shared.log("OTelManager: Collection stopped")
    }

    // MARK: - Stats

    func refreshEventCount() {
        let apiCount = database.totalAPIRequestCount()
        let toolCount = database.totalToolResultCount()
        DispatchQueue.main.async {
            self.totalEventsReceived = apiCount + toolCount
        }
    }
}
