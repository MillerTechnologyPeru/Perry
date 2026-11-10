import CPerryFoundation
import Glibc
import PerryObjCInterop

// NSPredicate, NSComparisonPredicate, NSCompoundPredicate and NSExpression:
// a predicate tree parsed from Apple's format syntax, printed back as
// Darwin prints it, and evaluated against objects through key-value
// coding. Core Data reads the tree through the public API to run fetches.

/// An expression's value.
indirect enum ExpressionNode {
    case keyPath(String)
    case constant(ObjCObject?)
    case evaluatedObject
    case aggregate([ExpressionNode])
    /// A function by name ("count:", "max:") of argument expressions.
    case function(String, [ExpressionNode])
    /// A substitution variable ("$p"), bound by a subquery.
    case variable(String)
    /// SUBQUERY(collection, $variable, predicate): the members of the
    /// collection the predicate holds for.
    case subquery(ExpressionNode, String, PredicateNode)

    /// NSExpressionType.
    var type: UInt {
        switch self {
        case .constant: return 0
        case .evaluatedObject: return 1
        case .keyPath: return 3
        case .aggregate: return 14
        case .function: return 4
        case .variable: return 2
        case .subquery: return 13
        }
    }
}

/// A predicate.
indirect enum PredicateNode {
    case truth(Bool)
    case comparison(Comparison)
    case compound(UInt, [PredicateNode])
    /// predicateWithBlock:'s block, copied, which the predicate keeps.
    case block(BlockReference)

    struct Comparison {
        var left: ExpressionNode
        var right: ExpressionNode
        var operation: UInt
        var modifier: UInt
        var options: UInt
    }
}

/// A block a predicate holds: copied when made, released with the last
/// predicate to hold it.
final class BlockReference {
    let block: id
    init?(_ block: id?) {
        guard let copied = block.flatMap({ ObjC.retainBlock($0) }) else { return nil }
        self.block = copied
    }
    deinit { ObjC.release(block) }

    /// The block's answer for an object and substitution variables.
    func evaluate(_ object: id?, _ bindings: id?) -> Bool {
        Blocks.invoke(block, as: (@convention(c) (id, id?, id?) -> Bool).self)(block, object, bindings)
    }
}

/// The functions the infix operators of an expression stand for, by their
/// NSExpression names.
enum PredicateArithmetic {
    static let symbols: [String: String] = [
        "add:to:": "+", "from:subtract:": "-", "multiply:by:": "*", "divide:by:": "/",
        "bitwiseAnd:with:": "&", "bitwiseOr:with:": "|",
    ]

    /// An operator's function, and the precedence it binds with: bitwise or,
    /// bitwise and, sums, then products.
    static let operators: [String: (function: String, level: Int)] = [
        "|": ("bitwiseOr:with:", 0), "&": ("bitwiseAnd:with:", 1),
        "+": ("add:to:", 2), "-": ("from:subtract:", 2), "*": ("multiply:by:", 3), "/": ("divide:by:", 3),
    ]

    /// The result of a function on two numbers: integers stay integers
    /// where both operands are, and a division by zero has none.
    static func apply(_ name: String, _ left: id?, _ right: id?) -> id? {
        guard let left, let right, ObjC.isKind(left, of: Numbers.numberClass), ObjC.isKind(right, of: Numbers.numberClass) else {
            return nil
        }
        let a = Numbers.storage(left), b = Numbers.storage(right)
        if name == "bitwiseAnd:with:" { return Numbers.make(nil, .signed(a.int64 & b.int64)) }
        if name == "bitwiseOr:with:" { return Numbers.make(nil, .signed(a.int64 | b.int64)) }
        if a.isFloatingPoint || b.isFloatingPoint {
            let x = a.double, y = b.double
            switch name {
            case "add:to:": return Numbers.make(nil, .double(x + y))
            case "from:subtract:": return Numbers.make(nil, .double(x - y))
            case "multiply:by:": return Numbers.make(nil, .double(x * y))
            case "divide:by:": return Numbers.make(nil, .double(x / y))
            default: return nil
            }
        }
        let x = a.int64, y = b.int64
        switch name {
        case "add:to:": return Numbers.make(nil, .signed(x &+ y))
        case "from:subtract:": return Numbers.make(nil, .signed(x &- y))
        case "multiply:by:": return Numbers.make(nil, .signed(x &* y))
        case "divide:by:": return y == 0 ? nil : Numbers.make(nil, .signed(x / y))
        default: return nil
        }
    }
}

/// NSPredicateOperatorType and the other enums, as Darwin numbers them.
enum PredicateOperator {
    static let lessThan: UInt = 0, lessThanOrEqualTo: UInt = 1, greaterThan: UInt = 2, greaterThanOrEqualTo: UInt = 3
    static let equalTo: UInt = 4, notEqualTo: UInt = 5, matches: UInt = 6, like: UInt = 7, beginsWith: UInt = 8
    static let endsWith: UInt = 9, `in`: UInt = 10, contains: UInt = 99, between: UInt = 100

    static let names: [UInt: String] = [
        lessThan: "<", lessThanOrEqualTo: "<=", greaterThan: ">", greaterThanOrEqualTo: ">=", equalTo: "==",
        notEqualTo: "!=", matches: "MATCHES", like: "LIKE", beginsWith: "BEGINSWITH", endsWith: "ENDSWITH",
        `in`: "IN", contains: "CONTAINS", between: "BETWEEN",
    ]
}

