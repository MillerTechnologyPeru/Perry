import CPerryGeometry
import Glibc
import PerryObjCInterop

// CoreText's lines and runs, for apps that lay text out themselves: a
// frame's lines and their origins, a line's glyph runs, typesetters,
// truncated lines and run delegates. Lines break at spaces and line feeds,
// and a word wider than the frame breaks where it must. There is no
// shaping here, so a run has a glyph for each UTF-16 unit of its text, and
// draws its text as UIKit's string drawing does.

// MARK: Line breaking

enum LineBreaks {
    static func isSpace(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 || unit == 0x3000 }
    static func isLineEnd(_ unit: UInt16) -> Bool { unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029 }
    /// Ideographs and kana break anywhere.
    static func breaksAnywhere(_ unit: UInt16) -> Bool { (0x2E80...0x9FFF).contains(unit) || (0xAC00...0xD7A3).contains(unit) || (0xFF00...0xFFEF).contains(unit) }
    static func isLowSurrogate(_ unit: UInt16) -> Bool { (0xDC00..<0xE000).contains(unit) }

    static func width(_ string: NSAttributedString, _ text: [UInt16], _ start: Int, _ end: Int) -> CGFloat {
        end > start ? LineSegments(string, range: (start, end - start), text: text).width : 0
    }

    /// Where the line that starts at `start` ends, its trailing spaces and
    /// line feed with it, within `width`; at least one character.
    static func end(of string: NSAttributedString, text: [UInt16], from start: Int, limit: Int, width: CGFloat) -> Int {
        guard start < limit else { return limit }
        var accepted = start        // The end of the words that fit.
        var index = start
        while index < limit {
            if isLineEnd(text[index]) {
                // A carriage return and line feed end the line as one.
                let next = index + 1
                return text[index] == 0x0D && next < limit && text[next] == 0x0A ? next + 1 : next
            }
            // The next word: up to a space, a line end or an ideograph.
            var wordEnd = index
            if breaksAnywhere(text[wordEnd]) {
                wordEnd += 1
            } else {
                while wordEnd < limit, !isSpace(text[wordEnd]), !isLineEnd(text[wordEnd]), !breaksAnywhere(text[wordEnd]) { wordEnd += 1 }
            }
            if wordEnd > index, self.width(string, text, start, wordEnd) > width {
                if accepted > start { return accepted }
                // The word alone is too wide: as many characters as fit.
                var low = index + 1, high = wordEnd
                while low < high {
                    let middle = (low + high + 1) / 2
                    if self.width(string, text, start, middle) <= width { low = middle } else { high = middle - 1 }
                }
                while low < limit, low > start + 1, isLowSurrogate(text[low]) { low -= 1 }
                if low < limit, isLowSurrogate(text[low]) { low += 1 }
                return max(low, start + 1)
            }
            // The spaces after it go with the line, however wide.
            var spaceEnd = wordEnd
            while spaceEnd < limit, isSpace(text[spaceEnd]) { spaceEnd += 1 }
            accepted = spaceEnd
            index = spaceEnd
        }
        return limit
    }

    /// The width of the spaces and line feed a line ends with.
    static func trailingWhitespace(_ string: NSAttributedString, text: [UInt16], start: Int, end: Int) -> (width: CGFloat, trimmedEnd: Int) {
        var trimmed = end
        while trimmed > start, isSpace(text[trimmed - 1]) || isLineEnd(text[trimmed - 1]) { trimmed -= 1 }
        guard trimmed < end else { return (0, end) }
        return (width(string, text, start, end) - width(string, text, start, trimmed), trimmed)
    }
}

// MARK: Frames' lines

enum FrameLines {
    static func paragraphStyle(_ string: NSAttributedString, at index: Int) -> ParagraphStyleState? {
        guard index < Int(string.length()) else { return nil }
        return string.attributes(at: UInt(index), effectiveRange: nil)?.object(forKey: "NSParagraphStyle")?.as(NSParagraphStyle.self)?.state
    }

