import FoundationEssentials
import Glibc
import PerryObjCInterop

// CFFTPCreateParsedResourceListing: one line of an FTP server's directory
// listing, as `ls -l` writes it, read into a dictionary of the
// kCFFTPResource keys, as Darwin's does: the file's type (sys/dirent.h's
// DT_ value) and permissions (with the set-ID and sticky bits) from its
// mode string, owner, group, size, modification date (in local time, this
// year when the line gives a time instead of one) and name, with a
// symbolic link's target apart. The size is the field before the date, the
// group the one before that, and the owner the one before that unless the
// line has no group. A line of another form gives its whole text as the
// name; a "total" line or an empty one gives nothing.

@ObjCConstants
enum FTPResourceKeys {
    static let kCFFTPResourceMode = "kCFFTPResourceMode"
    static let kCFFTPResourceName = "kCFFTPResourceName"
    static let kCFFTPResourceOwner = "kCFFTPResourceOwner"
    static let kCFFTPResourceGroup = "kCFFTPResourceGroup"
    static let kCFFTPResourceLink = "kCFFTPResourceLink"
    static let kCFFTPResourceSize = "kCFFTPResourceSize"
    static let kCFFTPResourceType = "kCFFTPResourceType"
    static let kCFFTPResourceModDate = "kCFFTPResourceModDate"
}

enum FTPListing {
    struct Resource {
        var type: Int64
        var mode: Int64
        var owner: String
        var group: String
        var size: Int64
        var date: Date
        var name: String
        var link: String
    }

    static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// DT_FIFO, DT_CHR, DT_DIR, DT_BLK, DT_REG, DT_LNK and DT_SOCK, by the
    /// mode string's first character.
    static func fileType(_ character: Character) -> Int64? {
        switch character {
        case "p": return 1
        case "c": return 2
        case "d": return 4
        case "b": return 6
        case "-": return 8
        case "l": return 10
        case "s": return 12
        default: return nil
        }
    }

    /// The permission bits of "rwxr-xr-x", with set-user-ID, set-group-ID
    /// and sticky bits from s, S, t and T.
    static func permissions(_ text: Substring) -> Int64? {
        let characters = Array(text)
        guard characters.count >= 9 else { return nil }
        var mode: Int64 = 0
        for (index, character) in characters.prefix(9).enumerated() {
            let bit = Int64(1) << (8 - index)
            let special: Int64 = index == 2 ? 0o4000 : index == 5 ? 0o2000 : index == 8 ? 0o1000 : 0
            switch character {
            case "-": break
            case "r" where index % 3 == 0, "w" where index % 3 == 1, "x" where index % 3 == 2: mode |= bit
            case "s" where special != 0 && index != 8, "t" where index == 8: mode |= bit | special
            case "S" where special != 0 && index != 8, "T" where index == 8: mode |= special
            default: return nil
            }
        }
        return mode
    }

