//
//  OTelDatabase.swift
//  Claude Usage - SQLite Storage for OTel Events
//
//  Uses SQLite3 C API (system framework, no external deps).
//  Thread-safe via serial DispatchQueue.
//

import Foundation
import SQLite3

final class OTelDatabase {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.claudeusage.oteldb", qos: .utility)
    private let dbPath: String

    init() {
        let dir = Constants.OTel.databaseDirectory
        let path = dir.appendingPathComponent(Constants.OTel.databaseFilename).path
        self.dbPath = path
    }

    // MARK: - Lifecycle

    func open() throws {
        try queue.sync {
            // Ensure directory exists with restricted permissions (owner-only)
            let dir = Constants.OTel.databaseDirectory.path
            if !FileManager.default.fileExists(atPath: dir) {
                try FileManager.default.createDirectory(
                    atPath: dir,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }

            if sqlite3_open(dbPath, &db) != SQLITE_OK {
                let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
                throw OTelDatabaseError.openFailed(msg)
            }

            // Restrict database file permissions to owner-only read/write
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: dbPath
            )

            // Enable WAL mode for better concurrency
            exec("PRAGMA journal_mode=WAL")
            exec("PRAGMA synchronous=NORMAL")

            try createTables()
        }
    }

    func close() {
        queue.sync {
            if let db = db {
                sqlite3_close(db)
            }
            db = nil
        }
    }

    // MARK: - Schema

    private func createTables() throws {
        let apiRequestsSQL = """
            CREATE TABLE IF NOT EXISTS api_requests (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                session_id TEXT,
                model TEXT NOT NULL,
                cost_usd REAL NOT NULL DEFAULT 0,
                duration_ms INTEGER NOT NULL DEFAULT 0,
                input_tokens INTEGER NOT NULL DEFAULT 0,
                output_tokens INTEGER NOT NULL DEFAULT 0,
                cache_read_tokens INTEGER NOT NULL DEFAULT 0,
                cache_creation_tokens INTEGER NOT NULL DEFAULT 0,
                speed TEXT,
                user_email TEXT,
                organization_id TEXT
            )
            """

        let toolResultsSQL = """
            CREATE TABLE IF NOT EXISTS tool_results (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                session_id TEXT,
                tool_name TEXT NOT NULL,
                success INTEGER NOT NULL DEFAULT 1,
                duration_ms INTEGER NOT NULL DEFAULT 0
            )
            """

        guard exec(apiRequestsSQL), exec(toolResultsSQL) else {
            throw OTelDatabaseError.schemaFailed
        }

        // Create indexes (IF NOT EXISTS is implicit with CREATE INDEX IF NOT EXISTS)
        exec("CREATE INDEX IF NOT EXISTS idx_api_requests_timestamp ON api_requests(timestamp DESC)")
        exec("CREATE INDEX IF NOT EXISTS idx_api_requests_model ON api_requests(model)")
        exec("CREATE INDEX IF NOT EXISTS idx_tool_results_timestamp ON tool_results(timestamp DESC)")
    }

    // MARK: - Insert

