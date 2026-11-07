import FoundationEssentials
import Glibc
import PerryObjCInterop

// The app as the desktop knows it: a desktop entry named by its bundle
// identifier, in the user's applications ($XDG_DATA_HOME/applications, else
// ~/.local/share/applications), with the app's name and icon, launching it
// through Perry as it runs now. The window's Wayland app ID (SDL_APP_ID) is
// the same identifier, so GNOME shows the window under the entry's name and
// icon, and its location agent, asked through GeoClue for the app (Perry's
// CoreLocation), finds the entry and asks the user, with the app's location
// usage description as the reason.
//
// The entry is written when the window first opens, and rewritten only
// when it would change. PERRY_DESKTOP_ENTRY=0 writes none.

enum DesktopEntry {
    /// The app's desktop ID: its bundle identifier, keeping the characters a
    /// desktop file's name may have; nil without one.
    static let id: String? = {
        guard let identifier = NSBundle.main().infoObject(forKey: "CFBundleIdentifier")?.stringValue else { return nil }
        let kept = String(identifier.map { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) ? $0 : "_" })
        return kept.isEmpty ? nil : kept
    }()

    /// Writes the entry and its icon, if the app has an identifier.
    static func install() {
        if let setting = getenv("PERRY_DESKTOP_ENTRY"), String(cString: setting) == "0" { return }
        guard let id, let data = dataHome else { return }
        let applications = data + "/applications"
        let icons = data + "/icons/hicolor/256x256/apps"
        let icon = writeIcon(to: icons + "/" + id + ".png")
        var lines = ["[Desktop Entry]", "Type=Application", "Name=" + escaped(name)]
        if let exec = exec { lines.append("Exec=" + exec) }
        if let icon { lines.append("Icon=" + escaped(icon)) }
        lines.append("StartupWMClass=" + id)
        lines.append("Terminal=false")
        if let reason = locationReason { lines.append("X-Geoclue-Reason=" + escaped(reason)) }
        if let bundle = bundlePath { lines.append("X-Perry-Bundle=" + escaped(bundle)) }
        let contents = lines.joined(separator: "\n") + "\n"
        let path = applications + "/" + id + ".desktop"
        if let existing = FileManager.default.contents(atPath: path), existing == Data(contents.utf8) { return }
        try? FileManager.default.createDirectory(atPath: applications, withIntermediateDirectories: true)
        if !FileManager.default.createFile(atPath: path, contents: Data(contents.utf8)) {
            uikitWarning("could not write the app's desktop entry \(path)")
        }
    }

    // MARK: What the entry says

    /// $XDG_DATA_HOME, else the user's ~/.local/share: the real home, not
    /// the app's container.
    private static var dataHome: String? {
        if let data = getenv("XDG_DATA_HOME").map({ String(cString: $0) }), data.hasPrefix("/") { return data }
        guard let user = getpwuid(getuid()), let home = user.pointee.pw_dir else { return nil }
        return String(cString: home) + "/.local/share"
    }

    /// The name the home screen shows.
    private static var name: String {
        NSBundle.main().infoObject(forKey: "CFBundleDisplayName")?.stringValue
            ?? NSBundle.main().infoObject(forKey: "CFBundleName")?.stringValue ?? id ?? "App"
    }

    /// Why the app wants the location, localized: what GNOME's prompt says.
    private static var locationReason: String? {
        for key in ["NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription", "NSLocationUsageDescription"] {
            if let reason = NSBundle.main().infoObject(forKey: key)?.stringValue, !reason.isEmpty { return reason }
        }
        return nil
    }

    private static var bundlePath: String? { NSBundle.main().bundlePath() }

    /// Perry, run on the bundle, with the environment it runs with now that
    /// says where its libraries and the app's data are: the library path
    /// and the PERRY_ settings other than debugging switches.
    private static var exec: String? {
        guard let bundle = bundlePath, let perry = executable else { return nil }
        let debugging = ["TRACE", "SNAPSHOT", "TAPS", "CLICKS", "TYPE", "CRASH", "ZOMBIES", "UNRECOGNIZED", "UNIMPLEMENTED",
                         "KEEP_CRASH", "DESKTOP_ENTRY"]
        var settings: [String] = []
        var entry = environ
        while let pointer = entry.pointee {
            let setting = String(cString: pointer)
            let name = setting.prefix { $0 != "=" }
            if name == "LD_LIBRARY_PATH" || (name.hasPrefix("PERRY_") && !debugging.contains { name.contains($0) }) {
                settings.append(setting)
            }
            entry += 1
        }
        let arguments = (settings.isEmpty ? [] : ["env"] + settings.sorted()) + [perry, bundle]
        return arguments.map(quoted).joined(separator: " ")
    }

    /// The program running: Perry's loader.
    private static var executable: String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let length = readlink("/proc/self/exe", &buffer, Int(PATH_MAX))
        guard length > 0 else { return nil }
        return String(decoding: buffer[..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The app's icon, the largest of its icon files or its asset catalog's
    /// AppIcon, written as a PNG; its path, or nil without one.
    private static func writeIcon(to path: String) -> String? {
        var names: [String] = []
        if let icons = NSBundle.main().infoObject(forKey: "CFBundleIcons")?.as(NSDictionary.self),
           let primary = icons.object(forKey: "CFBundlePrimaryIcon")?.as(NSDictionary.self) {
            if let files = primary.object(forKey: "CFBundleIconFiles")?.as(NSArray.self) {
                names += files.elements.reversed().compactMap(\.stringValue)
            }
            if let name = primary.object(forKey: "CFBundleIconName")?.stringValue { names.append(name) }
        }
        if let files = NSBundle.main().infoObject(forKey: "CFBundleIconFiles")?.as(NSArray.self) {
            names += files.elements.reversed().compactMap(\.stringValue)
        }
        names += ["AppIcon", "AppIcon60x60", "Icon"]
        for name in names {
            guard let image = UIImage.image(UIImage.objCClass, named: name), let cgImage = image.state.cgImage,
                  let png = UIImage.encode(cgImage, type: "public.png") else { continue }
            let directory = String(path[..<(path.lastIndex(of: "/") ?? path.endIndex)])
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            return png.sendWrite(toFile: path, atomically: true) ? path : nil
        }
        return nil
    }

    // MARK: Desktop entry syntax

    /// A string value: backslashes, newlines and tabs escaped.
    private static func escaped(_ value: String) -> String {
        var result = ""
        for character in value {
            switch character {
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            default: result.append(character)
            }
        }
        return result
    }

    /// An Exec argument: quoted when it must be, with `"`, `` ` ``, `$` and
    /// `\` escaped inside quotes, and `%` doubled, then escaped as a string.
    private static func quoted(_ argument: String) -> String {
        let plain = argument.allSatisfy { $0.isLetter || $0.isNumber || "/._-+=:,@".contains($0) }
        let percent = argument.map { $0 == "%" ? "%%" : String($0) }.joined()
        if plain { return escaped(percent) }
        var inner = ""
        for character in percent {
            if "\"`$\\".contains(character) { inner.append("\\") }
            inner.append(character)
        }
        return escaped("\"" + inner + "\"")
    }
}
