import PerryObjCMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros: [String: MacroSpec] = [
    "ObjCClass": MacroSpec(type: ObjCClassMacro.self, conformances: ["AnyObjCObject"]),
    "ObjCMethod": MacroSpec(type: ObjCMethodMacro.self),
    "ObjCClassMethod": MacroSpec(type: ObjCMethodMacro.self),
    "ObjCImplementation": MacroSpec(type: ObjCImplementationMacro.self),
]

private func expect(_ source: String, expands expanded: String, diagnostics: [DiagnosticSpec] = [],
                     sourceLocation: SourceLocation = #_sourceLocation) {
    assertMacroExpansion(source, expandedSource: expanded, diagnostics: diagnostics, macroSpecs: macros) { failure in
        Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
    }
}

@Suite struct ObjCMacroTests {

    @Test("@ObjCClass declares a wrapper")
    func wrapper() {
        expect("""
            @ObjCClass("NSString")
            public struct NSString {}
            """, expands: """
            public struct NSString {

                public let objcHolder: ObjCObjectHolder

                public init(objcHolder: ObjCObjectHolder) {
                    self.objcHolder = objcHolder
                }

                public static var objCClassName: String {
                    "NSString"
                }
            }

            extension NSString: AnyObjCObject {
            }
            """)
    }

    @Test("Methods without a body send the message")
    func sending() {
        expect("""
            struct NSString {
                @ObjCMethod("characterAtIndex:")
                func character(at index: UInt) -> UInt16

                @ObjCMethod("copy")
                func copy() -> NSString

                @ObjCMethod("getCharacters:")
                func getCharacters(_ buffer: UnsafeMutablePointer<UInt16>)

                @ObjCMethod("initWithString:")
                init?(string: String?)

                @ObjCClassMethod("string")
                static func empty() -> NSString
            }
            """, expands: """
            struct NSString {
                func character(at index: UInt) -> UInt16 {
                    typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UInt.ObjCType) -> UInt16.ObjCType
                    let send = unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)
                    return UInt16(objCReturnValue: send(self.objcObject, ObjCRuntime.selector("characterAtIndex:"), index.objCArgument()))
                }
                func copy() -> NSString {
                    typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> NSString.ObjCType
                    let send = unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)
                    return NSString(objCOwned: send(self.objcObject, ObjCRuntime.selector("copy")))
                }
                func getCharacters(_ buffer: UnsafeMutablePointer<UInt16>) {
                    typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeMutablePointer<UInt16>.ObjCType) -> Void
                    let send = unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)
                    send(self.objcObject, ObjCRuntime.selector("getCharacters:"), buffer.objCArgument())
                }
                init?(string: String?) {
                    typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Optional<String>.ObjCType) -> UnsafeMutableRawPointer?
                    let send = unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)
                    let allocated = unsafeBitCast(ObjCRuntime.msgSend, to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?).self)(Self.objCClass.pointer, ObjCRuntime.selector("alloc"))
                    let result = send(allocated, ObjCRuntime.selector("initWithString:"), string.objCArgument())
                    guard let result else {
                        return nil
                    }
                    self.init(objcHolder: ObjCObjectHolder(adopting: result))
                }
                static func empty() -> NSString {
                    typealias Send = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> NSString.ObjCType
                    let send = unsafeBitCast(ObjCRuntime.msgSend, to: Send.self)
                    return NSString(objCReturnValue: send(Self.objCClass.pointer, ObjCRuntime.selector("string")))
                }
            }
            """)
    }