    /// A new line of `string`'s `range`, +1.
    static func makeLine(_ string: NSAttributedString, range: (location: Int, length: Int), suffix: NSAttributedString? = nil) -> UnsafeMutableRawPointer {
        let line = Typesetting.make(CTLine.objCClass, string)
        let state = Typesetting.states[line]
        (state.range, state.suffix) = (range, suffix)
        return line
    }

    /// Breaks the string into the lines that fit the frame's box, from its
    /// top, and places their baselines in CoreText's coordinates: from the
    /// box's bottom left, y up.
    static func layOut(_ frame: TypesetState, string: NSAttributedString, from first: Int, length: Int?) {
        let text = Array(string.string().utf16)
        let limit = length.map { min(text.count, first + $0) } ?? text.count
        let box = frame.box
        let boxWidth = box.width > 0 && box.width < 1e7 ? box.width : CGFloat.greatestFiniteMagnitude
        let boxHeight = box.height > 0 && box.height < 1e7 ? box.height : CGFloat.greatestFiniteMagnitude
        let lines = NSMutableArray.empty()
        var origins: [CGPoint] = []
        var start = min(first, limit)
        var top: CGFloat = 0
        var paragraphStart = true
        while start < limit {
            let style = paragraphStyle(string, at: start)
            let indent = paragraphStart ? (style?.firstLineHeadIndent ?? 0) : (style?.headIndent ?? 0)
            let tail = style?.tailIndent ?? 0
            let right = boxWidth == .greatestFiniteMagnitude ? boxWidth : (tail > 0 ? min(tail, boxWidth) : boxWidth + tail)
            let available = max(right - indent, 1)
            let end = LineBreaks.end(of: string, text: text, from: start, limit: limit, width: available)
            let segments = LineSegments(string, range: (start, end - start), text: text)
            var ascent = segments.ascent
            let descent = segments.descent
            if let style {
                var height = ascent + descent
                if style.lineHeightMultiple > 0 { height *= style.lineHeightMultiple }
                if style.minimumLineHeight > 0 { height = max(height, style.minimumLineHeight) }
                if style.maximumLineHeight > 0 { height = min(height, style.maximumLineHeight) }
                ascent = height - descent
                if paragraphStart, start > first { top += style.paragraphSpacingBefore }
            }
            let baseline = top + ascent
            // A line that does not fit the box is left out, with the rest.
            if baseline + descent > boxHeight + 0.5 { break }
            let trailing = LineBreaks.trailingWhitespace(string, text: text, start: start, end: end).width
            let free = boxWidth == .greatestFiniteMagnitude ? 0 : max(available - (segments.width - trailing), 0)
            // NSTextAlignment: left 0, center 1, right 2; natural 4 is left.
            let flush: CGFloat = style?.alignment == 1 ? free / 2 : style?.alignment == 2 ? free : 0
            let line = makeLine(string, range: (start, end - start))
            lines.add(NSObject(line))
            ObjCRuntime.release(line)
            origins.append(CGPoint(x: indent + flush, y: (boxHeight == .greatestFiniteMagnitude ? 0 : boxHeight) - baseline))
            paragraphStart = end > start && LineBreaks.isLineEnd(text[end - 1])
            top = baseline + descent + segments.leading + (style?.lineSpacing ?? 0) + (paragraphStart ? (style?.paragraphSpacing ?? 0) : 0)
            start = end
        }
        frame.lines = lines
        frame.origins = origins
        frame.visibleLength = start - min(first, limit)
    }
}

/// The frame's lines, which live as long as the frame.
@c(_CTFrameGetLines)
public func CTFrameGetLines(_ frame: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let (state, _) = Typesetting.state(frame) else { return nil }
    if state.lines == nil { state.lines = NSMutableArray.empty() }
    return state.lines?.objcObject
}