    func insertAPIRequests(_ requests: [ParsedAPIRequest]) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }

            let sql = """
                INSERT INTO api_requests (timestamp, session_id, model, cost_usd, duration_ms,
                    input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
                    speed, user_email, organization_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            self.exec("BEGIN TRANSACTION")

            for req in requests {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                sqlite3_bind_double(stmt, 1, req.timestamp.timeIntervalSince1970)
                self.bindTextOrNull(stmt, 2, req.sessionId)
                sqlite3_bind_text(stmt, 3, (req.model as NSString).utf8String, -1, nil)
                sqlite3_bind_double(stmt, 4, req.costUSD)
                sqlite3_bind_int(stmt, 5, Int32(req.durationMs))
                sqlite3_bind_int(stmt, 6, Int32(req.inputTokens))
                sqlite3_bind_int(stmt, 7, Int32(req.outputTokens))
                sqlite3_bind_int(stmt, 8, Int32(req.cacheReadTokens))
                sqlite3_bind_int(stmt, 9, Int32(req.cacheCreationTokens))
                self.bindTextOrNull(stmt, 10, req.speed)
                self.bindTextOrNull(stmt, 11, req.userEmail)
                self.bindTextOrNull(stmt, 12, req.organizationId)

                sqlite3_step(stmt)
            }

            self.exec("COMMIT")
        }
    }

    func insertToolResults(_ results: [ParsedToolResult]) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }

            let sql = """
                INSERT INTO tool_results (timestamp, session_id, tool_name, success, duration_ms)
                VALUES (?, ?, ?, ?, ?)
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            self.exec("BEGIN TRANSACTION")

            for result in results {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                sqlite3_bind_double(stmt, 1, result.timestamp.timeIntervalSince1970)
                self.bindTextOrNull(stmt, 2, result.sessionId)
                sqlite3_bind_text(stmt, 3, (result.toolName as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 4, result.success ? 1 : 0)
                sqlite3_bind_int(stmt, 5, Int32(result.durationMs))

                sqlite3_step(stmt)
            }

            self.exec("COMMIT")
        }
    }

    // MARK: - Query

    func fetchAPIRequests(
        limit: Int = 100,
        offset: Int = 0,
        modelFilter: String? = nil,
        fromDate: Date? = nil,
        toDate: Date? = nil
    ) -> [OTelAPIRequest] {
        queue.sync {
            guard let db else { return [] }

            var conditions: [String] = []
            var params: [Any] = []

            if let model = modelFilter {
                conditions.append("model = ?")
                params.append(model)
            }
            if let from = fromDate {
                conditions.append("timestamp >= ?")
                params.append(from.timeIntervalSince1970)
            }
            if let to = toDate {
                conditions.append("timestamp <= ?")
                params.append(to.timeIntervalSince1970)
            }

            var sql = "SELECT id, timestamp, session_id, model, cost_usd, duration_ms, input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens, speed, user_email, organization_id FROM api_requests"

            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }
            sql += " ORDER BY timestamp DESC LIMIT ? OFFSET ?"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            var idx: Int32 = 1
            for param in params {
                if let s = param as? String {
                    sqlite3_bind_text(stmt, idx, (s as NSString).utf8String, -1, nil)
                } else if let d = param as? Double {
                    sqlite3_bind_double(stmt, idx, d)
                } else if let ti = param as? TimeInterval {
                    sqlite3_bind_double(stmt, idx, ti)
                }
                idx += 1
            }
            sqlite3_bind_int(stmt, idx, Int32(limit))
            sqlite3_bind_int(stmt, idx + 1, Int32(offset))

            var results: [OTelAPIRequest] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let request = OTelAPIRequest(
                    id: sqlite3_column_int64(stmt, 0),
                    timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                    sessionId: columnText(stmt, 2),
                    model: columnText(stmt, 3) ?? "unknown",
                    costUSD: sqlite3_column_double(stmt, 4),
                    durationMs: Int(sqlite3_column_int(stmt, 5)),
                    inputTokens: Int(sqlite3_column_int(stmt, 6)),
                    outputTokens: Int(sqlite3_column_int(stmt, 7)),
                    cacheReadTokens: Int(sqlite3_column_int(stmt, 8)),
                    cacheCreationTokens: Int(sqlite3_column_int(stmt, 9)),
                    speed: columnText(stmt, 10),
                    userEmail: columnText(stmt, 11),
                    organizationId: columnText(stmt, 12)
                )
                results.append(request)
            }
            return results
        }
    }

    func fetchDaySummary(fromDate: Date? = nil, toDate: Date? = nil) -> [OTelDaySummary] {
        queue.sync {
            guard let db else { return [] }

            var conditions: [String] = []
            var params: [Any] = []

            if let from = fromDate {
                conditions.append("timestamp >= ?")
                params.append(from.timeIntervalSince1970)
            }
            if let to = toDate {
                conditions.append("timestamp <= ?")
                params.append(to.timeIntervalSince1970)
            }

            // First get daily totals
            var sql = """
                SELECT date(timestamp, 'unixepoch', 'localtime') as day,
                       SUM(cost_usd) as total_cost,
                       COUNT(*) as total_requests,
                       SUM(input_tokens) as total_input,
                       SUM(output_tokens) as total_output,
                       SUM(cache_read_tokens) as total_cache_read,
                       SUM(cache_creation_tokens) as total_cache_creation
                FROM api_requests
                """
            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }
            sql += " GROUP BY day ORDER BY day DESC"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            var idx: Int32 = 1
            for param in params {
                if let d = param as? Double {
                    sqlite3_bind_double(stmt, idx, d)
                } else if let ti = param as? TimeInterval {
                    sqlite3_bind_double(stmt, idx, ti)
                }
                idx += 1
            }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = .current

            var summaries: [OTelDaySummary] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let dayStr = columnText(stmt, 0) ?? ""
                let date = dateFormatter.date(from: dayStr) ?? Date()

                let summary = OTelDaySummary(
                    id: dayStr,
                    date: date,
                    totalCostUSD: sqlite3_column_double(stmt, 1),
                    totalRequests: Int(sqlite3_column_int(stmt, 2)),
                    totalInputTokens: Int(sqlite3_column_int(stmt, 3)),
                    totalOutputTokens: Int(sqlite3_column_int(stmt, 4)),
                    totalCacheReadTokens: Int(sqlite3_column_int(stmt, 5)),
                    totalCacheCreationTokens: Int(sqlite3_column_int(stmt, 6)),
                    modelBreakdown: fetchModelBreakdown(for: dayStr, db: db)
                )
                summaries.append(summary)
            }
            return summaries
        }
    }

    private func fetchModelBreakdown(for day: String, db: OpaquePointer) -> [OTelDaySummary.ModelSummary] {
        let sql = """
            SELECT model, COUNT(*) as requests, SUM(cost_usd) as cost,
                   SUM(input_tokens) as input_tok, SUM(output_tokens) as output_tok
            FROM api_requests
            WHERE date(timestamp, 'unixepoch', 'localtime') = ?
            GROUP BY model ORDER BY cost DESC
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (day as NSString).utf8String, -1, nil)

        var models: [OTelDaySummary.ModelSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let modelName = columnText(stmt, 0) ?? "unknown"
            models.append(OTelDaySummary.ModelSummary(
                id: modelName,
                model: modelName,
                requests: Int(sqlite3_column_int(stmt, 1)),
                costUSD: sqlite3_column_double(stmt, 2),
                inputTokens: Int(sqlite3_column_int(stmt, 3)),
                outputTokens: Int(sqlite3_column_int(stmt, 4))
            ))
        }
        return models
    }

    func fetchDistinctModels() -> [String] {
        queue.sync {
            guard let db else { return [] }

            let sql = "SELECT DISTINCT model FROM api_requests ORDER BY model"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            var models: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let model = columnText(stmt, 0) {
                    models.append(model)
                }
            }
            return models
        }
    }

    func totalAPIRequestCount() -> Int {
        queue.sync {
            guard let db else { return 0 }

            let sql = "SELECT COUNT(*) FROM api_requests"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
            return 0
        }
    }

    func totalToolResultCount() -> Int {
        queue.sync {
            guard let db else { return 0 }

            let sql = "SELECT COUNT(*) FROM tool_results"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
            return 0
        }
    }

    // MARK: - Maintenance

    func pruneOldEvents(olderThanDays: Int = 30) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }

            let cutoff = Date().addingTimeInterval(-Double(olderThanDays) * 86400).timeIntervalSince1970

            var stmt: OpaquePointer?

            let apiSQL = "DELETE FROM api_requests WHERE timestamp < ?"
            if sqlite3_prepare_v2(db, apiSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, cutoff)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }

            let toolSQL = "DELETE FROM tool_results WHERE timestamp < ?"
            stmt = nil
            if sqlite3_prepare_v2(db, toolSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, cutoff)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }

            LoggingService.shared.log("OTelDatabase: Pruned events older than \(olderThanDays) days")
        }
    }

    // MARK: - SQLite Helpers

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func bindTextOrNull(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }
}

// MARK: - Errors

enum OTelDatabaseError: Error, LocalizedError {
    case openFailed(String)
    case schemaFailed

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "Failed to open OTel database: \(msg)"
        case .schemaFailed: return "Failed to create OTel database schema"
        }
    }
}