    @Test("Implementations get thunks that convert the receiver and arguments")
    func implementing() {
        expect("""
            @ObjCImplementation("registerCore")
            extension NSString {
                @ObjCMethod("stringByAppendingString:")
                func appending(_ other: String) -> String { "" }

                @ObjCMethod("initWithString:")
                func initialize(string: String?) -> Self? { self }

                @ObjCMethod("dealloc")
                func dealloc() {}

                @ObjCClassMethod("alloc")
                static func alloc(_ cls: ObjCClass) -> NSString? { nil }

                func helper() {}
            }
            """, expands: """
            extension NSString {
                func appending(_ other: String) -> String {
                    ""
                }
                func initialize(string: String?) -> Self? {
                    self
                }
                func dealloc() {}
                static func alloc(_ cls: ObjCClass) -> NSString? {
                    nil
                }

                func helper() {}

                static func registerCore(_ registrar: any ObjCMethodRegistrar) {
                    registrar.addMethod("stringByAppendingString:", types: ObjCTypeEncoding.method(returning: String.self, arguments: [String.self]), implementation: unsafeBitCast({ (receiver: UnsafeMutableRawPointer?, _: UnsafeRawPointer?, a0: String.ObjCType) -> String.ObjCType in
                                let this = NSString(objcHolder: ObjCObjectHolder(retaining: receiver!));
                                return this.appending(String(objCArgument: a0)).objCReturnValue()
                            } as @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, String.ObjCType) -> String.ObjCType, to: UnsafeRawPointer.self), isClassMethod: false)
                    registrar.addMethod("initWithString:", types: ObjCTypeEncoding.method(returning: Optional<NSString>.self, arguments: [Optional<String>.self]), implementation: unsafeBitCast({ (receiver: UnsafeMutableRawPointer?, _: UnsafeRawPointer?, a0: Optional<String>.ObjCType) -> Optional<NSString>.ObjCType in
                                let this = NSString(objcHolder: ObjCObjectHolder(adopting: receiver!));
                                return this.initialize(string: Optional<String>(objCArgument: a0)).objCOwnedReturnValue()
                            } as @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Optional<String>.ObjCType) -> Optional<NSString>.ObjCType, to: UnsafeRawPointer.self), isClassMethod: false)
                    registrar.addMethod("dealloc", types: ObjCTypeEncoding.method(returning: nil, arguments: []), implementation: unsafeBitCast({ (receiver: UnsafeMutableRawPointer?, _: UnsafeRawPointer?) -> Void in
                                let this = NSString(objcHolder: ObjCObjectHolder(borrowing: receiver!));
                                this.dealloc()
                            } as @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void, to: UnsafeRawPointer.self), isClassMethod: false)
                    registrar.addMethod("alloc", types: ObjCTypeEncoding.method(returning: Optional<NSString>.self, arguments: []), implementation: unsafeBitCast({ (receiver: UnsafeMutableRawPointer?, _: UnsafeRawPointer?) -> Optional<NSString>.ObjCType in
                                return NSString.alloc(ObjCClass(receiver!)).objCOwnedReturnValue()
                            } as @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Optional<NSString>.ObjCType, to: UnsafeRawPointer.self), isClassMethod: true)
                }
            }
            """)
    }

    @Test("Mismatched selectors and signatures are compile errors")
    func diagnostics() {
        expect("""
            struct NSMutableArray {
                @ObjCMethod("insertObject:atIndex:")
                func insert(_ object: ObjCObject)

                @ObjCMethod("count")
                static func count() -> UInt

                @ObjCMethod("description")
                func describe() async -> String
            }
            """, expands: """
            struct NSMutableArray {
                func insert(_ object: ObjCObject) {
                    fatalError()
                }
                static func count() -> UInt {
                    fatalError()
                }
                func describe() async -> String {
                    fatalError()
                }
            }
            """, diagnostics: [
                DiagnosticSpec(message: "selector 'insertObject:atIndex:' takes 2 arguments, but the function takes 1",
                               line: 3, column: 16),
                DiagnosticSpec(message: "@ObjCMethod applies to instance methods; use @ObjCClassMethod",
                               line: 5, column: 5),
                DiagnosticSpec(message: "Objective-C methods cannot be async or throw", line: 9, column: 18),
            ])
    }
}