/// The lines' baselines' origins, from the bottom left of the frame's box.
@c(_CTFrameGetLineOrigins)
public func CTFrameGetLineOrigins(_ frame: UnsafeMutableRawPointer?, _ range: PerryCFRange, _ origins: UnsafeMutablePointer<CGPoint>?) {
    guard let (state, _) = Typesetting.state(frame), let origins else { return }
    let first = max(range.location, 0)
    let end = range.length > 0 ? min(first + range.length, state.origins.count) : state.origins.count
    guard first < end else { return }
    for index in first..<end { origins[index - first] = state.origins[index] }
}

// MARK: Lines

@c(_CTLineGetTrailingWhitespaceWidth)
public func CTLineGetTrailingWhitespaceWidth(_ line: UnsafeMutableRawPointer?) -> Double {
    guard let (state, string) = Typesetting.state(line), state.suffix == nil else { return 0 }
    let text = Array(string.string().utf16)
    let start = min(state.range?.location ?? 0, text.count)
    let end = min(start + (state.range?.length ?? text.count), text.count)
    return Double(LineBreaks.trailingWhitespace(string, text: text, start: start, end: end).width)
}

/// How far to move the pen for the line to be flush in `flushWidth`: 0 is
/// left, 0.5 centered, 1 right.
@c(_CTLineGetPenOffsetForFlush)
public func CTLineGetPenOffsetForFlush(_ line: UnsafeMutableRawPointer?, _ flushFactor: CGFloat, _ flushWidth: Double) -> Double {
    guard let layout = lineSegments(line) else { return 0 }
    let used = Double(layout.width) - CTLineGetTrailingWhitespaceWidth(line)
    return max(flushWidth - used, 0) * Double(min(max(flushFactor, 0), 1))
}

/// A line that fits `width`: the line itself if it does, else its start
/// with the token after it (the token goes at the end for every type).
@c(_CTLineCreateTruncatedLine)
public func CTLineCreateTruncatedLine(_ line: UnsafeMutableRawPointer?, _ width: Double, _ type: UInt32,
                                      _ token: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let (state, string) = Typesetting.state(line) else { return nil }
    let text = Array(string.string().utf16)
    let start = min(state.range?.location ?? 0, text.count)
    let end = min(start + (state.range?.length ?? text.count), text.count)
    if state.suffix != nil || LineBreaks.width(string, text, start, end) <= CGFloat(width) {
        let copy = FrameLines.makeLine(string, range: (start, end - start), suffix: state.suffix)
        return copy
    }
    let tokenString = Typesetting.state(token)?.string
    let tokenWidth = tokenString.map { LineSegments($0).width } ?? 0
    var low = start, high = end
    while low < high {
        let middle = (low + high + 1) / 2
        if LineBreaks.width(string, text, start, middle) + tokenWidth <= CGFloat(width) { low = middle } else { high = middle - 1 }
    }
    while low > start, LineBreaks.isLowSurrogate(text[low]) || LineBreaks.isSpace(text[low - 1]) { low -= 1 }
    return FrameLines.makeLine(string, range: (start, low - start), suffix: tokenString)
}

/// The line as it is: words are not spread out here.
@c(_CTLineCreateJustifiedLine)
public func CTLineCreateJustifiedLine(_ line: UnsafeMutableRawPointer?, _ factor: CGFloat, _ width: Double) -> UnsafeMutableRawPointer? {
    guard let (state, string) = Typesetting.state(line) else { return nil }
    let length = Int(string.length())
    return FrameLines.makeLine(string, range: state.range ?? (0, length), suffix: state.suffix)
}

// MARK: Runs

final class RunState: ObjectState {
    var segment: LineSegments.Segment?
    /// The x of the caret before each UTF-16 unit, from the line's start,
    /// and after the last.
    var offsets: [CGFloat]?
    required init() {}
}