enum PredicateModifier { static let direct: UInt = 0, all: UInt = 1, any: UInt = 2 }
enum PredicateOptions { static let caseInsensitive: UInt = 1, diacriticInsensitive: UInt = 2, normalized: UInt = 4 }
enum CompoundType { static let not: UInt = 0, and: UInt = 1, or: UInt = 2 }

// MARK: - Printing

enum PredicateFormat {
    static func expression(_ node: ExpressionNode) -> String {
        switch node {
        case .keyPath(let path): return path
        case .evaluatedObject: return "SELF"
        case .aggregate(let elements): return "{" + elements.map(expression).joined(separator: ", ") + "}"
        case .constant(let value): return constant(value?.objcObject)
        case .variable(let name): return "$" + name
        case .subquery(let collection, let variable, let predicate):
            return "SUBQUERY(" + expression(collection) + ", $" + variable + ", " + PredicateFormat.predicate(predicate) + ")"
        case .function(let name, let arguments):
            if let symbol = PredicateArithmetic.symbols[name], arguments.count == 2 {
                return "(" + expression(arguments[0]) + " \(symbol) " + expression(arguments[1]) + ")"
            }
            return String(name.prefix { $0 != ":" }) + "(" + arguments.map(expression).joined(separator: ", ") + ")"
        }
    }

    static func constant(_ object: id?) -> String {
        guard let object, object != Nulls.null else { return "nil" }
        if let string = Strings.value(of: object) {
            return "\"" + string.replacingAll("\\", "\\\\").replacingAll("\"", "\\\"") + "\""
        }
        if ObjC.isKind(object, of: Arrays.arrayClass) || ObjC.isKind(object, of: Sets.setClass) {
            let elements = ObjC.isKind(object, of: Arrays.arrayClass) ? Arrays.elements(object) : Sets.elements(object)
            return "{" + elements.map(constant).joined(separator: ", ") + "}"
        }
        return Format.describe(object)
    }

    static func predicate(_ node: PredicateNode) -> String {
        switch node {
        case .truth(let value):
            return value ? "TRUEPREDICATE" : "FALSEPREDICATE"
        case .comparison(let c):
            let modifier = c.modifier == PredicateModifier.any ? "ANY " : c.modifier == PredicateModifier.all ? "ALL " : ""
            var flags = ""
            if c.options & PredicateOptions.caseInsensitive != 0 { flags += "c" }
            if c.options & PredicateOptions.diacriticInsensitive != 0 { flags += "d" }
            if c.options & PredicateOptions.normalized != 0 { flags += "n" }
            let operation = (PredicateOperator.names[c.operation] ?? "?") + (flags.isEmpty ? "" : "[\(flags)]")
            return "\(modifier)\(expression(c.left)) \(operation) \(expression(c.right))"
        case .compound(let type, let subpredicates):
            // Compound subpredicates are parenthesized.
            let parts = subpredicates.map { sub -> String in
                if case .compound = sub { return "(" + predicate(sub) + ")" }
                return predicate(sub)
            }
            if type == CompoundType.not { return "NOT " + (parts.first ?? "") }
            return parts.joined(separator: type == CompoundType.and ? " AND " : " OR ")
        case .block(let reference):
            return "BLOCKPREDICATE(\(reference.block))"
        }
    }
}

private extension String {
    func replacingAll(_ target: String, _ replacement: String) -> String {
        var result = "", rest = Substring(self)
        while let range = rest.firstRange(of: target) {
            result += rest[..<range.lowerBound] + replacement
            rest = rest[range.upperBound...]
        }
        return result + rest
    }
}

// MARK: - Parsing

/// Where a format's substitutions come from: Darwin's variadic arguments or
/// an argument array.
enum PredicateArguments {
    case variadic(DarwinArguments)
    case array([id])

    mutating func object() -> id? {
        switch self {
        case .variadic(var arguments):
            let value = arguments.nextPointer()
            self = .variadic(arguments)
            return value
        case .array(var values):
            guard !values.isEmpty else { foundationFatal("Insufficient arguments for conversion characters specified in format string.") }
            let value = values.removeFirst()
            self = .array(values)
            return value
        }
    }

    /// A double argument, as its bits.
    mutating func double() -> UInt64 {
        switch self {
        case .variadic(var arguments):
            let value = arguments.nextDouble()
            self = .variadic(arguments)
            return value
        case .array:
            return word(wide: true)
        }
    }

    /// An int, long or pointer argument; `wide` for a long long.
    mutating func word(wide: Bool = false) -> UInt64 {
        switch self {
        case .variadic(var arguments):
            let value = wide ? arguments.next64() : arguments.next()
            self = .variadic(arguments)
            return value
        case .array:
            // An argument array holds objects: numbers in NSNumbers.
            let number = object()
            return UInt64(bitPattern: Numbers.storage(number).int64)
        }
    }
}

struct PredicateParser {
    enum Token: Equatable {
        case word(String)       // identifiers, key paths and keywords
        case string(String)
        case number(String)
        case symbol(String)
        case format(String)     // %@, %K, %d…
        case end
    }

    let format: String
    private var tokens: [Token] = []
    private var position = 0
    var arguments: PredicateArguments

    init(_ format: String, arguments: PredicateArguments) {
        self.format = format
        self.arguments = arguments
        tokens = Self.tokenize(format)
    }

