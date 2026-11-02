// The type database: iOS's declared types (the common ones), with what each
// conforms to, its filename extensions and MIME types (preferred first) and
// its description; the app's exported and imported declarations from its
// Info.plist join them. Unknown tags get dynamic types, whose identifiers
// ("dyn.") encode what they conform to and their tag.

struct TypeRecord {
    let identifier: String
    var conformsTo: [String]
    var extensions: [String]
    var mimeTypes: [String]
    var description: String?
    var dynamic = false
}

enum TagClass {
    static let filenameExtension = "public.filename-extension"
    static let mimeType = "public.mime-type"
}

enum Database {
    /// Declared types, in declaration order: a tag's first type wins.
    nonisolated(unsafe) private static var records: [TypeRecord] = builtIn
    nonisolated(unsafe) private static var byIdentifier: [String: Int] = index(builtIn)
    nonisolated(unsafe) private static var loadedBundle = false
    static let lock = Lock()

    private static func index(_ records: [TypeRecord]) -> [String: Int] {
        var index: [String: Int] = [:]
        for (offset, record) in records.enumerated() where index[record.identifier.lowercased()] == nil {
            index[record.identifier.lowercased()] = offset
        }
        return index
    }

    /// The app's UTExportedTypeDeclarations and UTImportedTypeDeclarations.
    private static func loadBundle() {
        guard !loadedBundle else { return }
        loadedBundle = true
        guard let info = NSBundle.main().infoDictionary() else { return }
        for key in ["UTExportedTypeDeclarations", "UTImportedTypeDeclarations"] {
            guard let declarations = info.object(key), declarations.isArray else { continue }
            for declaration in declarations.unsafeCast(to: NSArray.self).elements where declaration.isDictionary {
                let entry = declaration.unsafeCast(to: NSDictionary.self)
                guard let identifier = entry.object("UTTypeIdentifier")?.strings.first,
                      byIdentifier[identifier.lowercased()] == nil else { continue }
                let tags = entry.object("UTTypeTagSpecification").flatMap { $0.isDictionary ? $0.unsafeCast(to: NSDictionary.self) : nil }
                records.append(TypeRecord(identifier: identifier,
                                          conformsTo: entry.object("UTTypeConformsTo")?.strings ?? ["public.data"],
                                          extensions: tags?.object(TagClass.filenameExtension)?.strings ?? [],
                                          mimeTypes: tags?.object(TagClass.mimeType)?.strings ?? [],
                                          description: entry.object("UTTypeDescription")?.strings.first))
                byIdentifier[identifier.lowercased()] = records.count - 1
            }
        }
    }

    static func record(_ identifier: String) -> TypeRecord? {
        lock.withLock {
            loadBundle()
            if let index = byIdentifier[identifier.lowercased()] { return records[index] }
            return Dynamic.decode(identifier)
        }
    }

    static func isDeclared(_ identifier: String) -> Bool {
        lock.withLock {
            loadBundle()
            return byIdentifier[identifier.lowercased()] != nil
        }
    }

    /// Every type the identifier conforms to, itself included.
    static func ancestors(_ identifier: String) -> [String] {
        var seen: [String] = []
        var pending = [identifier]
        while let next = pending.popLast() {
            let canonical = record(next)?.identifier ?? next
            guard !seen.contains(where: { $0.lowercased() == canonical.lowercased() }) else { continue }
            seen.append(canonical)
            pending += record(canonical)?.conformsTo ?? []
        }
        return seen
    }

    static func conforms(_ identifier: String, to other: String) -> Bool {
        ancestors(identifier).contains { $0.lowercased() == other.lowercased() }
    }

    /// Declared types with the tag, in declaration order, that conform to
    /// `conformingTo` when given.
    static func types(tag: String, tagClass: String, conformingTo: String?) -> [TypeRecord] {
        let all = lock.withLock { () -> [TypeRecord] in
            loadBundle()
            return records
        }
        let wanted = tag.lowercased()
        return all.filter { record in
            let tags = tagClass == TagClass.filenameExtension ? record.extensions : tagClass == TagClass.mimeType ? record.mimeTypes : []
            return tags.contains { $0.lowercased() == wanted } && (conformingTo.map { conforms(record.identifier, to: $0) } ?? true)
        }
    }