@ObjCClass("__NSCFRun")
final class CTRun: NSObject {
    static let states = StateTable<RunState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CTRun.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CTRun.objCClass.pointer)
    }

    static func state(_ run: UnsafeMutableRawPointer?) -> (state: RunState, segment: LineSegments.Segment)? {
        guard let run else { return nil }
        let state = states[run]
        return state.segment.map { (state, $0) }
    }

    /// A glyph for each UTF-16 unit; a truncation token's count its text's.
    static func count(_ segment: LineSegments.Segment) -> Int {
        segment.length > 0 ? segment.length : segment.text.utf16.count
    }

    static func offsets(_ state: RunState, _ segment: LineSegments.Segment) -> [CGFloat] {
        if let offsets = state.offsets { return offsets }
        let count = count(segment)
        var offsets: [CGFloat] = []
        if segment.isTab || segment.isDelegate || segment.text.isEmpty {
            offsets = (0...count).map { segment.x + segment.width * CGFloat($0) / CGFloat(max(count, 1)) }
        } else {
            let units = Array(segment.text.utf16)
            offsets = (0...count).map { index in
                index == 0 ? segment.x : index >= units.count ? segment.x + segment.width
                    : segment.x + Text.size(String(decoding: units[..<index], as: UTF16.self), font: segment.font).width
            }
        }
        state.offsets = offsets
        return offsets
    }

    /// The part of the run a CFRange names; a length of 0 is to its end.
    static func part(_ range: PerryCFRange, of count: Int) -> Range<Int> {
        let first = min(max(range.location, 0), count)
        return first..<(range.length > 0 ? min(first + range.length, count) : count)
    }
}

@c(_CTRunGetTypeID) public func CTRunGetTypeID() -> UInt { 0x50_07 }

/// The line's runs, in order, which live as long as the line.
@c(_CTLineGetGlyphRuns)
public func CTLineGetGlyphRuns(_ line: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let (state, _) = Typesetting.state(line) else { return nil }
    if let runs = state.runs { return runs.objcObject }
    let runs = NSMutableArray.empty()
    for segment in lineSegments(line)?.segments ?? [] {
        let run = CTRun.objCClass.object.allocated().initialized()
        CTRun.states[run.objcObject].segment = segment
        runs.add(run)
    }
    state.runs = runs
    return runs.objcObject
}

@c(_CTRunGetGlyphCount)
public func CTRunGetGlyphCount(_ run: UnsafeMutableRawPointer?) -> Int { CTRun.state(run).map { CTRun.count($0.segment) } ?? 0 }