    static func tokenize(_ format: String) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(format)
        var i = 0
        func peek(_ offset: Int = 0) -> Character? { i + offset < characters.count ? characters[i + offset] : nil }
        while let c = peek() {
            if c.isWhitespace { i += 1; continue }
            if c == "\"" || c == "'" {
                var text = ""
                i += 1
                while let d = peek(), d != c {
                    if d == "\\", let escaped = peek(1) {
                        text.append(escaped == "n" ? "\n" : escaped == "t" ? "\t" : escaped)
                        i += 2
                    } else {
                        text.append(d)
                        i += 1
                    }
                }
                i += 1
                tokens.append(.string(text))
            } else if c == "%" {
                var spec = "%"
                i += 1
                while let d = peek(), "lqhLzjt".contains(d) { spec.append(d); i += 1 }
                if let d = peek() { spec.append(d); i += 1 }
                tokens.append(.format(spec))
            } else if c.isNumber || (c == "-" && (peek(1)?.isNumber ?? false) && Self.expectsValue(tokens)) {
                var text = String(c)
                i += 1
                while let d = peek(), d.isNumber || d == "." || d == "e" || d == "E" || d == "x" || d.isHexDigit { text.append(d); i += 1 }
                tokens.append(.number(text))
            } else if c.isLetter || c == "_" || c == "$" || c == "@" || c == "#" {
                var text = ""
                while let d = peek(), d.isLetter || d.isNumber || d == "_" || d == "$" || d == "@" || d == "." || d == "#" {
                    text.append(d)
                    i += 1
                }
                tokens.append(.word(text))
            } else {
                let two = peek(1).map { String(c) + String($0) } ?? ""
                if ["==", "!=", "<>", "<=", "=<", ">=", "=>", "&&", "||"].contains(two) {
                    tokens.append(.symbol(two))
                    i += 2
                } else {
                    tokens.append(.symbol(String(c)))
                    i += 1
                }
            }
        }
        tokens.append(.end)
        return tokens
    }

    /// Whether a minus sign here starts a number rather than an operator.
    private static func expectsValue(_ tokens: [Token]) -> Bool {
        guard let last = tokens.last else { return true }
        switch last {
        case .symbol(let s): return s != ")" && s != "}"
        case .word(let w): return Self.keyword(w) != nil && !["SELF"].contains(w.uppercased())
        default: return false
        }
    }

    static func keyword(_ word: String) -> String? {
        let upper = word.uppercased()
        let keywords: Set<String> = ["AND", "OR", "NOT", "ANY", "ALL", "SOME", "NONE", "IN", "LIKE", "MATCHES", "BEGINSWITH",
                                     "ENDSWITH", "CONTAINS", "BETWEEN", "TRUEPREDICATE", "FALSEPREDICATE", "YES", "NO",
                                     "TRUE", "FALSE", "NIL", "NULL", "SELF"]
        return keywords.contains(upper) ? upper : nil
    }

    private var current: Token { tokens[position] }

    private mutating func advance() { if position < tokens.count - 1 { position += 1 } }

    private func fail(_ reason: String) -> Never {
        foundationFatal("Unable to parse the format string \"\(format)\": \(reason)")
    }

    private func isKeyword(_ name: String) -> Bool {
        if case .word(let w) = current { return Self.keyword(w) == name }
        return false
    }

    private func isSymbol(_ symbols: String...) -> Bool {
        if case .symbol(let s) = current { return symbols.contains(s) }
        return false
    }

    mutating func parse() -> PredicateNode {
        let node = parseOr()
        guard current == .end else { fail("unexpected \(current)") }
        return node
    }

    private mutating func parseOr() -> PredicateNode {
        var parts = [parseAnd()]
        while isKeyword("OR") || isSymbol("||") {
            advance()
            parts.append(parseAnd())
        }
        return parts.count == 1 ? parts[0] : .compound(CompoundType.or, parts)
    }

    private mutating func parseAnd() -> PredicateNode {
        var parts = [parseNot()]
        while isKeyword("AND") || isSymbol("&&") {
            advance()
            parts.append(parseNot())
        }
        return parts.count == 1 ? parts[0] : .compound(CompoundType.and, parts)
    }

    private mutating func parseNot() -> PredicateNode {
        if isKeyword("NOT") || isSymbol("!") {
            advance()
            return .compound(CompoundType.not, [parseNot()])
        }
        return parsePrimary()
    }

    /// Whether the parenthesis the parser is at opens an expression, which a
    /// comparison follows ("(a & 1) = 0"), rather than a predicate.
    private func groupIsExpression() -> Bool {
        var depth = 0, index = position
        while index < tokens.count {
            if case .symbol(let s) = tokens[index] {
                if s == "(" { depth += 1 }
                if s == ")" {
                    depth -= 1
                    if depth == 0 { break }
                }
            }
            index += 1
        }
        guard index + 1 < tokens.count else { return false }
        switch tokens[index + 1] {
        case .symbol(let s):
            return ["=", "==", "!=", "<>", "<", "<=", "=<", ">", ">=", "=>", "&", "|", "+", "-", "*", "/"].contains(s)
        case .word(let w):
            return ["IN", "LIKE", "MATCHES", "BEGINSWITH", "ENDSWITH", "CONTAINS", "BETWEEN"].contains(w.uppercased())
        default:
            return false
        }
    }

    private mutating func parsePrimary() -> PredicateNode {
        if isSymbol("("), !groupIsExpression() {
            advance()
            let node = parseOr()
            guard isSymbol(")") else { fail("missing )") }
            advance()
            return node
        }
        if isKeyword("TRUEPREDICATE") { advance(); return .truth(true) }
        if isKeyword("FALSEPREDICATE") { advance(); return .truth(false) }
        return parseComparison()
    }

    private mutating func parseComparison() -> PredicateNode {
        var modifier = PredicateModifier.direct
        var negate = false
        if isKeyword("ANY") || isKeyword("SOME") { modifier = PredicateModifier.any; advance() }
        else if isKeyword("ALL") { modifier = PredicateModifier.all; advance() }
        else if isKeyword("NONE") { modifier = PredicateModifier.any; negate = true; advance() }
        let left = parseExpression()
        let operation: UInt
        switch current {
        case .symbol("=="), .symbol("="): operation = PredicateOperator.equalTo
        case .symbol("!="), .symbol("<>"): operation = PredicateOperator.notEqualTo
        case .symbol("<"): operation = PredicateOperator.lessThan
        case .symbol("<="), .symbol("=<"): operation = PredicateOperator.lessThanOrEqualTo
        case .symbol(">"): operation = PredicateOperator.greaterThan
        case .symbol(">="), .symbol("=>"): operation = PredicateOperator.greaterThanOrEqualTo
        case .word(let w):
            switch Self.keyword(w) {
            case "IN": operation = PredicateOperator.in
            case "LIKE": operation = PredicateOperator.like
            case "MATCHES": operation = PredicateOperator.matches
            case "BEGINSWITH": operation = PredicateOperator.beginsWith
            case "ENDSWITH": operation = PredicateOperator.endsWith
            case "CONTAINS": operation = PredicateOperator.contains
            case "BETWEEN": operation = PredicateOperator.between
            default: fail("expected an operator, found \(w)")
            }
        default: fail("expected an operator")
        }
        advance()
        var options: UInt = 0
        if isSymbol("[") {
            advance()
            if case .word(let flags) = current {
                for flag in flags.lowercased() {
                    switch flag {
                    case "c": options |= PredicateOptions.caseInsensitive
                    case "d": options |= PredicateOptions.diacriticInsensitive
                    case "n": options |= PredicateOptions.normalized
                    default: fail("unknown option \(flag)")
                    }
                }
                advance()
            }
            guard isSymbol("]") else { fail("missing ]") }
            advance()
        }
        let right = parseExpression()
        let comparison = PredicateNode.comparison(.init(left: left, right: right, operation: operation,
                                                        modifier: modifier, options: options))
        return negate ? .compound(CompoundType.not, [comparison]) : comparison
    }

    /// An expression with its infix operators, the tighter binding first.
    private mutating func parseExpression(level: Int = 0) -> ExpressionNode {
        var left = level == 3 ? parseOperand() : parseExpression(level: level + 1)
        while case .symbol(let s) = current, let found = PredicateArithmetic.operators[s], found.level == level {
            advance()
            let right = level == 3 ? parseOperand() : parseExpression(level: level + 1)
            left = .function(found.function, [left, right])
        }
        return left
    }

    private mutating func parseOperand() -> ExpressionNode {
        let token = current
        advance()
        switch token {
        case .symbol("("):
            let inner = parseExpression()
            guard isSymbol(")") else { fail("missing )") }
            advance()
            return inner
        case .string(let text):
            return .constant(ObjCObject(Strings.autoreleased(text)))
        case .number(let text):
            return .constant(ObjCObject(Self.number(text)))
        case .word(let word):
            switch Self.keyword(word) {
            case "YES", "TRUE": return .constant(ObjCObject(perry_foundation_boolean(1)))
            case "NO", "FALSE": return .constant(ObjCObject(perry_foundation_boolean(0)))
            case "NIL", "NULL": return .constant(nil)
            case "SELF": return .evaluatedObject
            default:
                if word.uppercased() == "SUBQUERY", isSymbol("(") { return subquery() }
                if word.hasPrefix("$"), word.count > 1 { return .variable(String(word.dropFirst())) }
                return .keyPath(word.hasPrefix("#") ? String(word.dropFirst()) : word)
            }
        case .symbol("{"):
            var elements: [ExpressionNode] = []
            while !isSymbol("}") {
                elements.append(parseExpression())
                if isSymbol(",") { advance() } else if !isSymbol("}") { fail("missing }") }
            }
            advance()
            return .aggregate(elements)
        case .format(let spec):
            return substitution(spec)
        default:
            fail("unexpected \(token)")
        }
    }

    /// SUBQUERY(collection, $variable, predicate), and an aggregate key after
    /// it (".@count").
    private mutating func subquery() -> ExpressionNode {
        advance()
        let collection = parseExpression()
        guard isSymbol(",") else { fail("missing ,") }
        advance()
        guard case .word(let variable) = current, variable.hasPrefix("$") else { fail("SUBQUERY needs a variable") }
        advance()
        guard isSymbol(",") else { fail("missing ,") }
        advance()
        let predicate = parseOr()
        guard isSymbol(")") else { fail("missing )") }
        advance()
        var node = ExpressionNode.subquery(collection, String(variable.dropFirst()), predicate)
        if isSymbol("."), case .word(let key) = tokens[min(position + 1, tokens.count - 1)], key.hasPrefix("@") {
            let functions = ["@count": "count:", "@sum": "sum:", "@avg": "average:", "@max": "max:", "@min": "min:"]
            guard let function = functions[key] else { fail("unknown operator \(key)") }
            advance()
            advance()
            node = .function(function, [node])
        }
        return node
    }

    private mutating func substitution(_ spec: String) -> ExpressionNode {
        switch spec {
        case "%@":
            return .constant(arguments.object().map(ObjCObject.init))
        case "%K":
            guard let path = Strings.value(of: arguments.object()) else { fail("%K needs a key path string") }
            return .keyPath(path)
        case "%f", "%lf", "%g", "%e", "%F", "%Lf":
            return .constant(ObjCObject(Numbers.make(nil, .double(Double(bitPattern: arguments.double())))!))
        case "%u", "%lu", "%llu", "%qu", "%zu", "%x", "%lx", "%llx":
            let raw = arguments.word(wide: ["%llu", "%qu", "%llx"].contains(spec))
            let value = spec == "%u" || spec == "%x" ? UInt64(UInt32(truncatingIfNeeded: raw)) : raw
            return .constant(ObjCObject(Numbers.make(nil, .unsigned(value))!))
        case "%d", "%i", "%hd", "%hhd", "%c":
            return .constant(ObjCObject(Numbers.make(nil, .signed(Int64(Int32(truncatingIfNeeded: arguments.word()))))!))
        case "%lld", "%lli", "%qd":
            return .constant(ObjCObject(Numbers.make(nil, .signed(Int64(bitPattern: arguments.word(wide: true))))!))
        case "%ld", "%li", "%zd":
            return .constant(ObjCObject(Numbers.make(nil, .signed(Int64(Int(truncatingIfNeeded: arguments.word()))))!))
        case "%s":
            let pointer = arguments.object()
            return .constant(ObjCObject(Strings.autoreleased(pointer.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } ?? "")))
        default:
            fail("unsupported conversion \(spec)")
        }
    }

    static func number(_ text: String) -> id {
        if text.lowercased().hasPrefix("0x"), let value = Int64(text.dropFirst(2), radix: 16) {
            return Numbers.make(nil, .signed(value))!
        }
        if let value = Int64(text) { return Numbers.make(nil, .signed(value))! }
        return Numbers.make(nil, .double(Double(text) ?? 0))!
    }
}

