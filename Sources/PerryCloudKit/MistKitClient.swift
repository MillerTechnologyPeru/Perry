#if PERRY_MISTKIT
import Foundation
import MistKit

// CloudKit Web Services through MistKit, in plain Swift values: this file
// imports Foundation, whose classes share names with Perry's Objective-C
// ones, so none of those appear here. Backend.swift joins the two.

/// A field value of a record.
enum RemoteField: Sendable {
    case string(String)
    case integer(Int64)
    case double(Double)
    /// Seconds since 1970.
    case date(Double)
}

struct RemoteRecord: Sendable {
    var type: String?
    var name: String
    var fields: [String: RemoteField] = [:]
}

enum MistKitClient {
    private static let lock = Lock()
    nonisolated(unsafe) private static var services: [String: CloudKitService] = [:]

    private static func service(_ configuration: CloudKitConfiguration, _ identifier: String) throws -> CloudKitService {
        let name = configuration.container ?? identifier
        return try lock.withLock {
            if let service = services[name] { return service }
            let credentials = try Credentials(apiAuth: APICredentials(apiToken: configuration.apiToken,
                                                                       webAuthToken: configuration.webAuthToken))
            let service = CloudKitService(containerIdentifier: name, credentials: credentials,
                                          environment: configuration.environment == .development ? .development : .production)
            services[name] = service
            return service
        }
    }

    /// CKDatabaseScope: public 1, private 2, shared 3.
    private static func database(_ scope: Int) -> Database {
        switch scope {
        case 1: return .public(.prefers(.webAuth))
        case 3: return .shared
        default: return .private
        }
    }

    private static func remote(_ info: RecordInfo) -> RemoteRecord {
        var record = RemoteRecord(type: info.recordType, name: info.recordName)
        for (key, value) in info.fields {
            switch value {
            case .string(let text): record.fields[key] = .string(text)
            case .int64(let number): record.fields[key] = .integer(Int64(number))
            case .double(let number): record.fields[key] = .double(number)
            case .date(let date): record.fields[key] = .date(date.timeIntervalSince1970)
            default: CloudTrace.say("field \(key) of a kind not received")
            }
        }
        return record
    }

    private static func mistKit(_ field: RemoteField) -> FieldValue {
        switch field {
        case .string(let text): return .string(text)
        case .integer(let number): return .int64(Int(number))
        case .double(let number): return .double(number)
        case .date(let seconds): return .date(Date(timeIntervalSince1970: seconds))
        }
    }

    /// Runs a request in a task and gives its result.
    private static func run<T: Sendable>(_ container: String, _ done: @escaping @Sendable (Result<T, Error>) -> Void,
                                         _ body: @escaping @Sendable (CloudKitService) async throws -> T) {
        guard let configuration = CloudKitConfiguration.current else { return done(.failure(RemoteError.disabled)) }
        Task {
            do { done(.success(try await body(try service(configuration, container)))) } catch { done(.failure(error)) }
        }
    }

    /// The record, or nil when there is none.
    static func fetch(container: String, scope: Int, name: String, done: @escaping @Sendable (Result<RemoteRecord?, Error>) -> Void) {
        run(container, done) { service in
            let results = try await service.lookupRecords(recordNames: [name], database: database(scope))
            guard let result = results.first, case .success(let info) = result else { return nil }
            return remote(info)
        }
    }

    /// Every record of the type.
    static func query(container: String, scope: Int, type: String, done: @escaping @Sendable (Result<[RemoteRecord], Error>) -> Void) {
        run(container, done) { service in
            try await service.queryRecords(Query(recordType: type), database: database(scope)).records.map(remote)
        }
    }

    /// Creates the record or replaces it.
    static func save(container: String, scope: Int, record: RemoteRecord, done: @escaping @Sendable (Result<Bool, Error>) -> Void) {
        run(container, done) { service in
            let operation = RecordOperation(operationType: .forceReplace, recordType: record.type ?? "", recordName: record.name,
                                            fields: record.fields.mapValues(mistKit))
            let results = try await service.modifyRecords([operation], database: database(scope))
            if let result = results.first, case .failure = result { return false }
            return true
        }
    }

    static func delete(container: String, scope: Int, name: String, done: @escaping @Sendable (Result<Bool, Error>) -> Void) {
        run(container, done) { service in
            let operation = RecordOperation(operationType: .forceDelete, recordType: "", recordName: name)
            _ = try await service.modifyRecords([operation], database: database(scope))
            return true
        }
    }
}

enum RemoteError: Error { case disabled }
#endif
