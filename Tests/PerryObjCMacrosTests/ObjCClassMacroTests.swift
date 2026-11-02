import PerryObjCMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros: [String: MacroSpec] = [
    "ObjCClass": MacroSpec(type: ObjCClassMacro.self),
    "ObjCMethod": MacroSpec(type: ObjCMethodMacro.self),
    "ObjCClassMethod": MacroSpec(type: ObjCMethodMacro.self),
    "ObjCProperty": MacroSpec(type: ObjCPropertyMacro.self),
]

private func expect(_ source: String, expands expanded: String, diagnostics: [DiagnosticSpec] = [],
                     sourceLocation: SourceLocation = #_sourceLocation) {
    assertMacroExpansion(source, expandedSource: expanded, diagnostics: diagnostics, macroSpecs: macros) { failure in
        Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
    }
}

@Suite struct ObjCClassMacroTests {

    @Test("Methods get thunks that convert the receiver, arguments and result")
    func registration() {
        expect("""
            @ObjCClass("NSMutableString")
            public class NSMutableString: NSString {
                @ObjCMethod("appendString:")
                func append(_ other: String) {}

                @ObjCMethod("characterAtIndex:")
                func character(at index: UInt) -> UInt16 { 0 }

                @ObjCMethod("initWithCapacity:")
                func initialize(capacity: UInt) -> Self { self }

                @ObjCMethod("release")
                func release() {}

                @ObjCClassMethod("stringWithCapacity:")
                static func string(_ cls: ObjCClass, capacity: UInt) -> NSMutableString? { nil }

                func helper() {}
            }
            """, expands: """
            public class NSMutableString: NSString {
                func append(_ other: String) {}
                func character(at index: UInt) -> UInt16 {
                    0
                }
                func initialize(capacity: UInt) -> Self {
                    self
                }
                func release() {}
                static func string(_ cls: ObjCClass, capacity: UInt) -> NSMutableString? {
                    nil
                }

                func helper() {}

                public override class var objCClassName: String {
                    "NSMutableString"
                }

                public override class var objCSuperclassName: String? {
                    NSString.objCClassName
                }

                public override class func registerObjCMethods(_ registrar: any ObjCMethodRegistrar) {
                    registrar.addMethod("appendString:", types: ObjCTypeEncoding.method(returning: nil, arguments: [String.self]), implementation: unsafeBitCast({ (receiver: UnsafeMutableRawPointer?, _: UnsafeRawPointer?, a0: String.ObjCType) -> Void in
                                let this = NSMutableString(objcObject: receiver!, ownership: .retain);
                                this.append(String(objCArgument: a0))
                            } as @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, String.ObjCType) -> Void, to: UnsafeRawPointer.self), isClassMethod: false)
                    registrar.addMethod("characterAtIndex:", types: ObjCTypeEncoding.method(returning: UInt16.self, arguments: [UInt.self]), implementation: unsafeBitCast({ (receiver: UnsafeMutableRawPointer?, _: UnsafeRawPointer?, a0: UInt.ObjCType) -> UInt16.ObjCType in
                                let this = NSMutableString(objcObject: receiver!, ownership: .retain);
                                return this.character(at: UInt(objCArgument: a0)).objCReturnValue()
                            } as @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UInt.ObjCType) -> UInt16.ObjCType, to: UnsafeRawPointer.self), isClassMethod: false)
                    registrar.addMethod("initWithCapacity:", types: ObjCTypeEncoding.method(returning: NSMutableString.self, arguments: [UInt.self]), implementation: unsafeBitCast({ (receiver: UnsafeMutableRawPointer?, _: UnsafeRawPointer?, a0: UInt.ObjCType) -> NSMutableString.ObjCType in
                                let this = NSMutableString(objcObject: receiver!, ownership: .adopt);
                                return this.initialize(capacity: UInt(objCArgument: a0)).objCOwnedReturnValue()
                            } as @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UInt.ObjCType) -> NSMutableString.ObjCType, to: UnsafeRawPointer.self), isClassMethod: false)
                    registrar.addMethod("release", types: ObjCTypeEncoding.method(returning: nil, arguments: []), implementation: unsafeBitCast({ (receiver: UnsafeMutableRawPointer?, _: UnsafeRawPointer?) -> Void in
                                let this = NSMutableString(objcObject: receiver!, ownership: .borrow);
                                this.release()
                            } as @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void, to: UnsafeRawPointer.self), isClassMethod: false)
                    registrar.addMethod("stringWithCapacity:", types: ObjCTypeEncoding.method(returning: Optional<NSMutableString>.self, arguments: [UInt.self]), implementation: unsafeBitCast({ (receiver: UnsafeMutableRawPointer?, _: UnsafeRawPointer?, a0: UInt.ObjCType) -> Optional<NSMutableString>.ObjCType in
                                return NSMutableString.string(ObjCClass(receiver!), capacity: UInt(objCArgument: a0)).objCReturnValue()
                            } as @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UInt.ObjCType) -> Optional<NSMutableString>.ObjCType, to: UnsafeRawPointer.self), isClassMethod: true)
                }
            }
            """)
    }