// MARK: - Evaluation

enum PredicateEvaluation {
    /// A key path's value through key-value coding: -valueForKey: for each
    /// key, when the object responds to it.
    static func value(of path: String, in object: id?) -> id? {
        var current = object
        // "SELF.name" is the evaluated object's name.
        let keys = path.split(separator: ".")
        for key in keys.first?.uppercased() == "SELF" ? keys.dropFirst() : keys[...] {
            guard let target = current else { return nil }
            let keyObject = Strings.autoreleased(String(key))
            if ObjC.isKind(target, of: Dictionaries.dictionaryClass) {
                current = Dictionaries.value(target, for: keyObject)
            } else {
                current = ObjC.send(target, ObjC.selector("valueForKey:"), keyObject)
            }
        }
        return current
    }

    static func value(_ node: ExpressionNode, _ object: id?) -> id? {
        switch node {
        case .keyPath(let path): return value(of: path, in: object)
        case .constant(let value): return value?.objcObject
        case .evaluatedObject: return object
        case .aggregate(let elements): return Arrays.autoreleased(elements.compactMap { value($0, object) })
        case .function(let name, let arguments): return function(name, arguments.map { value($0, object) })
        case .variable(let name): return variables[name]
        case .subquery(let collection, let name, let predicate):
            let items = elements(value(collection, object)) ?? []
            let saved = variables[name]
            defer { variables[name] = saved }
            return Arrays.autoreleased(items.filter { item in
                variables[name] = item
                return evaluate(predicate, object)
            })
        }
    }

