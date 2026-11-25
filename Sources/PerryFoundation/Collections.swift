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

/// The positions of a collection's members by their -hash, for finding a
/// member equal to an object as NSSet and NSDictionary do: one with the
/// same hash, then identical or -isEqual:.
///
/// A Swift Set or Dictionary of ObjectKey would call the app's -hash and
/// -isEqual: from inside its own mutations (an insertion hashes the key, a
/// removal compares it), with the collection's stored property open for
/// modifying. This one keeps each member's hash, taken before it is added,
/// so only `position(of:hash:in:)` calls the app, on a copy of the index
/// and the members, and the mutations that follow call nothing.
struct ObjectIndex {
    /// The positions with one hash: one, nearly always, so there is no
    /// array to allocate for it.
    private struct Bucket {
        var first: Int
        var others: [Int] = []

        mutating func shift(from start: Int, by offset: Int) {
            if first >= start { first += offset }
            for index in others.indices where others[index] >= start {
                others[index] += offset
            }
        }

        /// Takes a position out; false once there is none left.
        mutating func remove(_ position: Int) -> Bool {
            if first == position {
                guard let last = others.popLast() else { return false }
                first = last
            } else if let index = others.firstIndex(of: position) {
                others.remove(at: index)
            }
            return true
        }
    }

    /// Each member's hash, in the members' order.
    private(set) var hashes: [UInt] = []
    private var buckets: [UInt: Bucket] = [:]

    /// The object's -hash, which the app may implement.
    static func hash(of object: id) -> UInt {
        ObjC.sendUInt(object, Selectors.hash)
    }

    /// The position of the member of `members` equal to `object`, whose
    /// hash is `hash`: identical, or one that says so to -isEqual:. Calls
    /// the app, so the index and the members must be copies, with no
    /// access to the properties they came from open.
    func position(of object: id, hash: UInt, in members: [id]) -> Int? {
        guard let bucket = buckets[hash] else { return nil }
        // The app may have changed the collection from its -isEqual:.
        func equal(_ position: Int) -> Bool {
            position < members.count && (members[position] == object || ObjC.sendBool(members[position], Selectors.isEqual, object))
        }
        if equal(bucket.first) { return bucket.first }
        return bucket.others.first(where: equal)
    }

    /// A member with this hash, inserted at `position`; the ones from
    /// there on move up one.
    mutating func insert(_ hash: UInt, at position: Int) {
        if position < hashes.count { shift(from: position, by: 1) }
        hashes.insert(hash, at: position)
        add(position, hash)
    }

    mutating func append(_ hash: UInt) {
        hashes.append(hash)
        add(hashes.count - 1, hash)
    }

    /// The member at `position` taken out; the ones after it move down one.
    mutating func remove(at position: Int) {
        take(position, hashes.remove(at: position))
        if position < hashes.count { shift(from: position + 1, by: -1) }
    }

    /// A member with another hash at `position`.
    mutating func replace(at position: Int, with hash: UInt) {
        take(position, hashes[position])
        hashes[position] = hash
        add(position, hash)
    }

    mutating func swapAt(_ a: Int, _ b: Int) {
        let (hashA, hashB) = (hashes[a], hashes[b])
        guard a != b, hashA != hashB else { return }
        take(a, hashA)
        take(b, hashB)
        add(b, hashA)
        add(a, hashB)
        hashes.swapAt(a, b)
    }

    mutating func removeAll() {
        hashes.removeAll()
        buckets.removeAll()
    }

    private mutating func add(_ position: Int, _ hash: UInt) {
        if buckets[hash] == nil {
            buckets[hash] = Bucket(first: position)
        } else {
            buckets[hash]!.others.append(position)
        }
    }

    private mutating func take(_ position: Int, _ hash: UInt) {
        if buckets[hash]?.remove(position) == false { buckets[hash] = nil }
    }

    private mutating func shift(from start: Int, by offset: Int) {
        var index = buckets.values.startIndex
        while index != buckets.values.endIndex {
            buckets.values[index].shift(from: start, by: offset)
            buckets.values.formIndex(after: &index)
        }
    }
}

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
