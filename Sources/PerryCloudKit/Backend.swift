import Dispatch
import Glibc
import PerryObjCInterop

// The requests a CKDatabase sends to CloudKit Web Services through MistKit,
// when PERRY_CLOUDKIT_API_TOKEN is set (Configuration.swift). Records carry
// strings, numbers and dates; queries are for every record of a type; other
// requests end with the error an unsupported request gets.

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithLongLong:") static func make(longLong: Int64) -> NSNumber
    @ObjCClassMethod("numberWithDouble:") static func make(double: Double) -> NSNumber
    @ObjCMethod("doubleValue") func doubleValue() -> Double
    @ObjCMethod("longLongValue") func longLongValue() -> Int64
    @ObjCMethod("objCType") func objCType() -> UnsafePointer<CChar>?
}

@ObjCWrapper("NSDate")
class NSDate: NSObject {
    @ObjCClassMethod("dateWithTimeIntervalSince1970:") static func make(timeIntervalSince1970: Double) -> NSDate
    @ObjCMethod("timeIntervalSince1970") func timeIntervalSince1970() -> Double
}

@ObjCWrapper("NSString")
class NSString: NSObject {
    @ObjCClassMethod("stringWithString:") static func make(string: String) -> NSString
    @ObjCMethod("UTF8String") func utf8() -> UnsafePointer<CChar>?
}

extension NSObject {
    @ObjCMethod("predicateFormat") func sendPredicateFormat() -> String?
}

enum Backend {
    /// CKErrorNotAuthenticated 9, CKErrorUnknownItem 11, CKErrorInvalidArguments 12,
    /// CKErrorInternalError 1.
    static func error(_ code: Int, _ message: String) -> NSError {
        CloudTrace.say("request failed: \(message)")
        return NSError.error(domain: CloudKitConstants.CKErrorDomain, code: code, userInfo: nil)
    }

    /// Whether requests go to MistKit.
    static var enabled: Bool { CloudKitConfiguration.current != nil }

    /// Runs `body` off the caller's queue, as CloudKit answers.
    static func answer(_ body: @escaping @Sendable () -> Void) { DispatchQueue.global().async(execute: body) }

    /// Calls a (record, error) completion handler.
    static func call(_ handler: UnsafeSendableBlock?, _ first: UnsafeMutableRawPointer?, _ error: NSError?) {
        guard let block = handler?.block else { return }
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        block.function(as: Invoke.self)(block.object, first, error?.objcObject)
    }

    static func recordName(_ id: NSObject?) -> String? {
        guard let id, id.is(CKRecordID.self) else { return nil }
        return id.unsafeCast(to: CKRecordID.self).cloud.name
    }

    static func makeRecordID(_ name: String) -> CKRecordID {
        let id = NSObject(CKRecordID.objCClass.pointer).newInstance().unsafeCast(to: CKRecordID.self)
        id.cloud.name = name
        return id
    }
}

/// A value carried into another queue, kept alive by the request's caller.
final class Locked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

@ObjCWrapper("NSMutableArray")
class NSMutableArray: NSObject {
    @ObjCClassMethod("array") static func make() -> NSMutableArray
    @ObjCMethod("addObject:") func add(_ object: NSObject)
}

#if PERRY_MISTKIT

extension Backend {
    /// A field value as a CKRecord keeps it: an NSString, NSNumber or NSDate.
    static func object(_ field: RemoteField) -> NSObject {
        switch field {
        case .string(let text): return NSString.make(string: text)
        case .integer(let number): return NSNumber.make(longLong: number)
        case .double(let number): return NSNumber.make(double: number)
        case .date(let seconds): return NSDate.make(timeIntervalSince1970: seconds)
        }
    }

    /// A CKRecord field for MistKit; nil for a kind of value that is not sent.
    static func field(_ value: NSObject) -> RemoteField? {
        if value.is(NSString.self), let text = value.unsafeCast(to: NSString.self).utf8() { return .string(String(cString: text)) }
        if value.is(NSDate.self) { return .date(value.unsafeCast(to: NSDate.self).timeIntervalSince1970()) }
        if value.is(NSNumber.self) {
            let number = value.unsafeCast(to: NSNumber.self)
            // 'd' and 'f' are floating point; the rest are integers.
            if let type = number.objCType(), type.pointee == 0x64 || type.pointee == 0x66 { return .double(number.doubleValue()) }
            return .integer(number.longLongValue())
        }
        return nil
    }

