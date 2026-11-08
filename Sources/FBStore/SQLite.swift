import Foundation
import CSQLite

/// Fehler der Datenbankschicht.
public struct SQLiteError: Error, CustomStringConvertible, LocalizedError {
    public let code: Int32
    public let message: String
    public let sql: String?

    public var description: String {
        if let sql { return "SQLite \(code): \(message) – \(sql)" }
        return "SQLite \(code): \(message)"
    }

    public var errorDescription: String? { "Datenbankfehler (\(code)): \(message)" }
}

/// Ein Wert für Platzhalter in SQL-Anweisungen.
public enum SQLValue: Sendable, Equatable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)

    public init(_ v: Int?) { self = v.map { .int(Int64($0)) } ?? .null }
    public init(_ v: Int64?) { self = v.map { .int($0) } ?? .null }
    public init(_ v: String?) { self = v.map { .text($0) } ?? .null }
    public init(_ v: Bool) { self = .int(v ? 1 : 0) }
    public init(_ v: Double?) { self = v.map { .double($0) } ?? .null }
    public init(_ v: Data?) { self = v.map { .blob($0) } ?? .null }
}

/// SQLITE_TRANSIENT: SQLite kopiert den gebundenen Wert sofort.
private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Eine Ergebniszeile (nur während des Schritts gültig).
public struct SQLRow {
    fileprivate let stmt: OpaquePointer

    public var columnCount: Int { Int(sqlite3_column_count(stmt)) }

    public func isNull(_ i: Int) -> Bool { sqlite3_column_type(stmt, Int32(i)) == SQLITE_NULL }

    public func int64(_ i: Int) -> Int64 { sqlite3_column_int64(stmt, Int32(i)) }
    public func int(_ i: Int) -> Int { Int(sqlite3_column_int64(stmt, Int32(i))) }
    public func bool(_ i: Int) -> Bool { sqlite3_column_int64(stmt, Int32(i)) != 0 }
    public func double(_ i: Int) -> Double { sqlite3_column_double(stmt, Int32(i)) }

    public func optInt64(_ i: Int) -> Int64? { isNull(i) ? nil : int64(i) }
    public func optInt(_ i: Int) -> Int? { isNull(i) ? nil : int(i) }

    public func string(_ i: Int) -> String {
        guard let c = sqlite3_column_text(stmt, Int32(i)) else { return "" }
        return String(cString: c)
    }

    public func optString(_ i: Int) -> String? { isNull(i) ? nil : string(i) }

    public func data(_ i: Int) -> Data? {
        guard !isNull(i) else { return nil }
        let n = Int(sqlite3_column_bytes(stmt, Int32(i)))
        guard n > 0, let p = sqlite3_column_blob(stmt, Int32(i)) else { return Data() }
        return Data(bytes: p, count: n)
    }
}

/// Schmale, sichere Hülle um eine SQLite-Verbindung.
///
/// Nicht threadsicher – der Aufrufer (`LibraryStore`) serialisiert alle Zugriffe über eine eigene Warteschlange.
public final class SQLiteConnection {
    private var db: OpaquePointer?
    private var cache: [String: OpaquePointer] = [:]
    public let path: String

    public init(path: String) throws {
        self.path = path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let handle { sqlite3_close(handle) }
            throw SQLiteError(code: rc, message: msg, sql: nil)
        }
        db = handle
        sqlite3_busy_timeout(handle, 5000)
        try execute("PRAGMA foreign_keys = ON")
        if path != ":memory:" {
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
        }
    }

    deinit {
        for (_, stmt) in cache { sqlite3_finalize(stmt) }
        cache.removeAll()
        if let db { sqlite3_close(db) }
    }

    private func error(_ rc: Int32, _ sql: String?) -> SQLiteError {
        SQLiteError(code: rc, message: db.map { String(cString: sqlite3_errmsg($0)) } ?? "?", sql: sql)
    }

    /// Führt eine oder mehrere Anweisungen ohne Parameter aus.
    public func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "?"
            sqlite3_free(err)
            throw SQLiteError(code: rc, message: msg, sql: sql)
        }
    }

    private func statement(_ sql: String) throws -> OpaquePointer {
        if let s = cache[sql] {
            sqlite3_reset(s)
            sqlite3_clear_bindings(s)
            return s
        }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else { throw error(rc, sql) }
        cache[sql] = stmt
        return stmt
    }

    private func bind(_ stmt: OpaquePointer, _ values: [SQLValue], _ sql: String) throws {
        for (offset, value) in values.enumerated() {
            let i = Int32(offset + 1)
            let rc: Int32
            switch value {
            case .null: rc = sqlite3_bind_null(stmt, i)
            case .int(let v): rc = sqlite3_bind_int64(stmt, i, v)
            case .double(let v): rc = sqlite3_bind_double(stmt, i, v)
            case .text(let v): rc = sqlite3_bind_text(stmt, i, v, -1, SQLITE_TRANSIENT_DESTRUCTOR)
            case .blob(let v):
                rc = v.withUnsafeBytes { buf in
                    sqlite3_bind_blob(stmt, i, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT_DESTRUCTOR)
                }
            }
            if rc != SQLITE_OK { throw error(rc, sql) }
        }
    }

    /// Führt eine Anweisung mit Parametern aus (INSERT/UPDATE/DELETE).
    @discardableResult
    public func run(_ sql: String, _ values: [SQLValue] = []) throws -> Int {
        let stmt = try statement(sql)
        defer { sqlite3_reset(stmt) }
        try bind(stmt, values, sql)
        var rc = sqlite3_step(stmt)
        while rc == SQLITE_ROW { rc = sqlite3_step(stmt) }
        guard rc == SQLITE_DONE else { throw error(rc, sql) }
        return Int(sqlite3_changes(db))
    }

    /// Fragt Zeilen ab und wandelt jede mit `map` um.
    public func query<T>(_ sql: String, _ values: [SQLValue] = [], _ map: (SQLRow) throws -> T) throws -> [T] {
        let stmt = try statement(sql)
        defer { sqlite3_reset(stmt) }
        try bind(stmt, values, sql)
        var result: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                result.append(try map(SQLRow(stmt: stmt)))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw error(rc, sql)
            }
        }
        return result
    }

    public func queryOne<T>(_ sql: String, _ values: [SQLValue] = [], _ map: (SQLRow) throws -> T) throws -> T? {
        try query(sql, values, map).first
    }

    public var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(db) }

    /// Führt `body` in einer Transaktion aus (bei Fehler: Rollback).
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public var userVersion: Int {
        get { (try? queryOne("PRAGMA user_version") { $0.int(0) }) ?? 0 }
    }

    public func setUserVersion(_ v: Int) throws {
        try execute("PRAGMA user_version = \(v)")
    }

    /// Prüft die Datenbankdatei („ok“ = unbeschädigt).
    public func integrityCheck() -> String {
        (try? queryOne("PRAGMA quick_check") { $0.string(0) }) ?? "error"
    }
}