    @Test("Explicit type encodings are used as written")
    func explicitTypes() {
        expect("""
            @ObjCClass("Shape")
            class Shape: NSObject {
                @ObjCMethod("frame", types: "{CGRect=dddd}16@0:8")
                func frame() -> Rect { Rect() }
            }
            """, expands: """
            class Shape: NSObject {
                func frame() -> Rect {
                    Rect()
                }

                override class var objCClassName: String {
                    "Shape"
                }

                override class var objCSuperclassName: String? {
                    NSObject.objCClassName
                }

                override class func registerObjCMethods(_ registrar: any ObjCMethodRegistrar) {
                    registrar.addMethod("frame", types: "{CGRect=dddd}16@0:8", implementation: unsafeBitCast({ (receiver: UnsafeMutableRawPointer?, _: UnsafeRawPointer?) -> Rect.ObjCType in
                                let this = Shape(objcObject: receiver!, ownership: .retain);
                                return this.frame().objCReturnValue()
                            } as @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Rect.ObjCType, to: UnsafeRawPointer.self), isClassMethod: false)
                }
            }
            """)
    }

    @Test("Functions without a body send their message, and are not registered")
    func calls() {
        expect("""
            @ObjCClass("Shape")
            class Shape: NSObject {
                @ObjCMethod("insertObject:atIndex:")
                func insert(_ object: NSObject?, at index: UInt)

                @ObjCMethod("initWithName:")
                func initialize(name: String) -> Self?

                @ObjCClassMethod("new")
                static func new() -> Self
            }
            """, expands: """
            class Shape: NSObject {
                func insert(_ object: NSObject?, at index: UInt) {
                    typealias Message = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Optional<NSObject>.ObjCType, UInt.ObjCType) -> Void
                    let message = unsafeBitCast(ObjCRuntime.msgSend, to: Message.self)
                    message(objcObject, ObjCRuntime.selector("insertObject:atIndex:"), object.objCArgument(), index.objCArgument())
                }
                func initialize(name: String) -> Self? {
                    typealias Message = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, String.ObjCType) -> UnsafeMutableRawPointer?
                    let message = unsafeBitCast(ObjCRuntime.msgSend, to: Message.self)
                    return message(ObjCRuntime.retain(objcObject), ObjCRuntime.selector("initWithName:"), name.objCArgument()).map {
                        Self(objCOwned: $0)
                    }
                }
                static func new() -> Self {
                    typealias Message = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
                    let message = unsafeBitCast(ObjCRuntime.msgSend, to: Message.self)
                    return Self(objCOwned: message(self.objCClass.pointer, ObjCRuntime.selector("new")))
                }

                override class var objCClassName: String {
                    "Shape"
                }

                override class var objCSuperclassName: String? {
                    NSObject.objCClassName
                }

                override class func registerObjCMethods(_ registrar: any ObjCMethodRegistrar) {

                }
            }
            """)
    }