    /// The variables subqueries have bound, while they evaluate.
    nonisolated(unsafe) static var variables: [String: id] = [:]

    /// The aggregate functions over an argument's collection, and the case
    /// changes over a string.
    static func function(_ name: String, _ arguments: [id?]) -> id? {
        let items = arguments.first.flatMap { elements($0) } ?? []
        typealias DoubleValue = @convention(c) (id?, SEL) -> Double.ObjCResultType
        let doubleValue = unsafeBitCast(ObjC.msgSend, to: DoubleValue.self)
        let numbers = items.map { darwinResult(doubleValue($0, ObjC.selector("doubleValue")), as: Double.self) }
        switch name {
        case "count:": return Numbers.make(nil, .signed(Int64(items.count)))
        case "sum:": return Numbers.make(nil, .double(numbers.reduce(0, +)))
        case "average:": return Numbers.make(nil, .double(numbers.isEmpty ? 0 : numbers.reduce(0, +) / Double(numbers.count)))
        case "max:": return items.max { ObjC.sendInt($0, ObjC.selector("compare:"), $1) < 0 }
        case "min:": return items.min { ObjC.sendInt($0, ObjC.selector("compare:"), $1) < 0 }
        case "add:to:", "from:subtract:", "multiply:by:", "divide:by:", "bitwiseAnd:with:", "bitwiseOr:with:":
            return arguments.count == 2 ? PredicateArithmetic.apply(name, arguments[0], arguments[1]) : nil
        case "lowercase:", "uppercase:":
            guard let text = arguments.first.flatMap({ Strings.value(of: $0) }) else { return nil }
            return Strings.autoreleased(name == "lowercase:" ? text.lowercased() : text.uppercased())
        default: return nil
        }
    }

    static func elements(_ value: id?) -> [id]? {
        guard let value else { return nil }
        if ObjC.isKind(value, of: Arrays.arrayClass) { return Arrays.elements(value) }
        if ObjC.isKind(value, of: Sets.setClass) { return Sets.elements(value) }
        return nil
    }

    static func evaluate(_ node: PredicateNode, _ object: id?, bindings: id? = nil) -> Bool {
        switch node {
        case .truth(let value): return value
        case .block(let reference): return reference.evaluate(object, bindings)
        case .compound(let type, let parts):
            if type == CompoundType.not { return !evaluate(parts[0], object) }
            if type == CompoundType.and { return parts.allSatisfy { evaluate($0, object) } }
            return parts.contains { evaluate($0, object) }
        case .comparison(let c):
            let left = value(c.left, object), right = value(c.right, object)
            if c.modifier != PredicateModifier.direct {
                let items = elements(left) ?? []
                let test: (id?) -> Bool = { compare($0, right, c) }
                return c.modifier == PredicateModifier.any ? items.contains(where: test) : items.allSatisfy(test)
            }
            return compare(left, right, c)
        }
    }

