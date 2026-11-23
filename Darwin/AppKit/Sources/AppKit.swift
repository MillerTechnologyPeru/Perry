// AppKit's Swift API that apps call as Swift: Perry's own, built over the
// SDK's AppKit headers into libswiftAppKit.dylib, which the loader looks
// in for AppKit's Swift symbols.

import Foundation

/// The Objective-C NSApplicationMain, which this module's Swift one of the
/// same name hides.
@_silgen_name("NSApplicationMain")
private func objectiveCApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

/// What @main on an NSApplicationDelegate, and a main.swift that calls it,
/// starts the app with.
@available(macOS 10.9, *)
public func NSApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32 {
    objectiveCApplicationMain(argc, argv)
}

extension NSApplicationDelegate {
    @_alwaysEmitIntoClient
    public static func main() {
        exit(NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv))
    }
}

extension NSApplication {
    /// Sets up Cocoa for a bundle loaded into a program that isn't a Cocoa
    /// application.
    @available(macOS 10.9, *)
    @MainActor @preconcurrency
    public static func loadApplication() {
        _ = __NSApplicationLoad()
    }
}

extension NSSound {
    @available(macOS 10.9, *)
    public static func beep() {
        __NSBeep()
    }
}

extension IndexPath {
    /// An index path of a collection view's item: its section, then its item.
    public init(item: Int, section: Int) {
        self.init(indexes: [section, item])
    }

    public var item: Int {
        get { self[1] }
        set { self[1] = newValue }
    }

    public var section: Int {
        get { self[0] }
        set { self[0] = newValue }
    }
}

extension URLResourceValues {
    @available(macOS, introduced: 10.10, deprecated: 12.0, message: "Use the QuickLookThumbnailing framework and extension point instead")
    public var thumbnail: NSImage? { allValues[.thumbnailKey] as? NSImage }

    /// The color of the file's label.
    public var labelColor: NSColor? { allValues[.labelColorKey] as? NSColor }

    /// The icon the file shows: its custom icon, else its type's.
    public var effectiveIcon: AnyObject? { allValues[.effectiveIconKey] as AnyObject? }

    /// The file's custom icon, if it has one.
    public var customIcon: NSImage? { allValues[.customIconKey] as? NSImage }

    @available(macOS, introduced: 10.10, deprecated: 12.0, message: "Use the QuickLookThumbnailing framework and extension point instead")
    public var thumbnailDictionary: [URLThumbnailDictionaryItem: NSImage]? {
        allValues[.thumbnailDictionaryKey] as? [URLThumbnailDictionaryItem: NSImage]
    }
}

extension NSGradient {
    /// A gradient of colors, each at its location from 0 to 1.
    public convenience init?(colorsAndLocations objects: (NSColor, CGFloat)...) {
        let locations = objects.map(\.1)
        self.init(colors: objects.map(\.0), atLocations: locations, colorSpace: .genericRGB)
    }
}

@available(macOS 14.0, *)
extension NSMenuItem {
    @available(*, deprecated, renamed: "sectionHeader(title:)", message: "Use sectionHeader(title:) instead.")
    public static func sectionHeader(withTitle title: String) -> NSMenuItem {
        sectionHeader(title: title)
    }

    public static func sectionHeader(title: String) -> NSMenuItem {
        NSMenuItem.__sectionHeader(withTitle: title)
    }
}

@available(macOS 14.0, *)
extension NSMenu {
    /// A palette of colors to pick from, titled, drawn with a template
    /// image when one is given.
    public static func palette(colors: [NSColor], titles: [String] = [], template: NSImage? = nil,
                               onSelectionChange: ((NSMenu) -> Void)? = nil) -> NSMenu {
        if let template {
            return NSMenu.__paletteMenu(with: colors, titles: titles, templateImage: template,
                                        selectionHandler: onSelectionChange)
        }
        return NSMenu.__paletteMenu(with: colors, titles: titles, selectionHandler: onSelectionChange)
    }
}
