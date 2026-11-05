import CFontConfig
import Glibc
import PerryObjCInterop

// CGFonts. A font made from data (a TrueType or OpenType file an app ships)
// is named by the PostScript name in its 'name' table, and its file is
// added to the fonts FontConfig chooses from, so the text Silica draws in
// that name uses it; a font made from a name is only the name.

extension TypeIDs {
    static let font: UInt = 80
}

final class FontState: @unchecked Sendable {
    let postScriptName: String?
    let fullName: String?

    init(postScriptName: String?, fullName: String?) {
        self.postScriptName = postScriptName
        self.fullName = fullName
    }
}

@ObjCClass("CGFont")
public final class CGFontObject: NSObject {
    static let states = StateTable<FontState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGFontObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGFontObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.font }
}

enum Fonts {
    /// The strings of a font file's 'name' table by name ID: 4 the full
    /// name, 6 the PostScript name. Windows' UTF-16 records are preferred
    /// to Macintosh Roman ones.
    static func names(_ bytes: [UInt8]) -> [Int: String] {
        func u16(_ at: Int) -> Int? { at + 2 <= bytes.count ? Int(bytes[at]) << 8 | Int(bytes[at + 1]) : nil }
        func u32(_ at: Int) -> Int? {
            guard let high = u16(at), let low = u16(at + 2) else { return nil }
            return high << 16 | low
        }
        // A collection's first font.
        var base = 0
        if bytes.starts(with: Array("ttcf".utf8)), let first = u32(12) { base = first }
        guard let tableCount = u16(base + 4) else { return [:] }
        var names: [Int: String] = [:]
        for index in 0 ..< tableCount {
            let record = base + 12 + index * 16
            guard record + 16 <= bytes.count, String(decoding: bytes[record ..< record + 4], as: UTF8.self) == "name",
                  let table = u32(record + 8), let count = u16(table + 2), let storage = u16(table + 4) else { continue }
            for entry in 0 ..< count {
                let at = table + 6 + entry * 12
                guard let platform = u16(at), let id = u16(at + 6), let length = u16(at + 8), let offset = u16(at + 10) else { break }
                let start = table + storage + offset
                guard start + length <= bytes.count else { continue }
                let raw = bytes[start ..< start + length]
                if platform == 3 || platform == 0 {
                    var units: [UInt16] = []
                    var i = raw.startIndex
                    while i + 1 < raw.endIndex {
                        units.append(UInt16(raw[i]) << 8 | UInt16(raw[i + 1]))
                        i += 2
                    }
                    names[id] = String(decoding: units, as: UTF16.self)
                } else if platform == 1, names[id] == nil {
                    names[id] = String(decoding: raw, as: UTF8.self)
                }
            }
        }
        return names
    }

    /// Writes the font's file where FontConfig can read it and adds it to
    /// the application's fonts.
    static func install(_ bytes: [UInt8], name: String) {
        let directory = (getenv("TMPDIR").map { String(cString: $0) } ?? "/tmp") + "/perry-fonts"
        mkdir(directory, 0o755)
        let safe = String(name.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
        let path = directory + "/" + safe + ".font"
        guard let file = fopen(path, "wb") else { return }
        _ = bytes.withUnsafeBytes { fwrite($0.baseAddress, 1, $0.count, file) }
        fclose(file)
        _ = path.withCString { FcConfigAppFontAddFile(nil, $0) }
    }
}

@c(_CGFontGetTypeID) public func CGFontGetTypeID() -> UInt { TypeIDs.font }

@c(_CGFontCreateWithDataProvider)
public func CGFontCreateWithDataProvider(_ provider: Ref?) -> Ref? {
    guard let bytes = DataProviders.bytes(provider), bytes.count > 12 else { return nil }
    let names = Fonts.names(bytes)
    guard let postScriptName = names[6] ?? names[4] else { return nil }
    Fonts.install(bytes, name: postScriptName)
    return makeObject(CGFontObject.objCClass, CGFontObject.states, FontState(postScriptName: postScriptName, fullName: names[4]))
}

@c(_CGFontCreateWithFontName)
public func CGFontCreateWithFontName(_ name: Ref?) -> Ref? {
    guard let name else { return nil }
    let string = String(objCArgument: name)
    return makeObject(CGFontObject.objCClass, CGFontObject.states, FontState(postScriptName: string, fullName: string))
}

@c(_CGFontCopyPostScriptName)
public func CGFontCopyPostScriptName(_ font: Ref?) -> Ref? {
    CGFontObject.states[font]?.postScriptName.map { $0.objCOwnedReturnValue() } ?? nil
}

@c(_CGFontCopyFullName)
public func CGFontCopyFullName(_ font: Ref?) -> Ref? {
    CGFontObject.states[font]?.fullName.map { $0.objCOwnedReturnValue() } ?? nil
}

@c(_CGFontRetain) public func CGFontRetain(_ font: Ref?) -> Ref? { ObjCRuntime.retain(font) }
@c(_CGFontRelease) public func CGFontRelease(_ font: Ref?) { ObjCRuntime.release(font) }