/// The run's attributes, as its string has them.
@c(_CTRunGetAttributes)
public func CTRunGetAttributes(_ run: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { CTRun.state(run)?.segment.attributes?.objcObject }

/// kCTRunStatusNoStatus: left to right, in string order.
@c(_CTRunGetStatus) public func CTRunGetStatus(_ run: UnsafeMutableRawPointer?) -> UInt32 { 0 }

@c(_CTRunGetStringRange)
public func CTRunGetStringRange(_ run: UnsafeMutableRawPointer?) -> PerryCFRange {
    guard let (_, segment) = CTRun.state(run) else { return PerryCFRange(location: 0, length: 0) }
    return PerryCFRange(location: segment.start, length: segment.length)
}

// The run keeps no buffers of its own to point into: callers then copy.
@c(_CTRunGetGlyphsPtr) public func CTRunGetGlyphsPtr(_ run: UnsafeMutableRawPointer?) -> UnsafeRawPointer? { nil }
@c(_CTRunGetPositionsPtr) public func CTRunGetPositionsPtr(_ run: UnsafeMutableRawPointer?) -> UnsafeRawPointer? { nil }
@c(_CTRunGetAdvancesPtr) public func CTRunGetAdvancesPtr(_ run: UnsafeMutableRawPointer?) -> UnsafeRawPointer? { nil }
@c(_CTRunGetStringIndicesPtr) public func CTRunGetStringIndicesPtr(_ run: UnsafeMutableRawPointer?) -> UnsafeRawPointer? { nil }

/// The font's glyphs for the run's characters.
@c(_CTRunGetGlyphs)
public func CTRunGetGlyphs(_ run: UnsafeMutableRawPointer?, _ range: PerryCFRange, _ buffer: UnsafeMutablePointer<UInt16>?) {
    guard let (_, segment) = CTRun.state(run), let buffer else { return }
    let part = CTRun.part(range, of: CTRun.count(segment))
    guard !part.isEmpty else { return }
    let units = Array(segment.text.utf16)
    guard part.upperBound <= units.count else {
        buffer.update(repeating: 0, count: part.count)
        return
    }
    _ = units.withUnsafeBufferPointer { CTFontGetGlyphsForCharacters(segment.font.objcObject, $0.baseAddress! + part.lowerBound, buffer, part.count) }
}

/// Each glyph's position, from the line's origin, on the baseline.
@c(_CTRunGetPositions)
public func CTRunGetPositions(_ run: UnsafeMutableRawPointer?, _ range: PerryCFRange, _ buffer: UnsafeMutablePointer<CGPoint>?) {
    guard let (state, segment) = CTRun.state(run), let buffer else { return }
    let part = CTRun.part(range, of: CTRun.count(segment))
    guard !part.isEmpty else { return }
    // The first alone, which is what is asked most, needs no measuring.
    if part == 0..<1 {
        buffer[0] = CGPoint(x: segment.x, y: 0)
        return
    }
    let offsets = CTRun.offsets(state, segment)
    for index in part { buffer[index - part.lowerBound] = CGPoint(x: offsets[index], y: 0) }
}

@c(_CTRunGetAdvances)
public func CTRunGetAdvances(_ run: UnsafeMutableRawPointer?, _ range: PerryCFRange, _ buffer: UnsafeMutablePointer<CGSize>?) {
    guard let (state, segment) = CTRun.state(run), let buffer else { return }
    let part = CTRun.part(range, of: CTRun.count(segment))
    guard !part.isEmpty else { return }
    let offsets = CTRun.offsets(state, segment)
    for index in part { buffer[index - part.lowerBound] = CGSize(width: offsets[index + 1] - offsets[index], height: 0) }
}

/// Each glyph's character, by its index in the string.
@c(_CTRunGetStringIndices)
public func CTRunGetStringIndices(_ run: UnsafeMutableRawPointer?, _ range: PerryCFRange, _ buffer: UnsafeMutablePointer<Int>?) {
    guard let (_, segment) = CTRun.state(run), let buffer else { return }
    let part = CTRun.part(range, of: CTRun.count(segment))
    for index in part { buffer[index - part.lowerBound] = segment.start + min(index, max(segment.length - 1, 0)) }
}

@c(_CTRunGetTextMatrix)
public func CTRunGetTextMatrix(_ run: UnsafeMutableRawPointer?) -> CGAffineTransform { CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }

/// The width of the glyphs, and the run's font's ascent, descent and leading.
@c(_CTRunGetTypographicBounds)
public func CTRunGetTypographicBounds(_ run: UnsafeMutableRawPointer?, _ range: PerryCFRange, _ ascent: UnsafeMutablePointer<CGFloat>?,
                                      _ descent: UnsafeMutablePointer<CGFloat>?, _ leading: UnsafeMutablePointer<CGFloat>?) -> Double {
    guard let (state, segment) = CTRun.state(run) else { return 0 }
    var metrics = (ascent: segment.font.ascender(), descent: -segment.font.descender(), leading: segment.font.leading())
    if segment.isDelegate, let own = segment.attributes?.object(forKey: "CTRunDelegate").flatMap(RunDelegates.metrics) {
        metrics = (own.ascent, own.descent, 0)
    }
    ascent?.pointee = metrics.ascent
    descent?.pointee = metrics.descent
    leading?.pointee = metrics.leading
    let count = CTRun.count(segment)
    let part = CTRun.part(range, of: count)
    if part == 0..<count { return Double(segment.width) }
    guard !part.isEmpty else { return 0 }
    let offsets = CTRun.offsets(state, segment)
    return Double(offsets[part.upperBound] - offsets[part.lowerBound])
}

/// The box of the run from its baseline, at the context's text position.
@c(_CTRunGetImageBounds)
public func CTRunGetImageBounds(_ run: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?, _ range: PerryCFRange) -> CGRect {
    guard let (_, segment) = CTRun.state(run) else { return .zero }
    let position = context.map { CG.getTextPosition($0) } ?? .zero
    let descent = -segment.font.descender()
    return CGRect(x: position.x + segment.x, y: position.y - descent, width: segment.width, height: segment.font.ascender() + descent)
}

/// Draws the run where its line would, the line's origin at the context's
/// text position, in CoreText's coordinates, y up: flipped there to draw
/// its text upright. The whole run is drawn, whatever the range.
@c(_CTRunDraw)
public func CTRunDraw(_ run: UnsafeMutableRawPointer?, _ context: UnsafeMutableRawPointer?, _ range: PerryCFRange) {
    guard let (_, segment) = CTRun.state(run), let context else { return }
    let position = CG.getTextPosition(context)
    Graphics.push(context)
    defer { Graphics.pop() }
    CG.saveGState(context)
    defer { CG.restoreGState(context) }
    CG.translateCTM(context, position.x, position.y)
    CG.scaleCTM(context, 1, -1)
    segment.draw()
}

// MARK: Run delegates

/// CTRunDelegateCallbacks: a version, then the functions that are given
/// the delegate's context: dealloc, and the ascent, descent and width of
/// the characters the delegate stands for.
final class RunDelegateState: ObjectState {
    typealias Metric = @convention(c) (UnsafeMutableRawPointer?) -> CGFloat
    typealias Dealloc = @convention(c) (UnsafeMutableRawPointer?) -> Void
    var context: UnsafeMutableRawPointer?
    var dealloc: Dealloc?
    var ascent: Metric?
    var descent: Metric?
    var width: Metric?
    required init() {}
}

@ObjCClass("__NSCFRunDelegate")
final class CTRunDelegate: NSObject {
    static let states = StateTable<RunDelegateState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        let state = CTRunDelegate.states[objcObject]
        state.dealloc?(state.context)
        CTRunDelegate.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CTRunDelegate.objCClass.pointer)
    }
}