    private static func text(_ value: id?, _ options: UInt) -> String? {
        guard var string = Strings.value(of: value) else { return nil }
        if options & PredicateOptions.caseInsensitive != 0 { string = string.lowercased() }
        return string
    }

    /// -compare: order of two values, when they can be ordered.
    private static func order(_ a: id?, _ b: id?) -> Int? {
        guard let a, let b else { return nil }
        return ObjC.sendInt(a, ObjC.selector("compare:"), b)
    }

    static func compare(_ left: id?, _ right: id?, _ c: PredicateNode.Comparison) -> Bool {
        let nullish: (id?) -> Bool = { $0 == nil || $0 == Nulls.null }
        switch c.operation {
        case PredicateOperator.equalTo, PredicateOperator.notEqualTo:
            var equal: Bool
            if nullish(left) || nullish(right) {
                equal = nullish(left) && nullish(right)
            } else if let l = text(left, c.options), let r = text(right, c.options) {
                equal = l == r
            } else {
                equal = ObjC.sendBool(left, Selectors.isEqual, right)
            }
            return c.operation == PredicateOperator.equalTo ? equal : !equal
        case PredicateOperator.lessThan: return (order(left, right) ?? 0) < 0 && !nullish(left) && !nullish(right)
        case PredicateOperator.lessThanOrEqualTo: return order(left, right).map { $0 <= 0 } ?? false
        case PredicateOperator.greaterThan: return (order(left, right) ?? 0) > 0
        case PredicateOperator.greaterThanOrEqualTo: return order(left, right).map { $0 >= 0 } ?? false
        case PredicateOperator.beginsWith:
            guard let l = text(left, c.options), let r = text(right, c.options) else { return false }
            return l.hasPrefix(r)
        case PredicateOperator.endsWith:
            guard let l = text(left, c.options), let r = text(right, c.options) else { return false }
            return l.hasSuffix(r)
        case PredicateOperator.contains:
            if let items = elements(left) { return items.contains { compare($0, right, .init(left: c.left, right: c.right, operation: PredicateOperator.equalTo, modifier: 0, options: c.options)) } }
            guard let l = text(left, c.options), let r = text(right, c.options) else { return false }
            return r.isEmpty || l.firstRange(of: r) != nil
        case PredicateOperator.in:
            if let items = elements(right) {
                return items.contains { compare(left, $0, .init(left: c.left, right: c.right, operation: PredicateOperator.equalTo, modifier: 0, options: c.options)) }
            }
            guard let l = text(left, c.options), let r = text(right, c.options) else { return false }
            return l.isEmpty || r.firstRange(of: l) != nil
        case PredicateOperator.between:
            guard let bounds = elements(right), bounds.count == 2 else { return false }
            return (order(left, bounds[0]) ?? -1) >= 0 && (order(left, bounds[1]) ?? 1) <= 0
        case PredicateOperator.like:
            guard let l = text(left, c.options), let r = text(right, c.options) else { return false }
            return wildcard(Array(l), Array(r))
        case PredicateOperator.matches:
            guard let l = text(left, c.options), let r = text(right, c.options) else { return false }
            var expression = regex_t()
            guard regcomp(&expression, "^(" + r + ")$", REG_EXTENDED | REG_NOSUB) == 0 else { return false }
            defer { regfree(&expression) }
            return regexec(&expression, l, 0, nil, 0) == 0
        default:
            return false
        }
    }

    /// LIKE: * matches any run of characters, ? any one.
    private static func wildcard(_ text: [Character], _ pattern: [Character]) -> Bool {
        guard let first = pattern.first else { return text.isEmpty }
        if first == "*" {
            for index in 0...text.count where wildcard(Array(text[index...]), Array(pattern.dropFirst())) { return true }
            return false
        }
        guard let c = text.first, first == "?" || first == c else { return false }
        return wildcard(Array(text.dropFirst()), Array(pattern.dropFirst()))
    }
}

// MARK: - Classes

/// A predicate object's tree.
final class PredicateStorage {
    let node: PredicateNode
    init(_ node: PredicateNode) { self.node = node }
}

final class ExpressionStorage {
    let node: ExpressionNode
    init(_ node: ExpressionNode) { self.node = node }
}

enum Predicates {
    nonisolated(unsafe) static var predicateClass: Class!
    nonisolated(unsafe) static var comparisonClass: Class!
    nonisolated(unsafe) static var compoundClass: Class!
    nonisolated(unsafe) static var trueClass: Class!
    nonisolated(unsafe) static var falseClass: Class!
    nonisolated(unsafe) static var blockClass: Class!
    nonisolated(unsafe) static var expressionClass: Class!

    static func node(_ object: id?) -> PredicateNode {
        Storage.get(object, as: PredicateStorage.self)?.node ?? .truth(true)
    }

    static func expressionNode(_ object: id?) -> ExpressionNode {
        Storage.get(object, as: ExpressionStorage.self)?.node ?? .constant(nil)
    }

    /// An autoreleased object for a tree, of the class Darwin uses for it.
    static func object(_ node: PredicateNode) -> id {
        let cls: Class
        switch node {
        case .truth(let value): cls = value ? trueClass : falseClass
        case .comparison: cls = comparisonClass
        case .compound: cls = compoundClass
        case .block: cls = blockClass
        }
        let object = Storage.allocate(UnsafeMutableRawPointer(cls))!
        Storage.set(object, PredicateStorage(node))
        return ObjC.autorelease(object)!
    }

