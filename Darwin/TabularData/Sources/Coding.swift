// Encoding and decoding column elements with Combine's top-level encoders
// and decoders.

import Combine
import Foundation

public struct ColumnEncodingError: Error, LocalizedError, CustomDebugStringConvertible {
    public var columnName: String
    public var rowIndex: Int
    public var encodingError: EncodingError

    public init(columnName: String, rowIndex: Int, encodingError: EncodingError) {
        self.columnName = columnName
        self.rowIndex = rowIndex
        self.encodingError = encodingError
    }

    public var debugDescription: String {
        let detail: String
        switch encodingError {
        case .invalidValue(_, let context): detail = context.debugDescription
        @unknown default: detail = "\(encodingError)"
        }
        return "In column '\(columnName)' at row \(rowIndex): \(detail)"
    }
}

public struct ColumnDecodingError: Error, LocalizedError, CustomDebugStringConvertible {
    public var columnName: String
    public var rowIndex: Int
    public var decodingError: DecodingError

    public init(columnName: String, rowIndex: Int, decodingError: DecodingError) {
        self.columnName = columnName
        self.rowIndex = rowIndex
        self.decodingError = decodingError
    }

    public var debugDescription: String {
        let detail: String
        switch decodingError {
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .keyNotFound(_, let context),
             .dataCorrupted(let context):
            detail = context.debugDescription
        @unknown default:
            detail = "\(decodingError)"
        }
        return "In column '\(columnName)' at row \(rowIndex): \(detail)"
    }
}

extension Column where WrappedElement: Encodable {
    public func encoded<Encoder>(using encoder: Encoder) throws -> Column<Encoder.Output> where Encoder: TopLevelEncoder {
        var result = Column<Encoder.Output>(name: name, capacity: count)
        for (row, element) in enumerated() {
            guard let element else {
                result.append(nil)
                continue
            }
            do {
                result.append(try encoder.encode(element))
            } catch let error as EncodingError {
                throw ColumnEncodingError(columnName: name, rowIndex: row, encodingError: error)
            }
        }
        return result
    }
}

extension AnyColumn {
    public func encoded<T, Encoder>(_ type: T.Type, using encoder: Encoder) throws -> AnyColumn
    where T: Encodable, Encoder: TopLevelEncoder {
        try assumingType(T.self).encoded(using: encoder).eraseToAnyColumn()
    }

    public mutating func encode<T, Encoder>(_ type: T.Type, using encoder: Encoder) throws where T: Encodable, Encoder: TopLevelEncoder {
        self = try encoded(type, using: encoder)
    }
}

extension DataFrame {
    public mutating func encodeColumn<T, Encoder>(_ columnName: String, _ type: T.Type, using encoder: Encoder) throws
    where T: Encodable, Encoder: TopLevelEncoder {
        let index = _requireColumn(columnName)
        _columns[index] = try _columns[index].encoded(T.self, using: encoder)
    }

    public mutating func encodeColumn<T, Encoder>(_ id: ColumnID<T>, using encoder: Encoder) throws
    where T: Encodable, Encoder: TopLevelEncoder {
        try encodeColumn(id.name, T.self, using: encoder)
    }
}

extension Column {
    public func decoded<T, Decoder>(_ type: T.Type, using decoder: Decoder) throws -> Column<T>
    where WrappedElement == Decoder.Input, T: Decodable, Decoder: TopLevelDecoder {
        var result = Column<T>(name: name, capacity: count)
        for (row, element) in enumerated() {
            guard let element else {
                result.append(nil)
                continue
            }
            do {
                result.append(try decoder.decode(T.self, from: element))
            } catch let error as DecodingError {
                throw ColumnDecodingError(columnName: name, rowIndex: row, decodingError: error)
            }
        }
        return result
    }
}

extension AnyColumn {
    public func decoded<T, Decoder>(_ type: T.Type, using decoder: Decoder) throws -> AnyColumn
    where T: Decodable, Decoder: TopLevelDecoder {
        try assumingType(Decoder.Input.self).decoded(T.self, using: decoder).eraseToAnyColumn()
    }

    public mutating func decode<T, Decoder>(_ type: T.Type, using decoder: Decoder) throws where T: Decodable, Decoder: TopLevelDecoder {
        self = try decoded(type, using: decoder)
    }
}

extension DataFrame {
    public mutating func decode<T, Decoder>(_ type: T.Type, inColumn columnName: String, using decoder: Decoder) throws
    where T: Decodable, Decoder: TopLevelDecoder {
        let index = _requireColumn(columnName)
        _columns[index] = try _columns[index].decoded(T.self, using: decoder)
    }

    public mutating func decode<T, Decoder>(_ type: T.Type, inColumn id: ColumnID<Decoder.Input>, using decoder: Decoder) throws
    where T: Decodable, Decoder: TopLevelDecoder {
        try decode(T.self, inColumn: id.name, using: decoder)
    }
}
