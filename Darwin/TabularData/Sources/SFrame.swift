// SFrame directories (Turi Create's binary column store).

import Foundation

public enum SFrameReadingError: Error {
    case missingArchive
    case badArchive(String)
    case unsupportedArchive(String)
    case unsupportedType(Int)
    case unsupportedLayout(String)
    case badEncoding(String)
    case missingColumn(String)
}

extension SFrameReadingError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missingArchive: return "Missing SFrame archive metadata file 'dir_archive.ini'."
        case .badArchive(let detail): return "Bad SFrame archive: \(detail)"
        case .unsupportedArchive(let detail): return "Unsupported SFrame archive: \(detail)"
        case .unsupportedType(let type): return "Unsupported data type: \(type)."
        case .unsupportedLayout(let detail): return "Unsupported data layout: \(detail)"
        case .badEncoding(let detail): return "Bad data encoding: \(detail)"
        case .missingColumn(let name): return "Missing requested column '\(name)'."
        }
    }
}

extension SFrameReadingError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}

/// The sections of an INI file, each a dictionary of its keys.
private func _parseINI(_ text: String) -> [String: [String: String]] {
    var sections: [String: [String: String]] = [:]
    var current = ""
    for rawLine in text.split(whereSeparator: \.isNewline) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
        if line.hasPrefix("["), line.hasSuffix("]") {
            current = String(line.dropFirst().dropLast())
            continue
        }
        guard let equals = line.firstIndex(of: "=") else { continue }
        sections[current, default: [:]][line[..<equals].trimmingCharacters(in: .whitespaces)] =
            line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
    }
    return sections
}

extension DataFrame {
    /// Reads the archive's metadata; the column segments themselves (block
    /// compressed, in Turi's encodings) aren't read, so this throws
    /// unsupportedLayout for an archive that is otherwise valid.
    public init(contentsOfSFrameDirectory url: URL, columns: [String]? = nil, rows: Range<Int>? = nil) throws {
        let archive = url.appendingPathComponent("dir_archive.ini")
        guard let text = try? String(contentsOf: archive, encoding: .utf8) else { throw SFrameReadingError.missingArchive }
        let ini = _parseINI(text)
        guard let contents = ini["metadata"]?["contents"] else {
            throw SFrameReadingError.badArchive("missing contents in dir_archive.ini")
        }
        guard contents == "sframe" else { throw SFrameReadingError.unsupportedArchive("contents are \(contents), not sframe") }
        guard let prefix = ini["prefixes"]?.sorted(by: { $0.key < $1.key }).first?.value else {
            throw SFrameReadingError.badArchive("missing prefixes in dir_archive.ini")
        }
        let indexURL = url.appendingPathComponent(URL(fileURLWithPath: prefix).lastPathComponent + ".frame_idx")
        guard let indexText = try? String(contentsOf: indexURL, encoding: .utf8) else {
            throw SFrameReadingError.badArchive("missing frame index \(indexURL.lastPathComponent)")
        }
        let index = _parseINI(indexText)
        let names = (index["column_names"] ?? [:]).sorted { $0.key < $1.key }.map(\.value)
        for name in columns ?? [] where !names.contains(name) { throw SFrameReadingError.missingColumn(name) }
        throw SFrameReadingError.unsupportedLayout("reading SFrame column segments isn't supported")
    }
}