    static func expression(_ node: ExpressionNode) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(expressionClass))!
        Storage.set(object, ExpressionStorage(node))
        return ObjC.autorelease(object)!
    }

    static func parse(_ format: String, _ arguments: PredicateArguments) -> id {
        var parser = PredicateParser(format, arguments: arguments)
        return object(parser.parse())
    }
}

/// NSPredicate.
@ObjCClass("NSPredicate")
public class NSPredicate: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Predicates.predicateClass = cls.storage
        cls.addMethod("predicateWithFormat:", types: "@24@0:8@16",
                      implementation: variadicEntry(perry_imp_predicateWithFormat), isClassMethod: true)
    }

    var node: PredicateNode { Predicates.node(objcObject) }

    @ObjCClassMethod("predicateWithFormat:argumentArray:")
    static func predicate(format: String, argumentArray: ObjCObject?) -> ObjCObject {
        ObjCObject(Predicates.parse(format, .array(argumentArray.map { Arrays.elements($0.objcObject) } ?? [])))
    }

    /// A Darwin va_list is a pointer to the argument slots.
    @ObjCClassMethod("predicateWithFormat:arguments:", types: "@32@0:8@16*24")
    static func predicate(format: String, arguments: UnsafeRawPointer?) -> ObjCObject {
        guard let arguments else { return ObjCObject(Predicates.parse(format, .array([]))) }
        return ObjCObject(Predicates.parse(format, .variadic(DarwinArguments(arguments))))
    }

    @ObjCClassMethod("predicateWithValue:")
    static func predicate(value: Bool) -> ObjCObject { ObjCObject(Predicates.object(.truth(value))) }

    @ObjCClassMethod("predicateWithBlock:")
    static func predicate(block: ObjCObject?) -> ObjCObject? {
        guard let reference = BlockReference(block?.objcObject) else { return nil }
        return ObjCObject(Predicates.object(.block(reference)))
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Predicates.predicateClass)
    }

    @ObjCMethod("predicateFormat") func predicateFormat() -> String { PredicateFormat.predicate(node) }
    @ObjCMethod("description") func description() -> String { PredicateFormat.predicate(node) }

    @ObjCMethod("evaluateWithObject:")
    func evaluate(with object: ObjCObject?) -> Bool { PredicateEvaluation.evaluate(node, object?.objcObject) }

    @ObjCMethod("evaluateWithObject:substitutionVariables:")
    func evaluate(with object: ObjCObject?, substitutionVariables: ObjCObject?) -> Bool {
        PredicateEvaluation.evaluate(node, object?.objcObject, bindings: substitutionVariables?.objcObject)
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSPredicate { self }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other else { return false }
        return other.objcObject == objcObject
            || (other.is(NSPredicate.self) && Strings.value(of: ObjC.send(other.objcObject, ObjC.selector("predicateFormat"))) == predicateFormat())
    }

    @ObjCMethod("hash") func hash() -> UInt { Strings.hash(predicateFormat()) }
}

@ObjCClass("NSTruePredicate")
public class NSTruePredicate: NSPredicate {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { Predicates.trueClass = cls.storage }
}

/// predicateWithBlock:'s predicates.
@ObjCClass("NSBlockPredicate")
public class NSBlockPredicate: NSPredicate {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { Predicates.blockClass = cls.storage }
}

@ObjCClass("NSFalsePredicate")
public class NSFalsePredicate: NSPredicate {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { Predicates.falseClass = cls.storage }
}

/// NSComparisonPredicate.
@ObjCClass("NSComparisonPredicate")
public class NSComparisonPredicate: NSPredicate {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { Predicates.comparisonClass = cls.storage }

    private var comparison: PredicateNode.Comparison? {
        if case .comparison(let c) = node { return c }
        return nil
    }

    @ObjCClassMethod("predicateWithLeftExpression:rightExpression:modifier:type:options:")
    static func predicate(left: ObjCObject, right: ObjCObject, modifier: UInt, type: UInt, options: UInt) -> ObjCObject {
        ObjCObject(Predicates.object(.comparison(.init(left: Predicates.expressionNode(left.objcObject),
                                                        right: Predicates.expressionNode(right.objcObject),
                                                        operation: type, modifier: modifier, options: options))))
    }

    @ObjCMethod("leftExpression")
    func leftExpression() -> ObjCObject? { comparison.map { ObjCObject(Predicates.expression($0.left)) } }
    @ObjCMethod("rightExpression")
    func rightExpression() -> ObjCObject? { comparison.map { ObjCObject(Predicates.expression($0.right)) } }
    @ObjCMethod("predicateOperatorType") func predicateOperatorType() -> UInt { comparison?.operation ?? 0 }
    @ObjCMethod("comparisonPredicateModifier") func comparisonPredicateModifier() -> UInt { comparison?.modifier ?? 0 }
    @ObjCMethod("options") func options() -> UInt { comparison?.options ?? 0 }
}

/// NSCompoundPredicate.
@ObjCClass("NSCompoundPredicate")
public class NSCompoundPredicate: NSPredicate {
    override public class func didDefineObjCClass(_ cls: ObjCClass) { Predicates.compoundClass = cls.storage }

    private static func make(_ type: UInt, _ subpredicates: ObjCObject?) -> ObjCObject {
        let nodes = (subpredicates.map { Arrays.elements($0.objcObject) } ?? []).map(Predicates.node)
        return ObjCObject(Predicates.object(.compound(type, nodes)))
    }

