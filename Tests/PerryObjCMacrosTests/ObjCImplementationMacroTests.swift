import PerryObjCMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros: [String: MacroSpec] = [
    "ObjCImplementation": MacroSpec(type: ObjCImplementationMacro.self, conformances: ["ObjCMethodTable"]),
    "ObjCMethod": MacroSpec(type: ObjCMethodMacro.self),
    "ObjCClassMethod": MacroSpec(type: ObjCMethodMacro.self),
]

private func expect(_ source: String, expands expanded: String, diagnostics: [DiagnosticSpec] = [],
                     sourceLocation: SourceLocation = #_sourceLocation) {
    assertMacroExpansion(source, expandedSource: expanded, diagnostics: diagnostics, macroSpecs: macros) { failure in
        Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
    }
}

@Suite struct ObjCImplementationMacroTests {

    @Test("Methods get C thunks with _cmd and type encodings")
    func registration() {
        expect("""
            @ObjCImplementation
            enum StringMethods {
                @ObjCMethod("characterAtIndex:")
                static func character(_ string: id?, at index: UInt) -> UInt16 { 0 }

                @ObjCClassMethod("stringWithUTF8String:")
                static func string(_ cls: id?, _ bytes: UnsafePointer<CChar>?) -> id? { nil }

                @ObjCMethod("setFlag:")
                static func set(_ object: id?, flag: Bool) {}

                static func helper() {}
            }
            """, expands: """
            enum StringMethods {
                static func character(_ string: id?, at index: UInt) -> UInt16 { 0 }
                static func string(_ cls: id?, _ bytes: UnsafePointer<CChar>?) -> id? { nil }
                static func set(_ object: id?, flag: Bool) {}

                static func helper() {}

                static func register(_ registrar: some ObjCMethodRegistrar) {
                    registrar.addMethod("characterAtIndex:", types: "S24@0:8Q16", implementation: unsafeBitCast({ (receiver: id?, _: UnsafeRawPointer?, a1: UInt) -> UInt16 in
                                StringMethods.character(receiver, at: a1)
                            } as @convention(c) (id?, UnsafeRawPointer?, UInt) -> UInt16, to: UnsafeRawPointer.self), isClassMethod: false)
                    registrar.addMethod("stringWithUTF8String:", types: "@24@0:8r*16", implementation: unsafeBitCast({ (receiver: id?, _: UnsafeRawPointer?, a1: UnsafePointer<CChar>?) -> id? in
                                StringMethods.string(receiver, a1)
                            } as @convention(c) (id?, UnsafeRawPointer?, UnsafePointer<CChar>?) -> id?, to: UnsafeRawPointer.self), isClassMethod: true)
                    registrar.addMethod("setFlag:", types: "v20@0:8B16", implementation: unsafeBitCast({ (receiver: id?, _: UnsafeRawPointer?, a1: Bool) -> Void in
                                StringMethods.set(receiver, flag: a1)
                            } as @convention(c) (id?, UnsafeRawPointer?, Bool) -> Void, to: UnsafeRawPointer.self), isClassMethod: false)
                }
            }

            extension StringMethods: ObjCMethodTable {
            }
            """)
    }

    @Test("Explicit type encodings are used as written")
    func explicitTypes() {
        expect("""
            @ObjCImplementation
            enum Methods {
                @ObjCMethod("rect", types: "{CGRect=dddd}16@0:8")
                static func rect(_ object: id?) -> Rect { Rect() }
            }
            """, expands: """
            enum Methods {
                static func rect(_ object: id?) -> Rect { Rect() }

                static func register(_ registrar: some ObjCMethodRegistrar) {
                    registrar.addMethod("rect", types: "{CGRect=dddd}16@0:8", implementation: unsafeBitCast({ (receiver: id?, _: UnsafeRawPointer?) -> Rect in
                                Methods.rect(receiver)
                            } as @convention(c) (id?, UnsafeRawPointer?) -> Rect, to: UnsafeRawPointer.self), isClassMethod: false)
                }
            }

            extension Methods: ObjCMethodTable {
            }
            """)
    }

    @Test("Selector and signature mismatches are compile errors")
    func diagnostics() {
        expect("""
            @ObjCImplementation
            enum Methods {
                @ObjCMethod("insertObject:atIndex:")
                static func insert(_ array: id?, _ object: id?) {}

                @ObjCMethod("frame")
                static func frame(_ view: id?) -> Rect { Rect() }

                @ObjCMethod("count")
                func count(_ array: id?) -> UInt { 0 }
            }
            """, expands: """
            enum Methods {
                static func insert(_ array: id?, _ object: id?) {}
                static func frame(_ view: id?) -> Rect { Rect() }
                func count(_ array: id?) -> UInt { 0 }

                static func register(_ registrar: some ObjCMethodRegistrar) {

                }
            }

            extension Methods: ObjCMethodTable {
            }
            """, diagnostics: [
                DiagnosticSpec(message: "selector 'insertObject:atIndex:' takes 2 arguments, but the function takes 1 after the receiver",
                               line: 4, column: 23),
                DiagnosticSpec(message: "cannot encode return type 'Rect'; pass types:", line: 7, column: 39),
                DiagnosticSpec(message: "Objective-C methods must be static functions", line: 10, column: 10),
            ])
    }
}