enum RunDelegates {
    static func metrics(_ delegate: NSObject) -> (ascent: CGFloat, descent: CGFloat, width: CGFloat)? {
        guard delegate.as(CTRunDelegate.self) != nil else { return nil }
        let state = CTRunDelegate.states[delegate.objcObject]
        return (state.ascent?(state.context) ?? 0, state.descent?(state.context) ?? 0, state.width?(state.context) ?? 0)
    }
}

@c(_CTRunDelegateGetTypeID) public func CTRunDelegateGetTypeID() -> UInt { 0x50_08 }

@c(_CTRunDelegateCreate)
public func CTRunDelegateCreate(_ callbacks: UnsafeRawPointer?, _ context: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let callbacks else { return nil }
    let delegate = CTRunDelegate.objCClass.object.allocated().initialized()
    let state = CTRunDelegate.states[delegate.objcObject]
    let word = MemoryLayout<Int>.size
    state.context = context
    state.dealloc = callbacks.load(fromByteOffset: word, as: RunDelegateState.Dealloc?.self)
    state.ascent = callbacks.load(fromByteOffset: word * 2, as: RunDelegateState.Metric?.self)
    state.descent = callbacks.load(fromByteOffset: word * 3, as: RunDelegateState.Metric?.self)
    state.width = callbacks.load(fromByteOffset: word * 4, as: RunDelegateState.Metric?.self)
    return ObjCRuntime.retain(delegate.objcObject)
}

@c(_CTRunDelegateGetRefCon)
public func CTRunDelegateGetRefCon(_ delegate: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    delegate.flatMap { CTRunDelegate.states[$0].context }
}