    /// The date of "Jan  5 12:34" (this year) or "Mar 10  2020", local time.
    static func modificationDate(month: Int, day: Int, timeOrYear: Substring) -> Date? {
        var parts = tm()
        var now = time(nil)
        localtime_r(&now, &parts)
        parts.tm_mon = Int32(month)
        parts.tm_mday = Int32(day)
        parts.tm_sec = 0
        if let colon = timeOrYear.firstIndex(of: ":") {
            guard let hour = Int32(timeOrYear[..<colon]), let minute = Int32(timeOrYear[timeOrYear.index(after: colon)...]),
                  (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
            parts.tm_hour = hour
            parts.tm_min = minute
        } else {
            guard let year = Int32(timeOrYear), year >= 1900 else { return nil }
            parts.tm_year = year - 1900
            parts.tm_hour = 0
            parts.tm_min = 0
        }
        parts.tm_isdst = -1
        let seconds = mktime(&parts)
        guard seconds != -1 else { return nil }
        return Date(timeIntervalSince1970: Double(seconds))
    }

    /// A Unix listing line, or nil when it isn't one.
    static func parse(_ line: String) -> Resource? {
        // The fields, each with where it ends in the line.
        var fields: [(text: Substring, end: String.Index)] = []
        var index = line.startIndex
        while index < line.endIndex {
            while index < line.endIndex, line[index] == " " || line[index] == "\t" { index = line.index(after: index) }
            guard index < line.endIndex else { break }
            let start = index
            while index < line.endIndex, line[index] != " " && line[index] != "\t" { index = line.index(after: index) }
            fields.append((line[start..<index], index))
        }
        guard fields.count >= 6, let first = fields[0].text.first, let type = fileType(first),
              let mode = permissions(fields[0].text.dropFirst()) else { return nil }
        // The month, followed by a day and a time or year.
        var found: (index: Int, month: Int, day: Int, date: Date)?
        for position in 4..<max(4, fields.count - 3) {
            guard let month = months.firstIndex(of: fields[position].text.lowercased()), let day = Int(fields[position + 1].text),
                  (1...31).contains(day), let date = modificationDate(month: month, day: day, timeOrYear: fields[position + 2].text) else { continue }
            found = (position, month, day, date)
            break
        }
        guard let found, let size = Int64(fields[found.index - 1].text) else { return nil }
        let owner = String(fields[max(2, found.index - 3)].text)
        let group = String(fields[found.index - 2].text)
        // The name is the rest of the line after the time or year.
        var nameStart = fields[found.index + 2].end
        while nameStart < line.endIndex, line[nameStart] == " " || line[nameStart] == "\t" { nameStart = line.index(after: nameStart) }
        var name = String(line[nameStart...])
        var link = ""
        if type == 10, let arrow = name.range(of: " -> ") {
            link = String(name[arrow.upperBound...])
            name = String(name[..<arrow.lowerBound])
        }
        guard !name.isEmpty else { return nil }
        return Resource(type: type, mode: mode, owner: owner, group: group, size: size, date: found.date, name: name, link: link)
    }

    /// The dictionary for a line, or nil for one that describes nothing.
    static func dictionary(_ bytes: [UInt8]) -> NSMutableDictionary? {
        let line = String(validating: bytes, as: UTF8.self) ?? String(bytes.map { Character(Unicode.Scalar($0)) })
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("total ") || trimmed == "total" { return nil }
        guard let resource = parse(line) else {
            return NSMutableDictionary.of([(FTPResourceKeys.kCFFTPResourceName, NSObject.string(line))])
        }
        return NSMutableDictionary.of([
            (FTPResourceKeys.kCFFTPResourceType, NSNumber.make(int64: resource.type)),
            (FTPResourceKeys.kCFFTPResourceMode, NSNumber.make(int64: resource.mode)),
            (FTPResourceKeys.kCFFTPResourceOwner, NSObject.string(resource.owner)),
            (FTPResourceKeys.kCFFTPResourceGroup, NSObject.string(resource.group)),
            (FTPResourceKeys.kCFFTPResourceSize, NSNumber.make(int64: resource.size)),
            (FTPResourceKeys.kCFFTPResourceModDate, NSDate.of(resource.date)),
            (FTPResourceKeys.kCFFTPResourceName, NSObject.string(resource.name)),
            (FTPResourceKeys.kCFFTPResourceLink, NSObject.string(resource.link)),
        ])
    }
}

/// CFIndex CFFTPCreateParsedResourceListing(CFAllocatorRef, const UInt8
/// *buffer, CFIndex bufferLength, CFDictionaryRef *parsed): the first line
/// of the buffer, ended by a line feed (and any carriage return before it).
/// Answers the bytes the line took, line feed included, with its dictionary
/// (+1) or none; 0, with none, when the buffer has no whole line.
@c(_CFFTPCreateParsedResourceListing)
public func CFFTPCreateParsedResourceListing(_ allocator: UnsafeRawPointer?, _ buffer: UnsafePointer<UInt8>?, _ length: Int,
                                             _ parsed: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int {
    parsed?.pointee = nil
    guard let buffer, length > 0 else { return 0 }
    let bytes = UnsafeBufferPointer(start: buffer, count: length)
    guard let newline = bytes.firstIndex(of: 0x0A) else { return 0 }
    var line = Array(bytes[..<newline])
    while line.last == 0x0D { line.removeLast() }
    if let parsed, let dictionary = FTPListing.dictionary(line) { parsed.pointee = ObjCRuntime.retain(dictionary.objcObject) }
    return newline + 1
}
