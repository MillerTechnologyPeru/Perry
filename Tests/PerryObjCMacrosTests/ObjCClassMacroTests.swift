import PerryObjCMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros: [String: MacroSpec] = [
    "ObjCClass": MacroSpec(type: ObjCClassMacro.self),
    "ObjCWrapper": MacroSpec(type: ObjCWrapperMacro.self),
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

    @Test("@ObjCWrapper names a class another library defines, and only calls it")
    func wrapper() {
        expect("""
            @ObjCWrapper("NSBundle")
            class NSBundle: NSObject {
                @ObjCClassMethod("mainBundle")
                static func main() -> NSBundle

                @ObjCMethod("bundlePath")
                func path() -> String { "" }
            }
            """, expands: """
            class NSBundle: NSObject {
                static func main() -> NSBundle {
                    typealias Message = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> NSBundle.ObjCType
                    let message = unsafeBitCast(ObjCRuntime.msgSend, to: Message.self)
                    return NSBundle(objCReturnValue: message(self.objCClass.pointer, ObjCRuntime.selector("mainBundle")))
                }
                func path() -> String {
                    ""
                }

                override class var objCClassName: String {
                    "NSBundle"
                }

                override class var objCSuperclassName: String? {
                    NSObject.objCClassName
                }
            }
            """, diagnostics: [
                DiagnosticSpec(message: "a wrapper's methods call the class's and have no body; implement methods with @ObjCClass or @ObjCCategory",
                               line: 6, column: 5),
            ])
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

@Suite struct ObjCProtocolMacroTests {

    private let specs: [String: MacroSpec] = [
        "ObjCProtocol": MacroSpec(type: ObjCProtocolMacro.self),
        "ObjCRequired": MacroSpec(type: ObjCRequirementMacro.self),
        "ObjCOptional": MacroSpec(type: ObjCRequirementMacro.self),
    ]

    @Test("@ObjCProtocol makes a wrapper that sends each requirement, and defaults for optional ones")
    func wrapper() {
        assertMacroExpansion("""
            @ObjCProtocol("UIWindowSceneDelegate")
            public protocol UIWindowSceneDelegate: UISceneDelegate {
                @ObjCRequired("windowScene")
                func windowScene() -> UIWindowScene

                @ObjCOptional("sceneDidBecomeActive:")
                func sceneDidBecomeActive(_ scene: UIScene)

                @ObjCOptional("shouldConnect:")
                func shouldConnect(_ scene: UIScene) -> Bool?
            }
            """, expandedSource: """
            public protocol UIWindowSceneDelegate: UISceneDelegate {
                func windowScene() -> UIWindowScene
                func sceneDidBecomeActive(_ scene: UIScene)
                func shouldConnect(_ scene: UIScene) -> Bool?
            }

            /// Any object that conforms to UIWindowSceneDelegate, called through messages.
            open class AnyUIWindowSceneDelegate: AnyUISceneDelegate, UIWindowSceneDelegate {
                override public class var objCProtocolName: String {
                    "UIWindowSceneDelegate"
                }

                public func windowScene() -> UIWindowScene {
                    typealias Message = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UIWindowScene.ObjCType
                    let message = unsafeBitCast(ObjCRuntime.msgSend, to: Message.self)
                    return UIWindowScene(objCReturnValue: message(objcObject, ObjCRuntime.selector("windowScene")))
                }

                public func sceneDidBecomeActive(_ scene: UIScene) {
                    guard responds(to: "sceneDidBecomeActive:") else {
                        return
                    }
                    typealias Message = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UIScene.ObjCType) -> Void
                    let message = unsafeBitCast(ObjCRuntime.msgSend, to: Message.self)
                    message(objcObject, ObjCRuntime.selector("sceneDidBecomeActive:"), scene.objCArgument())
                }

                public func shouldConnect(_ scene: UIScene) -> Bool? {
                    guard responds(to: "shouldConnect:") else {
                        return nil
                    }
                    typealias Message = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UIScene.ObjCType) -> Bool.ObjCType
                    let message = unsafeBitCast(ObjCRuntime.msgSend, to: Message.self)
                    return objCOptionalResult(message(objcObject, ObjCRuntime.selector("shouldConnect:"), scene.objCArgument()), as: Bool.self, owned: false)
                }

                override public class func defineObjCProtocol() {
                    ObjCRuntime.defineProtocol(named: "UIWindowSceneDelegate", adopting: [AnyUISceneDelegate.objCProtocolName], methods: [
                        ObjCProtocolMethod("windowScene", types: ObjCTypeEncoding.method(returning: UIWindowScene.self, arguments: []), isRequired: true),
                        ObjCProtocolMethod("sceneDidBecomeActive:", types: ObjCTypeEncoding.method(returning: nil, arguments: [UIScene.self]), isRequired: false),
                        ObjCProtocolMethod("shouldConnect:", types: ObjCTypeEncoding.method(returning: Bool.self, arguments: [UIScene.self]), isRequired: false),
                    ])
                }
            }

            /// Optional methods do nothing unless a conformer implements them.
            extension UIWindowSceneDelegate {
                public func sceneDidBecomeActive(_ scene: UIScene) {
                }
                public func shouldConnect(_ scene: UIScene) -> Bool? {
                    nil
                }
            }
            """, macroSpecs: specs) { failure in
            Issue.record(Comment(rawValue: failure.message))
        }
    }

    @Test("Optional results must be Optional, and requirements must be instance methods")
    func diagnostics() {
        assertMacroExpansion("""
            @ObjCProtocol("Source")
            protocol Source {
                @ObjCOptional("count")
                func count() -> Int

                @ObjCRequired("shared")
                static func shared() -> NSObject
            }
            """, expandedSource: """
            protocol Source {
                func count() -> Int
                static func shared() -> NSObject
            }

            /// Any object that conforms to Source, called through messages.
            class AnySource: ObjCProtocolObject, Source {
                override class var objCProtocolName: String {
                    "Source"
                }

                override class func defineObjCProtocol() {
                    ObjCRuntime.defineProtocol(named: "Source", adopting: [], methods: [])
                }
            }
            """, diagnostics: [
                DiagnosticSpec(message: "protocol class methods are not supported yet", line: 6, column: 5),
                DiagnosticSpec(message: "an optional method returns an Optional, which is nil when the object does not implement it",
                               line: 4, column: 21),
            ], macroSpecs: specs) { failure in
            Issue.record(Comment(rawValue: failure.message))
        }
    }
}
