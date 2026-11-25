import CPerryFoundation
import Glibc
import PerryObjCInterop

/// An object as a Swift dictionary key, compared with -isEqual: and hashed
/// with -hash, as NSDictionary and NSSet compare their members.
struct ObjectKey: Hashable {
    let object: id

    static func == (lhs: ObjectKey, rhs: ObjectKey) -> Bool {
        lhs.object == rhs.object || ObjC.sendBool(lhs.object, Selectors.isEqual, rhs.object)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjC.sendUInt(object, Selectors.hash))
    }
}

// The app's code may raise an Objective-C exception, which unwinds through
// Swift without ending the accesses its frames have open. A mutating call
// on a stored property or a global (sort(by:), removeAll(where:)) keeps
// one open while its closure runs, and one left behind stays in Swift's
// record of accesses after its frame is gone, for the next one to trip on.
// Code that calls the app (a comparator, a block, -isEqual:) works on a
// copy, and the result is assigned back once the app has returned.
extension Array {
    /// The elements `matches` keeps, and the ones it takes out, in order.
    /// `matches` runs once for each, with no access to the array open.
    func split(removing matches: (Element) throws -> Bool) rethrows -> (kept: [Element], removed: [Element]) {
        var kept: [Element] = [], removed: [Element] = []
        for element in self {
            if try matches(element) { removed.append(element) } else { kept.append(element) }
        }
        return (kept, removed)
    }
}

/// Blocks: the invoke function is the word after isa, flags and reserved,
/// callable from Linux code (darwinCallable).
enum Blocks {
    static func invoke<Function>(_ block: id, as type: Function.Type) -> Function {
        darwinCallable(unsafeBitCast(block.load(fromByteOffset: DarwinLayout.blockInvoke, as: UnsafeRawPointer.self), to: type))
    }
}

/// for (id x in collection): elements go out in batches through the
/// caller's own buffer, with the position in the caller's state, so
/// enumerations of a collection, nested or on other threads, share nothing.
/// The mutations counter lets the loop notice the collection changing.
final class EnumerationBuffer {
    let mutations: UnsafeMutablePointer<UInt>

    init() {
        mutations = .allocate(capacity: 1)
        mutations.initialize(to: 0)
    }

    deinit {
        mutations.deallocate()
    }

    /// countByEnumeratingWithState:objects:count: for `objects`.
    /// NSFastEnumerationState is { state, itemsPtr, mutationsPtr, extra[5] }:
    /// state is the index of the next batch, plus one once started.
    func enumerate(_ objects: [id], state: UnsafeMutableRawPointer?, buffer: UnsafeMutablePointer<id?>?, count: UInt) -> UInt {
        guard let state, let buffer, count > 0 else { return 0 }
        let started = state.load(as: UInt.self)
        let next = started == 0 ? 0 : Int(started - 1)
        guard next < objects.count else { return 0 }
        let batch = min(Int(count), objects.count - next)
        for index in 0..<batch {
            buffer[index] = objects[next + index]
        }
        state.storeBytes(of: UInt(next + batch + 1), as: UInt.self)
        state.storeBytes(of: UnsafeMutableRawPointer(buffer), toByteOffset: DarwinLayout.enumerationItems,
                         as: UnsafeMutableRawPointer.self)
        state.storeBytes(of: UnsafeMutableRawPointer(mutations), toByteOffset: DarwinLayout.enumerationMutations,
                         as: UnsafeMutableRawPointer.self)
        return UInt(batch)
    }

    func mutated() {
        mutations.pointee &+= 1
    }
}

/// Descriptions in Foundation's old-style property list format, which
/// collections use: strings quoted unless they are a plain word, nested
/// collections indented by four spaces per level. As in Foundation, a
/// collection at level n starts with its own indentation, so a nested one's
/// first line is indented twice ("planets =     (").
enum Describe {
    static func object(_ object: id?, indent: Int) -> String {
        guard let object else { return "(null)" }
        if let string = Strings.value(of: object) {
            return quoted(string)
        }
        if ObjC.isKind(object, of: Arrays.arrayClass) {
            return list(Arrays.elements(object), open: "(", close: ")", indent: indent)
        }
        if ObjC.isKind(object, of: Sets.setClass) {
            return list(Sets.elements(object), open: "{(", close: ")}", indent: indent)
        }
        if ObjC.isKind(object, of: Dictionaries.dictionaryClass) {
            return dictionary(Dictionaries.entries(object), indent: indent)
        }
        return Format.describe(object)
    }

    static func list(_ elements: [id], open: String, close: String, indent: Int) -> String {
        guard !elements.isEmpty else { return pad(indent) + open + "\n" + pad(indent) + close }
        let items = elements.map { pad(indent + 1) + object($0, indent: indent + 1) }
        return pad(indent) + open + "\n" + items.joined(separator: ",\n") + "\n" + pad(indent) + close
    }

    static func dictionary(_ entries: [(key: id, value: id)], indent: Int) -> String {
        guard !entries.isEmpty else { return pad(indent) + "{\n" + pad(indent) + "}" }
        var lines = entries.map { (key: object($0.key, indent: indent + 1), value: object($0.value, indent: indent + 1)) }
        // Keys are listed in sorted order when they are all strings.
        if entries.allSatisfy({ Strings.value(of: $0.key) != nil }) {
            let keys = entries.map { Strings.value(of: $0.key) ?? "" }
            lines = zip(keys, lines).sorted { Strings.compare($0.0, $1.0) < 0 }.map(\.1)
        }
        let body = lines.map { pad(indent + 1) + "\($0.key) = \($0.value);" }
        return pad(indent) + "{\n" + body.joined(separator: "\n") + "\n" + pad(indent) + "}"
    }

    /// The entries as a strings file has them, a `"key" = "value";` line
    /// each, sorted by key when the keys are all strings, with no braces.
    static func stringsFile(_ entries: [(key: id, value: id)]) -> String {
        func item(_ object: id) -> String {
            if let string = Strings.value(of: object) { return quoted(string, always: true) }
            return Describe.object(object, indent: 0)
        }
        var lines = entries.map { (key: item($0.key), value: item($0.value)) }
        if entries.allSatisfy({ Strings.value(of: $0.key) != nil }) {
            let keys = entries.map { Strings.value(of: $0.key) ?? "" }
            lines = zip(keys, lines).sorted { Strings.compare($0.0, $1.0) < 0 }.map(\.1)
        }
        return lines.map { "\($0.key) = \($0.value);\n" }.joined()
    }

    private static func pad(_ level: Int) -> String {
        String(repeating: " ", count: level * 4)
    }

    /// Strings print bare when they are a plain word, otherwise quoted
    /// with escapes; `always` quotes plain words too.
    static func quoted(_ string: String, always: Bool = false) -> String {
        let plain = !always && !string.isEmpty && string.unicodeScalars.allSatisfy {
            $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains(Character($0)) || "_$.".unicodeScalars.contains($0))
        }
        if plain { return string }
        var escaped = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\t": escaped += "\\t"
            default:
                if scalar.isASCII {
                    escaped.unicodeScalars.append(scalar)
                } else {
                    // Non-ASCII characters print as \\Uxxxx escapes.
                    for unit in String(scalar).utf16 {
                        escaped += "\\U" + hex4(unit)
                    }
                }
            }
        }
        return escaped + "\""
    }

    private static func hex4(_ value: UInt16) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: 4 - digits.count) + digits
    }
}