    @Test("@ObjCProperty sends the getter and setter")
    func properties() {
        expect("""
            extension NSObject {
                @ObjCProperty var tag: Int
                @ObjCProperty(getter: "isHidden", readonly: true) var hidden: Bool
                @ObjCProperty(readonly: true) static var count: UInt
            }
            """, expands: """
            extension NSObject {
                var tag: Int {
                    get {
                        typealias Message = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Int.ObjCType
                        let message = unsafeBitCast(ObjCRuntime.msgSend, to: Message.self)
                        return Int(objCReturnValue: message(objcObject, ObjCRuntime.selector("tag")))
                    }
                    set {
                        typealias Message = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int.ObjCType) -> Void
                        let message = unsafeBitCast(ObjCRuntime.msgSend, to: Message.self)
                        message(objcObject, ObjCRuntime.selector("setTag:"), newValue.objCArgument())
                    }
                }
                var hidden: Bool {
                    get {
                        typealias Message = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Bool.ObjCType
                        let message = unsafeBitCast(ObjCRuntime.msgSend, to: Message.self)
                        return Bool(objCReturnValue: message(objcObject, ObjCRuntime.selector("isHidden")))
                    }
                }
                static var count: UInt {
                    get {
                        typealias Message = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UInt.ObjCType
                        let message = unsafeBitCast(ObjCRuntime.msgSend, to: Message.self)
                        return UInt(objCReturnValue: message(self.objCClass.pointer, ObjCRuntime.selector("count")))
                    }
                }
            }
            """)
    }

    @Test("Mismatched selectors and signatures are compile errors")
    func diagnostics() {
        expect("""
            class NSMutableArray: NSArray {
                @ObjCMethod("insertObject:atIndex:")
                func insert(_ object: NSObject) {}

                @ObjCMethod("count")
                static func count() -> UInt { 0 }

                @ObjCMethod("description")
                func describe() async -> String { "" }

                @ObjCMethod("objectAtIndex:")
                func object(_: UInt) -> NSObject
            }
            """, expands: """
            class NSMutableArray: NSArray {
                func insert(_ object: NSObject) {}
                static func count() -> UInt {
                    0
                }
                func describe() async -> String {
                    ""
                }
                func object(_: UInt) -> NSObject {
                    fatalError()
                }
            }
            """, diagnostics: [
                DiagnosticSpec(message: "selector 'insertObject:atIndex:' takes 2 arguments, but the function takes 1",
                               line: 3, column: 16),
                DiagnosticSpec(message: "@ObjCMethod applies to instance methods; use @ObjCClassMethod",
                               line: 5, column: 5),
                DiagnosticSpec(message: "Objective-C methods cannot be async or throw", line: 9, column: 18),
                DiagnosticSpec(message: "name the parameter: the message send passes it", line: 12, column: 17),
            ])
    }

    @Test("@ObjCClass needs a class with a superclass")
    func classes() {
        expect("""
            @ObjCClass("Point")
            struct Point {}

            @ObjCClass("Root")
            class Root {}
            """, expands: """
            struct Point {}
            class Root {}
            """, diagnostics: [
                DiagnosticSpec(message: "@ObjCClass applies to a class", line: 1, column: 1),
                DiagnosticSpec(message: "an @ObjCClass class inherits from its Objective-C superclass's class, such as NSObject",
                               line: 5, column: 7),
            ])
    }
}

@Suite struct ObjCCategoryMacroTests {

    private let specs: [String: MacroSpec] = [
        "ObjCCategory": MacroSpec(type: ObjCCategoryMacro.self),
        "ObjCMethod": MacroSpec(type: ObjCMethodMacro.self),
    ]

