import PerryObjCMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros: [String: MacroSpec] = [
    "ObjCClass": MacroSpec(type: ObjCClassMacro.self),
    "ObjCMethod": MacroSpec(type: ObjCMethodMacro.self),
    "ObjCClassMethod": MacroSpec(type: ObjCMethodMacro.self),
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
                func character(at index: UInt) -> UInt16 { 0 }
                func initialize(capacity: UInt) -> Self { self }
                func release() {}
                static func string(_ cls: ObjCClass, capacity: UInt) -> NSMutableString? { nil }

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
                func frame() -> Rect { Rect() }

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

                @ObjCMethod("lastObject")
                func last() -> NSObject?
            }
            """, expands: """
            class NSMutableArray: NSArray {
                func insert(_ object: NSObject) {}
                static func count() -> UInt { 0 }
                func describe() async -> String { "" }
                func last() -> NSObject?
            }
            """, diagnostics: [
                DiagnosticSpec(message: "selector 'insertObject:atIndex:' takes 2 arguments, but the function takes 1",
                               line: 3, column: 16),
                DiagnosticSpec(message: "@ObjCMethod applies to instance methods; use @ObjCClassMethod",
                               line: 5, column: 5),
                DiagnosticSpec(message: "Objective-C methods cannot be async or throw", line: 9, column: 18),
                DiagnosticSpec(message: "an Objective-C method needs a body: it implements the selector",
                               line: 12, column: 10),
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
