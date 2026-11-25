import PerryObjCMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros: [String: MacroSpec] = ["DarwinC": MacroSpec(type: DarwinCMacro.self)]

private func expect(_ source: String, expands expanded: String, sourceLocation: SourceLocation = #_sourceLocation) {
    assertMacroExpansion(source, expandedSource: expanded, macroSpecs: macros) { failure in
        Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
    }
}

@Suite struct DarwinCMacroTests {

    @Test("QuickDraw's Point is one word on ppc, and passes through elsewhere")
    func point() {
        expect("""
            @DarwinC("_EqualPt")
            public func EqualPt(_ a: Point, _ b: Point) -> Boolean { 0 }
            """, expands: """
            public func EqualPt(_ a: Point, _ b: Point) -> Boolean { 0 }

            #if arch(powerpc)
            @c(_EqualPt) public func __darwin_EqualPt(_ a0_w0: UInt32, _ a1_w0: UInt32) -> Boolean {
                EqualPt(PPCWords.load(Point.self, [a0_w0]), PPCWords.load(Point.self, [a1_w0]))
            }
            #else
            @c(_EqualPt) public func __darwin_EqualPt(_ a0: Point, _ a1: Point) -> Boolean.ObjCResultType {
                Boolean.objCResult(EqualPt(a0, a1).objCReturnValue())
            }
            #endif

            @c(perry_native_EqualPt) public func __native_EqualPt(_ a0: Point, _ a1: Point) -> Boolean {
                EqualPt(a0, a1)
            }
            """)
    }

    @Test("A pointer to a Rect is a word; a Point after it is one more")
    func pointAfterPointer() {
        expect("""
            @DarwinC("_PinRect")
            public func PinRect(_ rect: UnsafePointer<Rect>?, _ point: Point) -> Int32 { 0 }
            """, expands: """
            public func PinRect(_ rect: UnsafePointer<Rect>?, _ point: Point) -> Int32 { 0 }

            #if arch(powerpc)
            @c(_PinRect) public func __darwin_PinRect(_ a0: UnsafePointer<Rect>?, _ a1_w0: UInt32) -> Int32 {
                PinRect(a0, PPCWords.load(Point.self, [a1_w0]))
            }
            #else
            @c(_PinRect) public func __darwin_PinRect(_ a0: UnsafePointer<Rect>?, _ a1: Point) -> Int32 {
                PinRect(a0, a1)
            }
            #endif

            @c(perry_native_PinRect) public func __native_PinRect(_ a0: UnsafePointer<Rect>?, _ a1: Point) -> Int32 {
                PinRect(a0, a1)
            }
            """)
    }

    @Test("A Rect by value is two words on ppc")
    func rect() {
        expect("""
            @DarwinC("_ShowRect")
            func ShowRect(_ rect: Rect, _ flag: Int32) {}
            """, expands: """
            func ShowRect(_ rect: Rect, _ flag: Int32) {}

            #if arch(powerpc)
            @c(_ShowRect) func __darwin_ShowRect(_ a0_w0: UInt32, _ a0_w1: UInt32, _ a1: Int32) {
                ShowRect(PPCWords.load(Rect.self, [a0_w0, a0_w1]), a1)
            }
            #else
            @c(_ShowRect) func __darwin_ShowRect(_ a0: Rect, _ a1: Int32) {
                ShowRect(a0, a1)
            }
            #endif

            @c(perry_native_ShowRect) func __native_ShowRect(_ a0: Rect, _ a1: Int32) {
                ShowRect(a0, a1)
            }
            """)
    }

    @Test("Past r10 the loader moves them, by their encodings")
    func pastTheRegisters() {
        expect("""
            @DarwinC("_FrameRects")
            func FrameRects(_ a: Rect, _ b: Rect, _ c: Rect, _ d: Rect, _ e: Point) {}
            """, expands: """
            func FrameRects(_ a: Rect, _ b: Rect, _ c: Rect, _ d: Rect, _ e: Point) {}

            #if arch(powerpc)
            @c(perry_ppc_moved_FrameRects) func __darwin_FrameRects(_ a0: Rect, _ a1: Rect, _ a2: Rect, _ a3: Rect, _ a4: Point) {
                FrameRects(a0, a1, a2, a3, a4)
            }
            @c(perry_ppc_types_FrameRects) func __darwin_types_FrameRects() -> UnsafePointer<CChar>? {
                PPCWords.cString("v" + "{Rect=ssss}" + "{Rect=ssss}" + "{Rect=ssss}" + "{Rect=ssss}" + "{Point=ss}")
            }
            #else
            @c(_FrameRects) func __darwin_FrameRects(_ a0: Rect, _ a1: Rect, _ a2: Rect, _ a3: Rect, _ a4: Point) {
                FrameRects(a0, a1, a2, a3, a4)
            }
            #endif

            @c(perry_native_FrameRects) func __native_FrameRects(_ a0: Rect, _ a1: Rect, _ a2: Rect, _ a3: Rect, _ a4: Point) {
                FrameRects(a0, a1, a2, a3, a4)
            }
            """)
    }
}