    @Test("@ObjCCategory adds an extension's methods to the extended class")
    func category() {
        assertMacroExpansion("""
            @ObjCCategory("Paths")
            public extension NSString {
                @ObjCMethod("lastPathComponent")
                func lastPathComponent() -> String { "" }
            }
            """, expandedSource: """
            public extension NSString {
                func lastPathComponent() -> String {
                    ""
                }

                /// Installs the Paths category's methods into `registrar`.
                public static func registerObjCCategoryPaths(_ registrar: any ObjCMethodRegistrar) {
                    registrar.addMethod("lastPathComponent", types: ObjCTypeEncoding.method(returning: String.self, arguments: []), implementation: unsafeBitCast({ (receiver: UnsafeMutableRawPointer?, _: UnsafeRawPointer?) -> String.ObjCType in
                                let this = NSString(objcObject: receiver!, ownership: .retain);
                                return this.lastPathComponent().objCReturnValue()
                            } as @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> String.ObjCType, to: UnsafeRawPointer.self), isClassMethod: false)
                }

                /// Adds the Paths category's methods to NSString's class.
                public static func addObjCCategoryPaths() {
                    registerObjCCategoryPaths(objCClass)
                }
            }
            """, macroSpecs: specs) { failure in
            Issue.record(Comment(rawValue: failure.message))
        }
    }

    @Test("@ObjCCategory needs an extension and an identifier name")
    func diagnostics() {
        assertMacroExpansion("""
            @ObjCCategory("Loose")
            class Loose: NSObject {}

            @ObjCCategory("Two words")
            extension NSString {}
            """, expandedSource: """
            class Loose: NSObject {}
            extension NSString {}
            """, diagnostics: [
                DiagnosticSpec(message: "@ObjCCategory applies to an extension of an Objective-C class's wrapper",
                               line: 1, column: 1),
                DiagnosticSpec(message: "the category name must be a string literal that is a Swift identifier",
                               line: 4, column: 1),
            ], macroSpecs: specs) { failure in
            Issue.record(Comment(rawValue: failure.message))
        }
    }
}

@Suite struct ObjCConstantsMacroTests {

    @Test("@ObjCConstants exports strings, aliases and objects")
    func constants() {
        assertMacroExpansion("""
            @ObjCConstants
            enum Modes {
                static let NSDefaultRunLoopMode = "kCFRunLoopDefaultMode"
                static let kCFRunLoopDefaultMode = NSDefaultRunLoopMode
                static let kCFNull: UnsafeMutableRawPointer? = makeNull()
                static var notExported = 0
            }
            """, expandedSource: """
            enum Modes {
                static let NSDefaultRunLoopMode = "kCFRunLoopDefaultMode"
                static let kCFRunLoopDefaultMode = NSDefaultRunLoopMode
                static let kCFNull: UnsafeMutableRawPointer? = makeNull()
                static var notExported = 0

                static var objCConstants: [(name: String, value: ObjCConstantValue)] {
                    [
                        ("NSDefaultRunLoopMode", .string(NSDefaultRunLoopMode)),
                        ("kCFRunLoopDefaultMode", .alias("NSDefaultRunLoopMode")),
                        ("kCFNull", .object({
                                    kCFNull
                                })),
                    ]
                }

                /// NSDefaultRunLoopMode's exported object.
                static var NSDefaultRunLoopModeObject: UnsafeMutableRawPointer {
                    ObjCConstantExports.shared.object("NSDefaultRunLoopMode")
                }

                /// kCFRunLoopDefaultMode's exported object.
                static var kCFRunLoopDefaultModeObject: UnsafeMutableRawPointer {
                    ObjCConstantExports.shared.object("kCFRunLoopDefaultMode")
                }

                /// kCFNull's exported object.
                static var kCFNullObject: UnsafeMutableRawPointer {
                    ObjCConstantExports.shared.object("kCFNull")
                }
            }

            extension Modes: ObjCConstantTable {
            }
            """, macroSpecs: ["ObjCConstants": MacroSpec(type: ObjCConstantsMacro.self, conformances: ["ObjCConstantTable"])]) { failure in
            Issue.record(Comment(rawValue: failure.message))
        }
    }
}
