import CPerryGeometry
import Glibc

// Nibs from before keyed archives: an NSIBObjectData and the objects under
// it, archived by NSArchiver into a typedstream ("objects.nib"). Each class
// wrote its values in order, superclass first, without keys. This turns
// such a nib into the keyed form a nib's objects are instantiated from,
// class by class, as Mac OS X 10.2's AppKit decoded it: views, controls
// and their cells, windows, menus, tables, scroll views, fonts, colors,
// custom objects and views, connections. Values a class wrote that nothing
// here uses are passed over.

enum LegacyNib {
    /// The nib's objects in keyed form, or nil if it isn't a typedstream.
    static func objects(_ bytes: [UInt8]) -> [NibArchive.Object]? {
        guard let values = TypedStream.values(bytes), let data = values.first?.object,
              data.className == "NSIBObjectData" else { return nil }
        let translation = Translation()
        let root = translation.reserve()
        let dataIndex = translation.translate(data)
        translation.fill(root, "NSObject", [("IB.objectdata", .object(dataIndex))])
        return translation.objects()
    }
}

private final class Translation {
    typealias Entry = (key: String, value: NibArchive.Value)

    var described: [(className: String, fallbacks: [String], entries: [Entry])] = []
    var indices: [ObjectIdentifier: Int] = [:]

    func reserve() -> Int {
        described.append(("NSNull", [], []))
        return described.count - 1
    }

    func fill(_ index: Int, _ className: String, _ entries: [Entry], fallbacks: [String] = []) {
        described[index] = (className, fallbacks, entries)
    }

    func add(_ className: String, _ entries: [Entry]) -> Int {
        described.append((className, [], entries))
        return described.count - 1
    }

    func objects() -> [NibArchive.Object] {
        var values: [Entry] = []
        var ranges: [Range<Int>] = []
        for item in described {
            ranges.append(values.count..<values.count + item.entries.count)
            values += item.entries
        }
        return zip(described, ranges).map { NibArchive.Object(className: $0.className, fallbacks: $0.fallbacks, values: values[$1]) }
    }

    // MARK: Values

    func string(_ text: String) -> NibArchive.Value { .object(add("NSString", [("NS.bytes", .data(Array(text.utf8)))])) }

    func array(_ items: [NibArchive.Value], className: String = "NSMutableArray") -> NibArchive.Value {
        .object(add(className, items.map { ("UINibEncoderEmptyKey", $0) }))
    }

    /// A value as a keyed one: objects by their entry, strings as strings.
    func reference(_ value: TypedStream.Value?) -> NibArchive.Value {
        switch value {
        case .object(let object?)?: return .object(translate(object))
        case .string(let text?)?: return string(text)
        case .bytes(let raw)?: return string(String(decoding: raw, as: UTF8.self))
        case .integer(let number)?: return .integer(number)
        case .real(let number)?: return .double(number)
        default: return .null
        }
    }

    /// Points, sizes and rects, as a keyed nib's packed doubles.
    static func doubles(_ values: [Double]) -> NibArchive.Value {
        var bytes: [UInt8] = [7]
        for value in values { withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes += $0 } }
        return .data(bytes)
    }

    /// The object's entry, made the first time it is met. Its index is
    /// taken before its values are read, as they may lead back to it.
    func translate(_ object: TypedStream.Object) -> Int {
        if let index = indices[ObjectIdentifier(object)] { return index }
        let index = reserve()
        indices[ObjectIdentifier(object)] = index
        var reader = ValueReader(values: object.values[...])
        var entries: [Entry] = []
        var className = object.className
        var chain = object.classes.map(\.name).reversed().map { $0 }
        // A class Interface Builder swapped in: its name and the class it
        // stands for, then that class's values.
        if object.className == "NSClassSwapper" {
            let name = reader.next()
            let original: String? = { if case .objectClass(let original)? = reader.next() { return original } else { return nil } }()
            entries.append(("NSClassName", reference(name)))
            if let original { entries.append(("NSOriginalClassName", string(original))) }
            chain = LegacyClasses.chain(original ?? "NSObject")
            className = "NSClassSwapper"
        }
        for level in chain {
            guard let decode = LegacyClasses.levels[level] else {
                if !LegacyClasses.empty.contains(level) {
                    Trace.log("nib: typedstream class \(level) of \(object.className) is not known; its values are passed over")
                    break
                }
                continue
            }
            decode(&reader, &entries, self, &className)
        }
        fill(index, className, entries)
        return index
    }
}