    @ObjCClassMethod("andPredicateWithSubpredicates:")
    static func and(_ subpredicates: ObjCObject?) -> ObjCObject { make(CompoundType.and, subpredicates) }
    @ObjCClassMethod("orPredicateWithSubpredicates:")
    static func or(_ subpredicates: ObjCObject?) -> ObjCObject { make(CompoundType.or, subpredicates) }

    @ObjCClassMethod("notPredicateWithSubpredicate:")
    static func not(_ subpredicate: ObjCObject) -> ObjCObject {
        ObjCObject(Predicates.object(.compound(CompoundType.not, [Predicates.node(subpredicate.objcObject)])))
    }

    @ObjCMethod("compoundPredicateType")
    func compoundPredicateType() -> UInt {
        if case .compound(let type, _) = node { return type }
        return 0
    }

    @ObjCMethod("subpredicates")
    func subpredicates() -> ObjCObject {
        guard case .compound(_, let parts) = node else { return ObjCObject(Arrays.autoreleased([])) }
        return ObjCObject(Arrays.autoreleased(parts.map(Predicates.object)))
    }
}

/// NSExpression.
@ObjCClass("NSExpression")
public class NSExpression: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Predicates.expressionClass = cls.storage
    }

    private var node: ExpressionNode { Predicates.expressionNode(objcObject) }

    @ObjCClassMethod("expressionForKeyPath:")
    static func keyPath(_ path: String) -> ObjCObject { ObjCObject(Predicates.expression(.keyPath(path))) }

    @ObjCClassMethod("expressionForConstantValue:")
    static func constant(_ value: ObjCObject?) -> ObjCObject { ObjCObject(Predicates.expression(.constant(value))) }

    @ObjCClassMethod("expressionForFunction:arguments:")
    static func function(_ name: String, arguments: ObjCObject?) -> ObjCObject {
        let nodes = (arguments.map { Arrays.elements($0.objcObject) } ?? []).map(Predicates.expressionNode)
        return ObjCObject(Predicates.expression(.function(name, nodes)))
    }

    @ObjCMethod("function")
    func function() -> String? {
        if case .function(let name, _) = node { return name }
        return nil
    }

    @ObjCMethod("arguments")
    func arguments() -> ObjCObject? {
        guard case .function(_, let arguments) = node else { return nil }
        return ObjCObject(Arrays.autoreleased(arguments.map(Predicates.expression)))
    }

    @ObjCClassMethod("expressionForEvaluatedObject")
    static func evaluatedObject() -> ObjCObject { ObjCObject(Predicates.expression(.evaluatedObject)) }

    @ObjCClassMethod("expressionForAggregate:")
    static func aggregate(_ expressions: ObjCObject?) -> ObjCObject {
        let nodes = (expressions.map { Arrays.elements($0.objcObject) } ?? []).map(Predicates.expressionNode)
        return ObjCObject(Predicates.expression(.aggregate(nodes)))
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Predicates.expressionClass)
    }

    @ObjCMethod("expressionType") func expressionType() -> UInt { node.type }

    @ObjCMethod("keyPath")
    func keyPath() -> String? {
        if case .keyPath(let path) = node { return path }
        return nil
    }

    @ObjCMethod("constantValue")
    func constantValue() -> ObjCObject? {
        if case .constant(let value) = node { return value }
        return nil
    }

    /// An aggregate's expressions.
    @ObjCMethod("collection")
    func collection() -> ObjCObject? {
        guard case .aggregate(let elements) = node else { return nil }
        return ObjCObject(Arrays.autoreleased(elements.map(Predicates.expression)))
    }

    @ObjCMethod("expressionValueWithObject:context:")
    func value(with object: ObjCObject?, context: ObjCObject?) -> ObjCObject? {
        PredicateEvaluation.value(node, object?.objcObject).map(ObjCObject.init)
    }

    @ObjCMethod("description") func description() -> String { PredicateFormat.expression(node) }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> NSExpression { self }
}

// MARK: - Variadic methods

@c
public func perry_foundation_predicateWithFormat(_ cls: id?, _ cmd: SEL?, _ format: id?,
                                                 _ arguments: UnsafeRawPointer?) -> id? {
    guard let arguments else { return nil }
    return Predicates.parse(Strings.value(of: format) ?? "", .variadic(DarwinArguments(arguments)))
}

/// Filtering collections with predicates.
@ObjCCategory("PredicateFiltering")
extension NSArray {
    @ObjCMethod("filteredArrayUsingPredicate:")
    func filtered(using predicate: NSPredicate) -> ObjCObject {
        ObjCObject(Arrays.autoreleased(Arrays.elements(objcObject).filter { predicate.evaluate(with: ObjCObject($0)) }))
    }

    /// For NSMutableArray: keeps the elements the predicate accepts.
    @ObjCMethod("filterUsingPredicate:")
    func filter(using predicate: NSPredicate) {
        let kept = Arrays.elements(objcObject).filter { predicate.evaluate(with: ObjCObject($0)) }
        _ = ObjC.send(objcObject, ObjC.selector("removeAllObjects"))
        for element in kept { _ = ObjC.send(objcObject, ObjC.selector("addObject:"), element) }
    }
}

@ObjCCategory("SetPredicateFiltering")
extension NSSet {
    @ObjCMethod("filteredSetUsingPredicate:")
    func filtered(using predicate: NSPredicate) -> ObjCObject {
        ObjCObject(Sets.autoreleased(Sets.elements(objcObject).filter { predicate.evaluate(with: ObjCObject($0)) }))
    }
}
