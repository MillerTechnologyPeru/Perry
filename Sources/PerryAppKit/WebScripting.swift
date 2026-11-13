import Glibc
import PerryObjCInterop

// WebKit's web scripting for AppKit's WebView: pages call the Objective-C
// objects an app sets on a web view's window script object, as
// window.name.method(...), and get the result at once. The page is in
// WPE's web process; PerryWebExtension there asks for the objects as each
// window object is cleared ("perry.cleared") and sends each call
// ("perry.call"), with JSON both ways. An object shows the methods its
// class lets scripts call (+isSelectorExcludedFromWebScript: answering NO;
// without it, none), named by +webScriptNameForSelector: or else by their
// selector with colons as underscores. Arguments and results are what JSON
// has: strings, numbers, Booleans, arrays and dictionaries as Foundation's,
// null as nil; a method's parameters and result may be objects or integers.

enum WebScripting {
    typealias Object = UnsafeMutableRawPointer
    private static let libobjc = "/usr/lib/libobjc.A.dylib"

    // Messages, by their types.
    private typealias Selector = UnsafeRawPointer
    private static func send(_ receiver: Object?, _ selector: String, _ first: Object? = nil, _ second: Object? = nil,
                             _ third: Object? = nil) -> Object? {
        guard let receiver else { return nil }
        typealias F = @convention(c) (Object, Selector, Object?, Object?, Object?) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), first, second, third)
    }
    private static func send(_ receiver: Object?, _ selector: String, _ first: Object?, int second: Int, _ third: Object?) -> Object? {
        guard let receiver else { return nil }
        typealias F = @convention(c) (Object, Selector, Object?, Int, Object?) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), first, second, third)
    }
    private static func send(_ receiver: Object?, _ selector: String, word: UInt) -> Object? {
        guard let receiver else { return nil }
        typealias F = @convention(c) (Object, Selector, UInt) -> Object?
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), word)
    }
    private static func word(_ receiver: Object?, _ selector: String) -> UInt {
        guard let receiver else { return 0 }
        typealias F = @convention(c) (Object, Selector) -> UInt
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector))
    }
    private static func flag(_ receiver: Object?, _ selector: String, _ argument: Object?) -> Bool {
        guard let receiver else { return false }
        typealias F = @convention(c) (Object, Selector, Object?) -> Bool
        return unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(receiver, ObjCRuntime.selector(selector), argument)
    }
    private static var null: Object? { send(ObjCRuntime.classObject("NSNull"), "null") }

    private static func function<T>(_ name: String, _: T.Type) -> T? {
        Symbols.lookup?(libobjc, name).map { unsafeBitCast($0, to: T.self) }
    }

    private static let copyMethodList = function("_class_copyMethodList",
        (@convention(c) (Object?, UnsafeMutablePointer<UInt32>?) -> UnsafeMutablePointer<Object?>?).self)
    private static let methodGetName = function("_method_getName", (@convention(c) (Object?) -> UnsafeRawPointer?).self)
    private static let methodGetTypeEncoding = function("_method_getTypeEncoding", (@convention(c) (Object?) -> UnsafePointer<CChar>?).self)
    private static let selectorName = function("_sel_getName", (@convention(c) (UnsafeRawPointer?) -> UnsafePointer<CChar>?).self)
    private static let classGetSuperclass = function("_class_getSuperclass", (@convention(c) (Object?) -> Object?).self)

    /// A method scripts can call: its selector and type encoding.
    struct Method {
        let selector: String
        let types: String
    }

    /// The methods scripts may call on an object, by their names in
    /// scripts.
    static func methods(of object: Object) -> [String: Method] {
        guard let copyMethodList, let methodGetName, let methodGetTypeEncoding, let selectorName, let classGetSuperclass else { return [:] }
        var found: [String: Method] = [:]
        let root = ObjCRuntime.classObject("NSObject")
        var cls: Object? = ObjCRuntime.objectClass(object)
        // Whether the class lets scripts call a selector, and the name.
        let instanceClass = cls
        let excludes = instanceClass.map { Send.responds($0, "isSelectorExcludedFromWebScript:") } ?? false
        let names = instanceClass.map { Send.responds($0, "webScriptNameForSelector:") } ?? false
        guard excludes else { return [:] }
        while let current = cls, current != root {
            var count: UInt32 = 0
            if let list = copyMethodList(current, &count) {
                for index in 0..<Int(count) {
                    guard let method = list[index], let selector = methodGetName(method), let name = selectorName(selector) else { continue }
                    let selectorString = String(cString: name)
                    typealias Excluded = @convention(c) (Object?, UnsafeRawPointer?, UnsafeRawPointer?) -> Bool
                    let excluded = unsafeBitCast(ObjCRuntime.msgSend, to: Excluded.self)(
                        instanceClass, ObjCRuntime.selector("isSelectorExcludedFromWebScript:"), selector)
                    guard !excluded else { continue }
                    var scriptName = String(selectorString.map { $0 == ":" ? "_" : $0 })
                    if names {
                        typealias Name = @convention(c) (Object?, UnsafeRawPointer?, UnsafeRawPointer?) -> Object?
                        if let given = unsafeBitCast(ObjCRuntime.msgSend, to: Name.self)(
                            instanceClass, ObjCRuntime.selector("webScriptNameForSelector:"), selector) {
                            scriptName = String(objCArgument: given)
                        }
                    }
                    let types = methodGetTypeEncoding(method).map { String(cString: $0) } ?? ""
                    if found[scriptName] == nil { found[scriptName] = Method(selector: selectorString, types: types) }
                }
                Glibc.free(list)
            }
            cls = classGetSuperclass(current)
        }
        return found
    }

    // MARK: JSON

    /// Foundation's value of JSON text, +0; nil for null or bad text.
    static func parse(_ json: String) -> Object? {
        // NSUTF8StringEncoding, and NSJSONReadingFragmentsAllowed: a string
        // or number alone too.
        guard let data = send(json.objCArgument(), "dataUsingEncoding:", word: 4),
              let value = send(ObjCRuntime.classObject("NSJSONSerialization"), "JSONObjectWithData:options:error:", data, int: 4, nil),
              value != null else { return nil }
        return value
    }

    /// JSON text of a Foundation value; "null" for nil or what JSON can't
    /// hold.
    static func json(_ value: Object?) -> String {
        guard let value else { return "null" }
        let serialization = ObjCRuntime.classObject("NSJSONSerialization")
        guard let array = send(ObjCRuntime.classObject("NSArray"), "arrayWithObject:", value),
              flag(serialization, "isValidJSONObject:", array),
              let data = send(serialization, "dataWithJSONObject:options:error:", array, int: 0, nil),
              let text = send(ObjCRuntime.classObject("NSString"), "alloc").flatMap({ send($0, "initWithData:encoding:", data, int: 4, nil) })
        else { return "null" }
        defer { ObjCRuntime.release(text) }
        // [value] without its brackets.
        let wrapped = String(objCArgument: text)
        return String(wrapped.dropFirst().dropLast())
    }

    // MARK: Calls

    /// The types in a method's type encoding: its result's, then self's,
    /// _cmd's and its parameters', without qualifiers or offsets.
    static func types(_ encoding: String) -> [Character] {
        var result: [Character] = []
        var characters = Array(encoding)[...]
        while let first = characters.first {
            characters = characters.dropFirst()
            switch first {
            case "r", "n", "N", "o", "O", "R", "V", "0"..."9", "-": continue
            case "{", "(", "[":
                // A structure, union or array: skipped whole, as a type
                // scripts can't pass.
                var depth = 1
                while depth > 0, let next = characters.first {
                    characters = characters.dropFirst()
                    if next == "{" || next == "(" || next == "[" { depth += 1 }
                    if next == "}" || next == ")" || next == "]" { depth -= 1 }
                }
                result.append("?")
            case "^":
                if !characters.isEmpty { characters = characters.dropFirst() }
                result.append("^")
            default:
                result.append(first)
            }
        }
        return result
    }

    private static let integers: Set<Character> = ["c", "C", "s", "S", "i", "I", "l", "L", "B"]
    private static let wideIntegers: Set<Character> = ["q", "Q"]

    /// Calls a script method of an object with arguments from JSON (an
    /// array): its result as JSON.
    static func call(_ object: Object, _ method: Method, _ arguments: Object?) -> String {
        let types = types(method.types)
        guard types.count >= 3, types.count - 3 <= 5 else { return "null" }
        let wide = MemoryLayout<UInt>.size == 8
        var words: [UInt] = []
        for (position, type) in types.dropFirst(3).enumerated() {
            let argument = arguments.flatMap { list -> Object? in
                guard position < Int(word(list, "count")) else { return nil }
                let item = send(list, "objectAtIndex:", word: UInt(position))
                return item == null ? nil : item
            }
            switch type {
            case "@", "#":
                words.append(UInt(bitPattern: argument))
            case _ where integers.contains(type) || (wide && wideIntegers.contains(type)):
                let number = argument.map { Int(bitPattern: word($0, "longValue")) } ?? 0
                words.append(UInt(bitPattern: number))
            default:
                WPE.log("a script's call of \(method.selector) has a parameter of type \(type), which scripts can't pass")
                return "null"
            }
        }
        while words.count < 5 { words.append(0) }
        typealias Send5 = @convention(c) (Object?, UnsafeRawPointer?, UInt, UInt, UInt, UInt, UInt) -> UInt
        let result = unsafeBitCast(ObjCRuntime.msgSend, to: Send5.self)(object, ObjCRuntime.selector(method.selector),
                                                                        words[0], words[1], words[2], words[3], words[4])
        switch types[0] {
        case "v":
            return "null"
        case "@":
            return json(UnsafeMutableRawPointer(bitPattern: result))
        case "B":
            return result & 0xff != 0 ? "true" : "false"
        case "c":
            return String(Int8(truncatingIfNeeded: result))
        case "C":
            return String(UInt8(truncatingIfNeeded: result))
        case "s":
            return String(Int16(truncatingIfNeeded: result))
        case "S":
            return String(UInt16(truncatingIfNeeded: result))
        case "i", "l":
            return String(Int32(truncatingIfNeeded: result))
        case "I", "L":
            return String(UInt32(truncatingIfNeeded: result))
        case "q" where wide:
            return String(Int(bitPattern: result))
        case "Q" where wide:
            return String(result)
        default:
            return "null"
        }
    }
}