/// An object's values, read in order.
private struct ValueReader {
    var values: ArraySlice<TypedStream.Value>

    mutating func next() -> TypedStream.Value? { values.popFirst() }
    mutating func integer() -> Int64 { next()?.integer ?? 0 }
    mutating func real() -> Double { next()?.real ?? 0 }
    mutating func skip(_ count: Int) { values = values.dropFirst(count) }
    mutating func rest() -> [TypedStream.Value] {
        defer { values = values.suffix(0) }
        return Array(values)
    }
    var isEmpty: Bool { values.isEmpty }
}

private typealias Level = (inout ValueReader, inout [Translation.Entry], Translation, inout String) -> Void

private enum LegacyClasses {
    /// Classes that wrote nothing of their own.
    static let empty: Set<String> = [
        "NSObject", "NSButton", "NSPopUpButton", "NSSecureTextField", "NSSecureTextFieldCell", "NSTableHeaderCell",
        "NSOutlineView", "_NSCornerView", "NSComboTableView", "NSValue", "NSNibOutletConnector", "NSNibControlConnector",
        "NSBrowserCell", "NSArray", "NSSet", "NSMutableString",
    ]

    /// A standard class's superclasses, for a class swapper's original.
    static let superclasses: [String: String] = [
        "NSResponder": "NSObject", "NSView": "NSResponder", "NSControl": "NSView", "NSButton": "NSControl",
        "NSPopUpButton": "NSButton", "NSTextField": "NSControl", "NSSecureTextField": "NSTextField", "NSComboBox": "NSTextField",
        "NSImageView": "NSControl", "NSMatrix": "NSControl", "NSScroller": "NSControl", "NSTableView": "NSControl",
        "NSOutlineView": "NSTableView", "NSBrowser": "NSControl", "NSBox": "NSView", "NSClipView": "NSView",
        "NSScrollView": "NSView", "NSSplitView": "NSView", "NSTabView": "NSView", "NSTableHeaderView": "NSView",
        "NSCustomView": "NSView", "NSSlider": "NSControl", "NSProgressIndicator": "NSView", "NSColorWell": "NSControl",
        "NSForm": "NSMatrix", "NSStepper": "NSControl", "NSTextView": "NSText", "NSText": "NSView",
    ]

    /// The class and its superclasses, root first.
    static func chain(_ name: String) -> [String] {
        var chain = [name]
        while let superclass = superclasses[chain[0]] { chain.insert(superclass, at: 0) }
        if chain.first != "NSObject" { chain.insert("NSObject", at: 0) }
        return chain
    }