    static func makeRecord(_ remote: RemoteRecord) -> CKRecord {
        let record = NSObject(CKRecord.objCClass.pointer).newInstance().unsafeCast(to: CKRecord.self)
        record.cloud.type = remote.type
        record.cloud.recordID = makeRecordID(remote.name)
        for (key, value) in remote.fields { record.cloud.values[key] = object(value) }
        return record
    }

    static func fetch(container: String, scope: Int, recordID: NSObject?, completion: ObjCBlock?) {
        let handler = completion.map(UnsafeSendableBlock.init)
        guard let name = recordName(recordID) else { return call(handler, nil, error(12, "fetch without a record ID")) }
        MistKitClient.fetch(container: container, scope: scope, name: name) { result in
            answer {
                switch result {
                case .success(let remote?): call(handler, makeRecord(remote).objcObject, nil)
                case .success(nil): call(handler, nil, error(11, "no record \(name)"))
                case .failure(let failure): call(handler, nil, error(1, "fetch \(name): \(failure)"))
                }
            }
        }
    }

    static func query(container: String, scope: Int, query: NSObject?, completion: ObjCBlock?) {
        let handler = completion.map(UnsafeSendableBlock.init)
        guard let query, query.is(CKQuery.self), let type = query.unsafeCast(to: CKQuery.self).cloud.type else {
            return call(handler, nil, error(12, "query without a record type"))
        }
        // Only a query for every record of the type is sent: a predicate is not translated.
        if let format = query.unsafeCast(to: CKQuery.self).cloud.predicate?.sendPredicateFormat(), format != "TRUEPREDICATE" {
            return call(handler, nil, error(12, "query predicate \(format) is not supported"))
        }
        MistKitClient.query(container: container, scope: scope, type: type) { result in
            answer {
                switch result {
                case .success(let records):
                    let array = NSMutableArray.make()
                    for record in records { array.add(makeRecord(record)) }
                    call(handler, array.objcObject, nil)
                case .failure(let failure): call(handler, nil, error(1, "query \(type): \(failure)"))
                }
            }
        }
    }

    static func save(container: String, scope: Int, record: NSObject?, completion: ObjCBlock?) {
        let handler = completion.map(UnsafeSendableBlock.init)
        guard let record, record.is(CKRecord.self) else { return call(handler, nil, error(12, "save without a record")) }
        let typed = record.unsafeCast(to: CKRecord.self)
        guard let type = typed.cloud.type, let name = recordName(typed.cloud.recordID) else {
            return call(handler, nil, error(12, "save of a record with no type or ID"))
        }
        var remote = RemoteRecord(type: type, name: name)
        for (key, value) in typed.cloud.values {
            if let converted = field(value) { remote.fields[key] = converted } else { CloudTrace.say("field \(key) of a kind not sent") }
        }
        let kept = Locked(record)
        MistKitClient.save(container: container, scope: scope, record: remote) { result in
            answer {
                switch result {
                case .success(true): call(handler, kept.value.objcObject, nil)
                case .success(false): call(handler, nil, error(1, "save \(name) refused"))
                case .failure(let failure): call(handler, nil, error(1, "save \(name): \(failure)"))
                }
            }
        }
    }

    static func delete(container: String, scope: Int, recordID: NSObject?, completion: ObjCBlock?) {
        let handler = completion.map(UnsafeSendableBlock.init)
        guard let name = recordName(recordID), let recordID else { return call(handler, nil, error(12, "delete without a record ID")) }
        let kept = Locked(recordID)
        MistKitClient.delete(container: container, scope: scope, name: name) { result in
            answer {
                switch result {
                case .success: call(handler, kept.value.objcObject, nil)
                case .failure(let failure): call(handler, nil, error(1, "delete \(name): \(failure)"))
                }
            }
        }
    }
}

#else

extension Backend {
    static func fetch(container: String, scope: Int, recordID: NSObject?, completion: ObjCBlock?) {}
    static func query(container: String, scope: Int, query: NSObject?, completion: ObjCBlock?) {}
    static func save(container: String, scope: Int, record: NSObject?, completion: ObjCBlock?) {}
    static func delete(container: String, scope: Int, recordID: NSObject?, completion: ObjCBlock?) {}
}

#endif
