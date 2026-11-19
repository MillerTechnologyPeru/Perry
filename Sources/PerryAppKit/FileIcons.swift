import CPerryGeometry
import Glibc

/// Icons for files, from the desktop's icon theme as freedesktop.org's
/// specifications have them found: a file's MIME type from shared-mime-info's
/// glob patterns, its icon named for the type with "/" as "-", then the
/// type's generic icon, then its media's.
enum FileIcons {
    static let themes = ["Adwaita", "hicolor"]
    static let sizes = ["32x32", "48x48", "24x24", "16x16", "64x64", "256x256"]
    static let contexts = ["mimetypes", "places", "apps", "devices"]

    /// Extension (lowercased) → MIME type, and exact names → MIME type.
    nonisolated(unsafe) static var extensions: [String: String]?
    nonisolated(unsafe) static var generic: [String: String]?
    nonisolated(unsafe) static var images: [String: NSImage] = [:]

    static func lines(_ path: String) -> [Substring] {
        guard let file = fopen(path, "r") else { return [] }
        defer { fclose(file) }
        var text: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = fread(&buffer, 1, buffer.count, file)
            if count <= 0 { break }
            text.append(contentsOf: buffer[0..<count])
        }
        return String(decoding: text, as: UTF8.self).split(separator: "\n")
    }

    /// globs2's lines are weight:type:pattern, heaviest first; the first
    /// type for an extension wins.
    static func loadDatabase() {
        guard extensions == nil else { return }
        var table: [String: String] = [:]
        for line in lines("/usr/share/mime/globs2") where !line.hasPrefix("#") {
            let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, parts[2].hasPrefix("*.") else { continue }
            let suffix = parts[2].dropFirst(2)
            guard !suffix.contains(where: { "*?[".contains($0) }) else { continue }
            let key = suffix.lowercased()
            if table[key] == nil { table[key] = String(parts[1]) }
        }
        // Mac types the database doesn't know, or knows otherwise.
        let mac = ["m": "text/x-objcsrc", "mm": "text/x-objc++src", "pch": "text/x-chdr", "xib": "application/xml",
                   "nib": "application/xml", "strings": "text/plain", "plist": "application/xml",
                   "xcodeproj": "application/x-xcode-project", "pbxproj": "text/plain", "app": "application/x-executable",
                   "framework": "inode/directory", "dylib": "application/x-sharedlib", "a": "application/x-archive"]
        for (key, type) in mac { table[key] = type }
        extensions = table
        var generics: [String: String] = [:]
        for line in lines("/usr/share/mime/generic-icons") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 { generics[String(parts[0])] = String(parts[1]) }
        }
        generic = generics
    }

    static func exists(_ path: String) -> Bool { access(path, R_OK) == 0 }

    /// The PNG for an icon name, the first size and theme that has it.
    static func file(named name: String) -> String? {
        for theme in themes {
            for size in sizes {
                for context in contexts {
                    let path = "/usr/share/icons/\(theme)/\(size)/\(context)/\(name).png"
                    if exists(path) { return path }
                }
            }
        }
        return nil
    }

    /// Icon names to try for a MIME type, most specific first.
    static func names(for type: String) -> [String] {
        loadDatabase()
        var names = [String(type.map { $0 == "/" ? "-" : $0 })]
        if let generic = generic?[type] { names.append(generic) }
        let media = type.split(separator: "/").first.map(String.init) ?? ""
        switch media {
        case "text": names.append(type.contains("src") || type.contains("hdr") ? "text-x-script" : "text-x-generic")
            names.append("text-x-generic")
        case "image", "audio", "video", "font": names.append("\(media)-x-generic")
        case "inode": names.append(type == "inode/directory" ? "folder" : "text-x-generic")
        default: break
        }
        if type.hasSuffix("xml") { names.append("text-x-generic") }
        names.append("application-x-generic")
        return names
    }

    static func mimeType(forExtension ext: String) -> String? {
        loadDatabase()
        return extensions?[ext.lowercased()]
    }

    /// An icon for a MIME type, 32 points square as AppKit's are; one
    /// image for each type, which callers may resize, as AppKit's
    /// icons are new each time: so a copy.
    static func icon(forMIMEType type: String) -> NSImage {
        if let image = images[type] { return copy(image) }
        let path = names(for: type).lazy.compactMap { file(named: $0) }.first
        let image = path.map { NSImage(contentsOfFile: $0) } ?? NSImage(size: CGSize(width: 32, height: 32))
        image.setSize(CGSize(width: 32, height: 32))
        images[type] = image
        return copy(image)
    }

    static func copy(_ image: NSImage) -> NSImage {
        let copy = image.path.map { NSImage(contentsOfFile: $0) } ?? NSImage(size: image.size)
        copy.setSize(image.size)
        return copy
    }

    /// A file's type: folders (packages by their extension), then by
    /// extension, then executables.
    static func type(ofFile path: String) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let ext = name.contains(".") ? String(name.split(separator: ".").last ?? "") : ""
        var info = stat()
        let found = stat(path, &info) == 0
        let directory = found && (info.st_mode & S_IFMT) == S_IFDIR
        if directory {
            if !ext.isEmpty, let type = mimeType(forExtension: ext), type != "inode/directory" { return type }
            return "inode/directory"
        }
        if let type = mimeType(forExtension: ext) { return type }
        if found, info.st_mode & 0o111 != 0 { return "application/x-executable" }
        return "text/plain"
    }

    /// A type as NSWorkspace takes it: an extension, a UTI, or an HFS type
    /// ('fold' and the like, quoted).
    static func type(forFileType fileType: String) -> String {
        switch fileType {
        case "'fldr'", "'fold'", "public.folder", "public.directory": return "inode/directory"
        case "'APPL'", "com.apple.application-bundle", "com.apple.application", "public.executable": return "application/x-executable"
        case "public.plain-text", "public.text": return "text/plain"
        case "public.image": return "image/png"
        default: break
        }
        if fileType.hasPrefix("public.") || fileType.hasPrefix("com.") {
            if fileType.contains("source") || fileType.contains("header") { return "text/x-csrc" }
            return "application/octet-stream"
        }
        return mimeType(forExtension: fileType) ?? "application/octet-stream"
    }
}