    nonisolated(unsafe) static let levels: [String: Level] = [
        // MARK: The nib's own objects
        "NSIBObjectData": { reader, entries, t, _ in
            entries.append(("NSRoot", t.reference(reader.next())))
            var children: [NibArchive.Value] = [], parents: [NibArchive.Value] = []
            for _ in 0..<max(0, reader.integer()) {
                children.append(t.reference(reader.next()))
                parents.append(t.reference(reader.next()))
            }
            entries.append(("NSObjectsKeys", t.array(children)))
            entries.append(("NSObjectsValues", t.array(parents)))
            var named: [NibArchive.Value] = [], names: [NibArchive.Value] = []
            for _ in 0..<max(0, reader.integer()) {
                named.append(t.reference(reader.next()))
                names.append(t.reference(reader.next()))
            }
            entries.append(("NSNamesKeys", t.array(named)))
            entries.append(("NSNamesValues", t.array(names)))
            entries.append(("NSVisibleWindows", t.reference(reader.next())))
            entries.append(("NSConnections", t.reference(reader.next())))
            reader.skip(1)   // the font manager
            for _ in 0..<max(0, reader.integer()) { reader.skip(2) }   // object IDs
            reader.skip(1)   // the next ID
            for _ in 0..<max(0, reader.integer()) { reader.skip(2) }   // class names
            if let framework = reader.next() { entries.append(("NSFramework", t.reference(framework))) }
        },
        "NSCustomObject": { reader, entries, t, _ in
            entries.append(("NSClassName", t.reference(reader.next())))
            reader.skip(1)
        },
        "NSCustomResource": { reader, entries, t, _ in
            entries.append(("NSClassName", t.reference(reader.next())))
            entries.append(("NSResourceName", t.reference(reader.next())))
        },
        "NSButtonImageSource": { reader, entries, t, _ in
            entries.append(("NSImageName", t.reference(reader.next())))
        },
        "NSNibConnector": { reader, entries, t, _ in
            entries.append(("NSSource", t.reference(reader.next())))
            entries.append(("NSDestination", t.reference(reader.next())))
            entries.append(("NSLabel", t.reference(reader.next())))
        },
        "NSIBHelpConnector": { reader, entries, t, _ in
            entries.append(("NSDestination", t.reference(reader.next())))
            entries.append(("NSMarker", t.reference(reader.next())))
            entries.append(("NSFile", t.reference(reader.next())))
        },

        // MARK: Foundation's
        "NSString": { reader, entries, _, _ in
            if case .bytes(let raw)? = reader.next() { entries.append(("NS.bytes", .data(raw))) }
        },
        "NSMutableArray": { reader, entries, t, _ in
            for _ in 0..<max(0, reader.integer()) { entries.append(("UINibEncoderEmptyKey", t.reference(reader.next()))) }
        },
        "NSMutableSet": { reader, entries, t, _ in
            for _ in 0..<max(0, reader.integer()) { entries.append(("UINibEncoderEmptyKey", t.reference(reader.next()))) }
        },
        "NSNumber": { reader, entries, _, _ in
            let type: String? = { if case .string(let type)? = reader.next() { return type } else { return nil } }()
            let value = reader.next()
            if type == "f" || type == "d", let real = value?.real {
                entries.append(("NS.dblval", .double(real)))
            } else {
                entries.append(("NS.intval", .integer(value?.integer ?? 0)))
            }
        },

        // MARK: Fonts, colors, images
        "NSFont": { reader, entries, t, _ in
            reader.skip(1)   // the name's length
            var name = ".AppleSystemUIFont"
            if case .bytes(let raw)? = reader.next() {
                // A UTF-16 name after its byte order mark, or plain bytes.
                if let mark = raw.indices.dropLast().first(where: { raw[$0] == 0xfe && raw[$0 + 1] == 0xff }) {
                    let units = stride(from: mark + 2, to: raw.count - 1, by: 2).map { UInt16(raw[$0]) << 8 | UInt16(raw[$0 + 1]) }
                    name = String(decoding: units.prefix { $0 != 0 }, as: UTF16.self)
                } else {
                    name = String(decoding: raw.drop { $0 < 0x20 }.prefix { $0 != 0 }, as: UTF8.self)
                }
            }
            entries.append(("NSName", t.string(name)))
            entries.append(("NSSize", .double(reader.real())))
            reader.skip(4)
        },
        "NSColor": { reader, entries, t, _ in
            let space = reader.integer()
            func numbers(_ count: Int) -> NibArchive.Value {
                let text = (0..<count).map { _ in String(reader.real()) }.joined(separator: " ")
                return .data(Array(text.utf8) + [0])
            }
            switch space {
            case 1, 2:
                entries.append(("NSColorSpace", .integer(space)))
                entries.append(("NSRGB", numbers(4)))
            case 3, 4:
                entries.append(("NSColorSpace", .integer(space)))
                entries.append(("NSWhite", numbers(2)))
            case 6:
                entries.append(("NSColorSpace", .integer(6)))
                entries.append(("NSCatalogName", t.reference(reader.next())))
                entries.append(("NSColorName", t.reference(reader.next())))
                entries.append(("NSColor", t.reference(reader.next())))
            default:
                _ = reader.rest()
            }
        },
        "NSImage": { reader, _, _, className in
            _ = reader.rest()
            className = "NSNull"
        },
        "NSImageRep": { reader, _, _, className in
            _ = reader.rest()
            className = "NSNull"
        },
        "NSBitmapImageRep": { reader, _, _, _ in _ = reader.rest() },
        "NSCursor": { reader, _, _, className in
            _ = reader.rest()
            className = "NSNull"
        },

        // MARK: Windows and menus
        "NSWindowTemplate": { reader, entries, t, _ in
            entries.append(("NSWindowStyleMask", .integer(reader.integer())))
            entries.append(("NSWindowBacking", .integer(reader.integer())))
            entries.append(("NSWindowRect", Translation.doubles((0..<4).map { _ in reader.real() })))
            entries.append(("NSWTFlags", .integer(reader.integer())))
            entries.append(("NSWindowTitle", t.reference(reader.next())))
            entries.append(("NSWindowClass", t.reference(reader.next())))
            entries.append(("NSViewClass", t.reference(reader.next())))
            entries.append(("NSWindowView", t.reference(reader.next())))
            reader.skip(2)
            entries.append(("NSScreenRect", Translation.doubles((0..<4).map { _ in reader.real() })))
            reader.skip(1)
            entries.append(("NSMinSize", Translation.doubles([reader.real(), reader.real()])))
            if case .object(let name?)? = reader.next(), name.className.hasSuffix("String") {
                entries.append(("NSFrameAutosaveName", t.reference(.object(name))))
            }
            reader.skip(1)
            if !reader.isEmpty { entries.append(("NSMaxSize", Translation.doubles([reader.real(), reader.real()]))) }
        },
        "NSMenu": { reader, entries, t, _ in
            reader.skip(1)
            entries.append(("NSTitle", t.reference(reader.next())))
            entries.append(("NSMenuItems", t.reference(reader.next())))
            if case .object(let name?)? = reader.next() { entries.append(("NSName", t.reference(.object(name)))) }
        },
        "NSMenuItem": { reader, entries, t, _ in
            entries.append(("NSMenu", t.reference(reader.next())))
            let flags = UInt32(truncatingIfNeeded: reader.integer())
            entries.append(("NSIsDisabled", .bool(flags & 0x8000_0000 != 0)))
            entries.append(("NSIsSeparator", .bool(flags & 0x4000_0000 != 0)))
            entries.append(("NSTitle", t.reference(reader.next())))
            entries.append(("NSKeyEquiv", t.reference(reader.next())))
            entries.append(("NSKeyEquivModMask", .integer(reader.integer())))
            entries.append(("NSMnemonicLoc", .integer(reader.integer())))
            entries.append(("NSState", .integer(reader.integer())))
            entries.append(("NSImage", t.reference(reader.next())))
            entries.append(("NSOnImage", t.reference(reader.next())))
            reader.skip(1)   // the off-state image
            entries.append(("NSMixedImage", t.reference(reader.next())))
            entries.append(("NSAction", t.reference(reader.next())))
            entries.append(("NSTag", .integer(reader.integer())))
            entries.append(("NSRepObject", t.reference(reader.next())))
            entries.append(("NSTarget", t.reference(reader.next())))
            entries.append(("NSSubmenu", t.reference(reader.next())))
        },

        // MARK: Views
        "NSResponder": { reader, _, _, _ in reader.skip(1) },
        "NSView": { reader, entries, t, _ in
            // The flags: the autoresizing mask in bits 24-29, autoresizing
            // subviews in bit 23.
            let old = UInt32(truncatingIfNeeded: reader.integer())
            var flags = Int64(old >> 24 & 0x3f)
            if old & 0x80_0000 != 0 { flags |= 0x100 }
            entries.append(("NSvFlags", .integer(flags)))
            entries.append(("NSSubviews", t.reference(reader.next())))
            reader.skip(3)
            entries.append(("NSFrame", Translation.doubles((0..<4).map { _ in reader.real() })))
            reader.skip(4)   // the bounds
            entries.append(("NSSuperview", t.reference(reader.next())))
            reader.skip(1)
            entries.append(("NSNextKeyView", t.reference(reader.next())))
            reader.skip(1)
        },
        "NSCustomView": { reader, entries, t, _ in
            entries.append(("NSClassName", t.reference(reader.next())))
            reader.skip(1)
        },
        "NSControl": { reader, entries, t, _ in
            entries.append(("NSTag", .integer(reader.integer())))
            entries.append(("NSEnabled", .bool(reader.integer() != 0)))
            reader.skip(1)
            entries.append(("NSCell", t.reference(reader.next())))
        },
        "NSTextField": { reader, entries, t, _ in
            entries.append(("NSDelegate", t.reference(reader.next())))
            reader.skip(1)
        },
        "NSComboBox": { reader, _, _, _ in _ = reader.rest() },
        "NSImageView": { reader, entries, _, _ in entries.append(("NSEditable", .bool(reader.integer() != 0))) },
        "NSMatrix": { reader, entries, t, _ in
            if case .objectClass(let name?)? = reader.next() { entries.append(("NSCellClass", t.string(name))) }
            reader.skip(2)
            entries.append(("NSNumRows", .integer(reader.integer())))
            entries.append(("NSNumCols", .integer(reader.integer())))
            reader.skip(1)   // the action, which the matrix's cell has
            entries.append(("NSDoubleAction", t.reference(reader.next())))
            reader.skip(1)
            entries.append(("NSCellSize", Translation.doubles([reader.real(), reader.real()])))
            entries.append(("NSIntercellSpacing", Translation.doubles([reader.real(), reader.real()])))
            entries.append(("NSMatrixFlags", .integer(reader.integer())))
            entries.append(("NSCells", t.reference(reader.next())))
            entries.append(("NSBackgroundColor", t.reference(reader.next())))
            entries.append(("NSCellBackgroundColor", t.reference(reader.next())))
            reader.skip(1)   // the font
            entries.append(("NSProtoCell", t.reference(reader.next())))
            reader.skip(2)
            entries.append(("NSSelectedCell", t.reference(reader.next())))
        },
        "NSScroller": { reader, _, _, _ in _ = reader.rest() },
        "NSClipView": { reader, entries, t, _ in
            entries.append(("NSDocView", t.reference(reader.next())))
            entries.append(("NSBGColor", t.reference(reader.next())))
            reader.skip(3)
            entries.append(("NScvFlags", .integer(reader.integer() != 0 ? 4 : 0)))
        },
        "NSScrollView": { reader, entries, t, _ in
            entries.append(("NSVScroller", t.reference(reader.next())))
            entries.append(("NSHScroller", t.reference(reader.next())))
            entries.append(("NSContentView", t.reference(reader.next())))
            entries.append(("NSHeaderClipView", t.reference(reader.next())))
            entries.append(("NSCornerView", t.reference(reader.next())))
            reader.skip(4)
            // The vertical scroller in bit 31, the horizontal in bit 30,
            // the border type in bits 25 and 26.
            let old = UInt32(truncatingIfNeeded: reader.integer())
            var flags = Int64(old >> 25 & 3)
            if old & 0x8000_0000 != 0 { flags |= 0x10 }
            if old & 0x4000_0000 != 0 { flags |= 0x20 }
            entries.append(("NSsFlags", .integer(flags)))
        },
        "NSTableView": { reader, entries, t, _ in
            entries.append(("NSHeaderView", t.reference(reader.next())))
            entries.append(("NSCornerView", t.reference(reader.next())))
            entries.append(("NSTableColumns", t.reference(reader.next())))
            entries.append(("NSIntercellSpacingWidth", .double(reader.real())))
            entries.append(("NSIntercellSpacingHeight", .double(reader.real())))
            entries.append(("NSBackgroundColor", t.reference(reader.next())))
            entries.append(("NSGridColor", t.reference(reader.next())))
            entries.append(("NSRowHeight", .double(reader.real())))
            entries.append(("NSDoubleAction", t.reference(reader.next())))
            reader.skip(1)
            entries.append(("NSTvFlags", .integer(reader.integer())))
            entries.append(("NSDataSource", t.reference(reader.next())))
            entries.append(("NSDelegate", t.reference(reader.next())))
            if case .object(let name?)? = reader.next(), name.className.hasSuffix("String") {
                entries.append(("NSAutosaveName", t.reference(.object(name))))
            }
        },
        "NSTableHeaderView": { reader, entries, t, _ in entries.append(("NSTableView", t.reference(reader.next()))) },
        "NSTableColumn": { reader, entries, t, _ in
            entries.append(("NSIdentifier", t.reference(reader.next())))
            entries.append(("NSWidth", .double(reader.real())))
            entries.append(("NSMinWidth", .double(reader.real())))
            entries.append(("NSMaxWidth", .double(reader.real())))
            entries.append(("NSHeaderCell", t.reference(reader.next())))
            entries.append(("NSDataCell", t.reference(reader.next())))
            entries.append(("NSResizingMask", .integer(reader.integer() != 0 ? 1 : 0)))
            entries.append(("NSIsEditable", .bool(reader.integer() != 0)))
            entries.append(("NSTableView", t.reference(reader.next())))
        },
        "NSBox": { reader, entries, t, _ in
            entries.append(("NSOffsets", Translation.doubles([reader.real(), reader.real()])))
            entries.append(("NSTitleCell", t.reference(reader.next())))
            entries.append(("NSContentView", t.reference(reader.next())))
            // The border type in the low two bits, the box type above.
            let kind = reader.integer()
            entries.append(("NSBorderType", .integer(kind & 3)))
            entries.append(("NSBoxType", .integer(kind >> 2 & 3)))
            entries.append(("NSTitlePosition", .integer(reader.integer())))
            entries.append(("NSTransparent", .bool(reader.integer() != 0)))
            reader.skip(1)
        },
        "NSSplitView": { reader, entries, t, _ in
            entries.append(("NSDelegate", t.reference(reader.next())))
            entries.append(("NSIsVertical", .bool(reader.integer() & 1 != 0)))
        },
        "NSTabView": { reader, entries, t, _ in
            entries.append(("NSTabViewItems", t.reference(reader.next())))
            entries.append(("NSSelectedTabViewItem", t.reference(reader.next())))
            entries.append(("NSFont", t.reference(reader.next())))
            entries.append(("NSTvFlags", .integer(reader.integer())))
            entries.append(("NSAllowTruncatedLabels", .bool(reader.integer() != 0)))
            entries.append(("NSDrawsBackground", .bool(reader.integer() != 0)))
            entries.append(("NSDelegate", t.reference(reader.next())))
        },
        "NSBrowser": { reader, _, _, _ in _ = reader.rest() },
        "NSViewTemplate": { reader, entries, t, className in
            // A text view, kept as a template of its class and settings.
            if case .object(let name?)? = reader.next(), case .bytes(let raw)? = name.values.first {
                let named = String(decoding: raw, as: UTF8.self)
                className = named == "NSText" ? "NSTextView" : named
            }
            reader.skip(1)
            entries.append(("NSBackgroundColor", t.reference(reader.next())))
            _ = reader.rest()
        },
        "NSTextTemplate": { reader, _, _, _ in _ = reader.rest() },
        "NSTabViewItem": { reader, entries, t, _ in
            entries.append(("NSIdentifier", t.reference(reader.next())))
            entries.append(("NSView", t.reference(reader.next())))
            entries.append(("NSLabel", t.reference(reader.next())))
            entries.append(("NSColor", t.reference(reader.next())))
            reader.skip(1)
            entries.append(("NSFirstResponder", t.reference(reader.next())))
            entries.append(("NSTabView", t.reference(reader.next())))
        },

        // MARK: Cells
        "NSCell": { reader, entries, t, _ in
            entries.append(("NSCellFlags", .integer(reader.integer())))
            entries.append(("NSCellFlags2", .integer(reader.integer())))
            entries.append(("NSContents", t.reference(reader.next())))
            entries.append(("NSSupport", t.reference(reader.next())))
            reader.skip(2)
        },
        "NSActionCell": { reader, entries, t, _ in
            entries.append(("NSTag", .integer(reader.integer())))
            entries.append(("NSAction", t.reference(reader.next())))
            entries.append(("NSTarget", t.reference(reader.next())))
            entries.append(("NSControlView", t.reference(reader.next())))
        },
        "NSTextFieldCell": { reader, entries, t, _ in
            entries.append(("NSDrawsBackground", .bool(reader.integer() != 0)))
            entries.append(("NSBackgroundColor", t.reference(reader.next())))
            entries.append(("NSTextColor", t.reference(reader.next())))
        },
        "NSComboBoxCell": { reader, entries, t, _ in
            entries.append(("NSVisibleItemCount", .integer(reader.integer())))
            entries.append(("NSHasVerticalScroller", .bool(reader.integer() != 0)))
            reader.skip(1)
            entries.append(("NSUsesDataSource", .bool(reader.integer() != 0)))
            entries.append(("NSPopUpListData", t.reference(reader.next())))
            _ = reader.rest()
        },
        "NSButtonCell": { reader, entries, t, _ in
            entries.append(("NSPeriodicDelay", .integer(reader.integer())))
            entries.append(("NSPeriodicInterval", .integer(reader.integer())))
            entries.append(("NSButtonFlags2", .integer(reader.integer())))
            entries.append(("NSButtonFlags", .integer(reader.integer())))
            entries.append(("NSAlternateContents", t.reference(reader.next())))
            entries.append(("NSKeyEquivalent", t.reference(reader.next())))
            entries.append(("NSNormalImage", t.reference(reader.next())))
            entries.append(("NSAlternateImage", t.reference(reader.next())))
            reader.skip(1)   // the sound
        },
        "NSMenuItemCell": { reader, entries, t, _ in
            entries.append(("NSMenuItem", t.reference(reader.next())))
            reader.skip(1)
        },
        "NSPopUpButtonCell": { reader, entries, t, _ in
            reader.skip(1)
            entries.append(("NSMenu", t.reference(reader.next())))
            entries.append(("NSSelectedIndex", .integer(reader.integer())))
        },
        "NSImageCell": { reader, entries, _, _ in
            entries.append(("NSAlign", .integer(reader.integer())))
            entries.append(("NSScale", .integer(reader.integer())))
            entries.append(("NSStyle", .integer(reader.integer())))
        },
    ]
}