    /// The preferred type for a tag: the first declared, else a dynamic one.
    static func preferred(tag: String, tagClass: String, conformingTo: String?) -> TypeRecord {
        types(tag: tag, tagClass: tagClass, conformingTo: conformingTo).first
            ?? Dynamic.make(tag: tag, tagClass: tagClass, conformingTo: conformingTo ?? "public.data")
    }

    static func tags(_ record: TypeRecord, _ tagClass: String) -> [String] {
        switch tagClass {
        case TagClass.filenameExtension: return record.extensions
        case TagClass.mimeType: return record.mimeTypes
        default: return []
        }
    }
}

/// Dynamic identifiers: "dyn.a" and the declaration "?0=<conforms>:<class>=<tag>"
/// in a 32-letter alphabet, so the type can be read back from its name.
enum Dynamic {
    private static let alphabet = Array("abcdefghkmnpqrstuvwxyz0123456789")
    private static let classCodes = [TagClass.filenameExtension: "1", TagClass.mimeType: "7"]

    static func make(tag: String, tagClass: String, conformingTo: String) -> TypeRecord {
        let code = classCodes[tagClass] ?? "0"
        let identifier = "dyn.a" + encode("?0=\(conformingTo):\(code)=\(tag)")
        return TypeRecord(identifier: identifier, conformsTo: [conformingTo],
                          extensions: tagClass == TagClass.filenameExtension ? [tag] : [],
                          mimeTypes: tagClass == TagClass.mimeType ? [tag] : [], description: nil, dynamic: true)
    }

    static func decode(_ identifier: String) -> TypeRecord? {
        guard identifier.hasPrefix("dyn.a"), let text = decodeText(String(identifier.dropFirst(5))),
              text.hasPrefix("?0=") else { return nil }
        var conformsTo = "public.data", tag = "", tagClass = ""
        for part in text.dropFirst().split(separator: ":") {
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            switch pieces[0] {
            case "0": conformsTo = pieces[1]
            case "1": (tag, tagClass) = (pieces[1], TagClass.filenameExtension)
            case "7": (tag, tagClass) = (pieces[1], TagClass.mimeType)
            default: break
            }
        }
        var record = make(tag: tag, tagClass: tagClass, conformingTo: conformsTo)
        record = TypeRecord(identifier: identifier, conformsTo: record.conformsTo, extensions: record.extensions,
                            mimeTypes: record.mimeTypes, description: nil, dynamic: true)
        return record
    }