// MARK: Typesetters

@ObjCClass("__NSCFTypesetter")
final class CTTypesetter: NSObject {
    @ObjCMethod("dealloc")
    func dealloc() {
        Typesetting.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CTTypesetter.objCClass.pointer)
    }
}

@c(_CTTypesetterGetTypeID) public func CTTypesetterGetTypeID() -> UInt { 0x50_09 }

@c(_CTTypesetterCreateWithAttributedString)
public func CTTypesetterCreateWithAttributedString(_ string: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let string else { return nil }
    return Typesetting.make(CTTypesetter.objCClass, NSObject(objCArgument: string).unsafeCast(to: NSAttributedString.self))
}

@c(_CTTypesetterCreateWithAttributedStringAndOptions)
public func CTTypesetterCreateWithAttributedStringAndOptions(_ string: UnsafeMutableRawPointer?,
                                                             _ options: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    CTTypesetterCreateWithAttributedString(string)
}

/// The framesetter's typesetter, which lives as long as it does.
@c(_CTFramesetterGetTypesetter)
public func CTFramesetterGetTypesetter(_ framesetter: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let (state, string) = Typesetting.state(framesetter) else { return nil }
    if state.typesetter == nil {
        let typesetter = Typesetting.make(CTTypesetter.objCClass, string)
        state.typesetter = NSObject(typesetter)
        ObjCRuntime.release(typesetter)
    }
    return state.typesetter?.objcObject
}

/// How many characters from `start` make a line within `width`.
@c(_CTTypesetterSuggestLineBreak)
public func CTTypesetterSuggestLineBreak(_ typesetter: UnsafeMutableRawPointer?, _ start: Int, _ width: Double) -> Int {
    guard let (_, string) = Typesetting.state(typesetter) else { return 0 }
    let text = Array(string.string().utf16)
    guard start >= 0, start < text.count else { return 0 }
    return LineBreaks.end(of: string, text: text, from: start, limit: text.count, width: CGFloat(width)) - start
}

@c(_CTTypesetterSuggestClusterBreak)
public func CTTypesetterSuggestClusterBreak(_ typesetter: UnsafeMutableRawPointer?, _ start: Int, _ width: Double) -> Int {
    CTTypesetterSuggestLineBreak(typesetter, start, width)
}

/// A line of the range; a length of 0 is to the string's end.
@c(_CTTypesetterCreateLine)
public func CTTypesetterCreateLine(_ typesetter: UnsafeMutableRawPointer?, _ range: PerryCFRange) -> UnsafeMutableRawPointer? {
    guard let (_, string) = Typesetting.state(typesetter) else { return nil }
    let length = Int(string.length())
    let start = min(max(range.location, 0), length)
    return FrameLines.makeLine(string, range: (start, range.length > 0 ? min(range.length, length - start) : length - start))
}

// MARK: Paragraph styles and the rest

/// A paragraph style's setting, copied to `buffer`; false for one not kept.
@c(_CTParagraphStyleGetValueForSpecifier)
public func CTParagraphStyleGetValueForSpecifier(_ style: UnsafeMutableRawPointer?, _ specifier: UInt32, _ size: Int,
                                                 _ buffer: UnsafeMutableRawPointer?) -> Bool {
    guard let style, let buffer, let state = NSObject(style).as(NSParagraphStyle.self)?.state else { return false }
    func byte(_ value: Int) -> Bool {
        guard size >= 1 else { return false }
        buffer.storeBytes(of: UInt8(truncatingIfNeeded: value), as: UInt8.self)
        return true
    }
    func float(_ value: CGFloat) -> Bool {
        guard size >= MemoryLayout<CGFloat>.size else { return false }
        buffer.storeBytes(of: value, as: CGFloat.self)
        return true
    }
    switch specifier {
    case 0: return byte(Int(NSTextAlignmentToCTTextAlignment(state.alignment)))
    case 1: return float(state.firstLineHeadIndent)
    case 2: return float(state.headIndent)
    case 3: return float(state.tailIndent)
    case 6: return byte(state.lineBreakMode)
    case 7: return float(state.lineHeightMultiple)
    case 8: return float(state.maximumLineHeight)
    case 9: return float(state.minimumLineHeight)
    case 10, 14, 15, 16: return float(state.lineSpacing)
    case 11: return float(state.paragraphSpacing)
    case 12: return float(state.paragraphSpacingBefore)
    case 13: return byte(state.baseWritingDirection)
    default: return false
    }
}

/// kCTVersionNumber10_15's successor: a recent CoreText.
@c(_CTGetCoreTextVersion) public func CTGetCoreTextVersion() -> UInt32 { 0x000E_0000 }

/// More of CoreText's keys, with Darwin's values.
@ObjCConstants
enum CoreTextMoreKeys {
    static let kCTRunDelegateAttributeName = "CTRunDelegate"
    static let kCTBackgroundColorAttributeName = "CTBackgroundColor"
    static let kCTUnderlineColorAttributeName = "NSUnderlineColor"
    static let kCTSuperscriptAttributeName = "NSSuperScript"
    static let kCTGlyphInfoAttributeName = "NSGlyphInfo"
    static let kCTLanguageAttributeName = "NSLanguage"
    static let kCTCharacterShapeAttributeName = "NSCharacterShape"
    static let kCTWritingDirectionAttributeName = "NSWritingDirection"
    static let kCTRubyAnnotationAttributeName = "CTRubyAnnotation"
    static let kCTBaselineClassAttributeName = "CTBaselineClass"
    static let kCTBaselineInfoAttributeName = "CTBaselineInfo"
    static let kCTBaselineReferenceInfoAttributeName = "CTBaselineReferenceInfo"
    static let kCTFramePathFillRuleAttributeName = "CTFramePathFillRule"
    static let kCTFramePathWidthAttributeName = "CTFramePathWidth"
    static let kCTTypesetterOptionForcedEmbeddingLevel = "CTTypesetterOptionForcedEmbeddingLevel"
    static let kCTFontManagerErrorDomain = "com.apple.CoreText.CTFontManagerErrorDomain"
    static let kCTFontCascadeListAttribute = "NSCTFontCascadeListAttribute"
    static let kCTFontFeaturesAttribute = "NSCTFontFeaturesAttribute"
    static let kCTFontFormatAttribute = "NSCTFontFormatAttribute"
    static let kCTFontStyleNameAttribute = "NSFontFaceAttribute"
    static let kCTFontURLAttribute = "NSCTFontFileURLAttribute"
    static let kCTFontVariationAttribute = "NSCTFontVariationAttribute"
    static let kCTFontVariationAxesAttribute = "NSCTFontVariationAxesAttribute"
    static let kCTFontVariationAxisIdentifierKey = "NSCTVariationAxisIdentifier"
    static let kCTFontVariationAxisMinimumValueKey = "NSCTVariationAxisMinimumValue"
    static let kCTFontVariationAxisMaximumValueKey = "NSCTVariationAxisMaximumValue"
    static let kCTFontVariationAxisDefaultValueKey = "NSCTVariationAxisDefaultValue"
    static let kCTFontVariationAxisNameKey = "NSCTVariationAxisName"
    static let kCTFontVariationAxisHiddenKey = "NSCTVariationAxisHidden"
    static let kCTFontFeatureTypeIdentifierKey = "CTFeatureTypeIdentifier"
    static let kCTFontFeatureTypeSelectorsKey = "CTFeatureTypeSelectors"
    static let kCTFontFeatureSelectorIdentifierKey = "CTFeatureSelectorIdentifier"
    static let kCTFontFamilyNameKey = "CTFontFamilyName"
    static let kCTFontPostScriptNameKey = "CTFontPostScriptName"
    static let kCTFontSlantTrait = "NSCTFontSlantTrait"
}