    private static func encode(_ text: String) -> String {
        var output = ""
        var buffer = 0, bits = 0
        for byte in text.utf8 {
            buffer = buffer << 8 | Int(byte)
            bits += 8
            while bits >= 5 {
                output.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 { output.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return output
    }

    private static func decodeText(_ code: String) -> String? {
        var bytes: [UInt8] = []
        var buffer = 0, bits = 0
        for character in code {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            buffer = buffer << 5 | value
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((buffer >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return String(validating: bytes, as: UTF8.self)
    }
}

/// iOS's declared types this database knows.
private let builtIn: [TypeRecord] = {
    func type(_ identifier: String, _ conformsTo: [String], _ extensions: [String] = [], _ mimeTypes: [String] = [],
              _ description: String? = nil) -> TypeRecord {
        TypeRecord(identifier: identifier, conformsTo: conformsTo, extensions: extensions, mimeTypes: mimeTypes, description: description)
    }
    return [
        type("public.item", [], [], [], "item"),
        type("public.content", ["public.item"], [], [], "content"),
        type("public.composite-content", ["public.content"], [], [], "composite content"),
        type("public.data", ["public.item"], [], [], "data"),
        type("public.directory", ["public.item"], [], [], "directory"),
        type("public.folder", ["public.directory"], [], [], "folder"),
        type("public.volume", ["public.folder"], [], [], "volume"),
        type("com.apple.package", ["public.directory"], [], [], "package"),
        type("com.apple.bundle", ["public.directory"], [], [], "bundle"),
        type("com.apple.application", ["public.data"], [], [], "application"),
        type("com.apple.application-bundle", ["com.apple.application", "com.apple.bundle", "com.apple.package"], ["app"], [],
             "application"),
        type("public.symlink", ["public.item"], [], [], "symbolic link"),
        type("com.apple.alias-file", ["public.data"], [], [], "alias"),
        type("public.url", ["public.data"], [], [], "URL"),
        type("public.file-url", ["public.url"], [], [], "file URL"),
        type("public.text", ["public.data", "public.content"], [], [], "text"),
        type("public.plain-text", ["public.text"], ["txt", "text"], ["text/plain"], "text"),
        type("public.utf8-plain-text", ["public.plain-text"], [], ["text/plain;charset=utf-8"], "Unicode text"),
        type("public.utf16-external-plain-text", ["public.plain-text"], [], [], "Unicode text"),
        type("public.utf16-plain-text", ["public.plain-text"], [], ["text/plain;charset=utf-16"], "Unicode text"),
        type("public.delimited-values-text", ["public.text"], [], [], "delimited text"),
        type("public.comma-separated-values-text", ["public.delimited-values-text"], ["csv"], ["text/csv"], "CSV document"),
        type("public.tab-separated-values-text", ["public.delimited-values-text"], ["tsv"], ["text/tab-separated-values"],
             "TSV document"),
        type("public.utf8-tab-separated-values-text", ["public.tab-separated-values-text"], [], [], "TSV document"),
        type("public.rtf", ["public.text"], ["rtf"], ["text/rtf"], "rich text document"),
        type("public.html", ["public.text"], ["html", "htm", "shtml", "shtm"], ["text/html"], "HTML text"),
        type("public.xml", ["public.text"], ["xml"], ["application/xml", "text/xml"], "XML text"),
        type("public.xhtml", ["public.xml"], ["xhtml", "xht"], ["application/xhtml+xml"], "XHTML text"),
        type("public.json", ["public.text"], ["json"], ["application/json"], "JSON"),
        type("public.yaml", ["public.text"], ["yaml", "yml"], ["application/x-yaml"], "YAML"),
        type("public.source-code", ["public.plain-text"], [], [], "source code"),
        type("public.script", ["public.source-code"], [], [], "script"),
        type("public.shell-script", ["public.script"], ["sh", "command"], ["application/x-sh"], "shell script"),
        type("public.python-script", ["public.script"], ["py"], ["text/x-python-script"], "Python script"),
        type("public.ruby-script", ["public.script"], ["rb", "rbw"], ["text/ruby-script"], "Ruby script"),
        type("com.netscape.javascript-source", ["public.source-code", "public.executable"], ["js", "jscript", "javascript"],
             ["text/javascript"], "JavaScript script"),
        type("public.c-source", ["public.source-code"], ["c"], [], "C source"),
        type("public.c-header", ["public.source-code"], ["h"], [], "C header"),
        type("public.objective-c-source", ["public.source-code"], ["m"], [], "Objective-C source"),
        type("public.c-plus-plus-source", ["public.source-code"], ["cp", "cpp", "c++", "cc", "cxx"], [], "C++ source"),
        type("public.swift-source", ["public.source-code"], ["swift"], [], "Swift source"),
        type("public.assembly-source", ["public.source-code"], ["s"], [], "assembly source"),
        type("com.apple.property-list", ["public.data"], ["plist"], [], "property list"),
        type("com.apple.xml-property-list", ["public.xml", "com.apple.property-list"], [], [], "XML property list"),
        type("com.apple.binary-property-list", ["com.apple.property-list"], [], [], "binary property list"),
        type("com.apple.log", ["public.plain-text"], ["log"], [], "log file"),
        type("public.log", ["public.plain-text"], [], [], "log file"),
        type("public.image", ["public.data", "public.content"], [], [], "image"),
        type("public.jpeg", ["public.image"], ["jpeg", "jpg", "jpe"], ["image/jpeg", "image/jpg"], "JPEG image"),
        type("public.png", ["public.image"], ["png"], ["image/png"], "PNG image"),
        type("com.compuserve.gif", ["public.image"], ["gif"], ["image/gif"], "GIF image"),
        type("public.tiff", ["public.image"], ["tiff", "tif"], ["image/tiff"], "TIFF image"),
        type("com.microsoft.bmp", ["public.image"], ["bmp", "dib"], ["image/bmp"], "Windows bitmap image"),
        type("com.microsoft.ico", ["public.image"], ["ico"], ["image/vnd.microsoft.icon"], "Windows icon image"),
        type("com.apple.icns", ["public.image"], ["icns"], [], "Apple icon image"),
        type("public.heif-standard", ["public.image"], ["heif"], ["image/heif"], "HEIF image"),
        type("public.heic", ["public.heif-standard"], ["heic"], ["image/heic"], "HEIF image"),
        type("public.heics", ["public.heif-standard"], ["heics"], ["image/heic-sequence"], "HEIF image sequence"),
        type("public.heif", ["public.heif-standard"], [], [], "HEIF image"),
        type("org.webmproject.webp", ["public.image"], ["webp"], ["image/webp"], "WebP image"),
        type("public.svg-image", ["public.image", "public.xml"], ["svg", "svgz"], ["image/svg+xml"], "SVG image"),
        type("public.camera-raw-image", ["public.image"], [], [], "raw image"),
        type("com.adobe.raw-image", ["public.camera-raw-image"], ["dng"], ["image/x-adobe-dng"], "DNG image"),
        type("com.apple.live-photo", ["public.item"], [], [], "Live Photo"),
        type("public.avif", ["public.image"], ["avif"], ["image/avif"], "AVIF image"),
        type("public.3d-content", ["public.content"], [], [], "3D content"),
        type("com.adobe.pdf", ["public.data", "public.composite-content"], ["pdf"], ["application/pdf"], "PDF document"),
        type("com.adobe.postscript", ["public.data", "public.content"], ["ps"], ["application/postscript"], "PostScript document"),
        type("public.audiovisual-content", ["public.data", "public.content"], [], [], "audiovisual content"),
        type("public.movie", ["public.audiovisual-content"], [], [], "movie"),
        type("public.video", ["public.movie"], [], [], "video"),
        type("public.audio", ["public.audiovisual-content"], [], [], "audio"),
        type("public.mpeg-4", ["public.movie"], ["mp4", "mpg4"], ["video/mp4", "video/mp4v"], "MPEG-4 movie"),
        type("com.apple.quicktime-movie", ["public.movie"], ["mov", "qt"], ["video/quicktime"], "QuickTime movie"),
        type("com.apple.m4v-video", ["public.movie"], ["m4v"], ["video/x-m4v"], "MPEG-4 video"),
        type("public.mpeg", ["public.movie"], ["mpg", "mpeg", "mpe", "m75", "m15"], ["video/mpeg", "video/mpg"], "MPEG movie"),
        type("public.mpeg-2-video", ["public.video"], ["m2v"], ["video/mpeg2"], "MPEG-2 video"),
        type("public.mpeg-2-transport-stream", ["public.movie"], ["ts"], ["video/mp2t"], "MPEG-2 transport stream"),
        type("public.avi", ["public.movie"], ["avi", "vfw"], ["video/avi", "video/msvideo", "video/x-msvideo"], "AVI movie"),
        type("public.3gpp", ["public.movie"], ["3gp", "3gpp"], ["video/3gpp", "audio/3gpp"], "3GPP movie"),
        type("public.mp3", ["public.audio"], ["mp3"], ["audio/mpeg", "audio/mpeg3", "audio/mpg", "audio/mp3", "audio/x-mp3"], "MP3 audio"),
        type("public.mpeg-4-audio", ["public.mpeg-4", "public.audio"], ["mp4", "mpg4"], ["audio/mp4"], "MPEG-4 audio"),
        type("com.apple.m4a-audio", ["public.mpeg-4-audio"], ["m4a"], ["audio/x-m4a", "audio/m4a"], "Apple MPEG-4 audio"),
        type("com.apple.protected-mpeg-4-audio", ["public.audio"], ["m4p"], ["audio/x-m4p"], "protected MPEG-4 audio"),
        type("com.microsoft.waveform-audio", ["public.audio"], ["wav", "wave"], ["audio/vnd.wave", "audio/wav", "audio/wave", "audio/x-wav"],
             "Waveform audio"),
        type("public.aiff-audio", ["public.audio"], ["aiff", "aif"], ["audio/aiff", "audio/x-aiff"], "AIFF-C audio"),
        type("com.apple.coreaudio-format", ["public.audio"], ["caf"], ["audio/x-caf"], "Apple Core Audio format"),
        type("public.midi-audio", ["public.audio"], ["midi", "mid", "smf", "kar"], ["audio/midi", "audio/x-midi"], "MIDI audio"),
        type("org.xiph.flac", ["public.audio"], ["flac"], ["audio/flac"], "FLAC audio"),
        type("public.archive", ["public.data"], [], [], "archive"),
        type("public.zip-archive", ["com.pkware.zip-archive"], ["zip"], ["application/zip"], "ZIP archive"),
        type("com.pkware.zip-archive", ["public.data", "public.archive"], [], [], "ZIP archive"),
        type("org.gnu.gnu-zip-archive", ["public.data", "public.archive"], ["gz", "gzip"], ["application/x-gzip", "application/gzip"],
             "gzip compressed archive"),
        type("public.bzip2-archive", ["public.data", "public.archive"], ["bz2", "bzip2"], ["application/x-bzip2"], "bzip2 compressed archive"),
        type("public.tar-archive", ["public.data", "public.archive"], ["tar"], ["application/x-tar", "application/tar"], "tar archive"),
        type("com.apple.disk-image", ["public.data", "public.archive"], ["dmg"], [], "disk image"),
        type("public.executable", ["public.item"], [], [], "executable"),
        type("public.unix-executable", ["public.data", "public.executable"], [], [], "Unix executable"),
        type("public.font", ["public.data", "public.content"], [], [], "font"),
        type("public.truetype-ttf-font", ["public.font"], ["ttf"], ["font/ttf"], "TrueType font"),
        type("public.opentype-font", ["public.font"], ["otf"], ["font/otf"], "OpenType font"),
        type("public.message", ["public.data", "public.content"], [], [], "message"),
        type("public.email-message", ["public.message"], [], [], "email message"),
        type("com.apple.mail.email", ["public.email-message"], ["eml"], ["message/rfc822"], "email message"),
        type("public.contact", ["public.data", "public.content"], [], [], "contact"),
        type("public.vcard", ["public.text", "public.contact"], ["vcf", "vcard"], ["text/vcard", "text/x-vcard", "text/directory"], "vCard"),
        type("public.calendar-event", ["public.data", "public.content"], [], [], "calendar event"),
        type("com.apple.ical.ics", ["public.calendar-event", "public.text"], ["ics"], ["text/calendar"], "iCalendar file"),
        type("public.to-do-item", ["public.data", "public.content"], [], [], "to-do item"),
        type("public.spreadsheet", ["public.content"], [], [], "spreadsheet"),
        type("public.presentation", ["public.composite-content"], [], [], "presentation"),
        type("public.database", ["public.data"], [], [], "database"),
        type("public.bookmark", ["public.data"], [], [], "bookmark"),
        type("public.internet-location", ["public.data"], [], [], "internet location"),
        type("com.apple.webarchive", ["public.data", "public.composite-content"], ["webarchive"], ["application/x-webarchive"],
             "web archive"),
        type("public.log", ["public.plain-text"], [], [], "log"),
        type("com.microsoft.word.doc", ["public.data", "public.composite-content"], ["doc"], ["application/msword"], "Word document"),
        type("com.microsoft.excel.xls", ["public.data", "public.composite-content", "public.spreadsheet"], ["xls"],
             ["application/vnd.ms-excel"], "Excel spreadsheet"),
        type("com.microsoft.powerpoint.ppt", ["public.data", "public.presentation"], ["ppt"], ["application/vnd.ms-powerpoint"],
             "PowerPoint presentation"),
        type("org.openxmlformats.openxml", ["public.zip-archive"], [], [], "Office Open XML document"),
        type("org.openxmlformats.wordprocessingml.document", ["org.openxmlformats.openxml", "public.composite-content"], ["docx"],
             ["application/vnd.openxmlformats-officedocument.wordprocessingml.document"], "Word document"),
        type("org.openxmlformats.spreadsheetml.sheet", ["org.openxmlformats.openxml", "public.spreadsheet"], ["xlsx"],
             ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"], "Excel spreadsheet"),
        type("org.openxmlformats.presentationml.presentation", ["org.openxmlformats.openxml", "public.presentation"], ["pptx"],
             ["application/vnd.openxmlformats-officedocument.presentationml.presentation"], "PowerPoint presentation"),
        type("com.apple.keynote.key", ["com.apple.package", "public.presentation"], ["key"], [], "Keynote presentation"),
        type("com.apple.pages.pages", ["com.apple.package", "public.composite-content"], ["pages"], [], "Pages document"),
        type("com.apple.numbers.numbers", ["com.apple.package", "public.spreadsheet"], ["numbers"], [], "Numbers spreadsheet"),
        type("com.apple.pkpass", ["public.data", "public.content"], ["pkpass"], ["application/vnd.apple.pkpass"], "Wallet pass"),
        type("com.apple.reality", ["public.data", "public.3d-content"], ["reality"], [], "Reality file"),
        type("com.pixar.universal-scene-description-mobile", ["public.zip-archive", "public.3d-content"], ["usdz"],
             ["model/vnd.usdz+zip"], "USDZ file"),
        type("public.x509-certificate", ["public.data"], ["cer", "crt", "der"], ["application/x-x509-ca-cert"], "certificate"),
        type("com.rsa.pkcs-12", ["public.data"], ["p12", "pfx"], ["application/x-pkcs12"], "personal information exchange"),
        type("public.geojson", ["public.json"], ["geojson"], ["application/geo+json"], "GeoJSON"),
        type("com.apple.ink.inktext", ["public.data"], [], [], "Ink text"),
        type("com.apple.flat-rtfd", ["public.data", "public.composite-content"], ["rtfd"], [], "rich text document with attachments"),
        type("com.apple.rtfd", ["com.apple.package", "public.composite-content"], ["rtfd"], [], "rich text document with attachments"),
        type("com.apple.txn.text-multimedia-data", ["public.data", "public.composite-content"], [], [], "text with multimedia"),
        type("org.idpf.epub-container", ["public.data", "public.composite-content"], ["epub"], ["application/epub+zip"], "EPUB document"),
        type("public.object-code", ["public.data"], ["o"], [], "object code"),
        type("com.apple.mach-o-binary", ["public.data", "public.executable"], [], [], "Mach-O binary"),
        type("com.apple.framework", ["com.apple.bundle"], ["framework"], [], "framework"),
        type("com.apple.plugin", ["com.apple.bundle", "com.apple.package"], ["plugin"], [], "plug-in"),
        type("com.apple.application-and-system-extension", ["com.apple.bundle"], ["appex"], [], "app extension"),
        type("com.apple.dylib", ["public.data", "public.executable"], ["dylib"], [], "dynamic library"),
    ]
}()
