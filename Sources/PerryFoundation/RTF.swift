import FoundationEssentials

// RTF read as its text: paragraphs, tabs, line breaks, escaped and Unicode
// characters, with the font, color and style tables, the document's info
// and pictures skipped. Formatting is not kept: an attributed string made
// from RTF has the text alone (Xcode 4 shows its license this way).

enum RTF {
    /// Whether the bytes are RTF.
    static func isRTF(_ bytes: [UInt8]) -> Bool { bytes.starts(with: Array("{\\rtf".utf8)) }

    /// Destinations whose contents are not text.
    private static let skipped: Set<String> = [
        "fonttbl", "colortbl", "stylesheet", "info", "pict", "header", "footer", "headerl", "headerr", "footerl", "footerr",
        "listtable", "listoverridetable", "revtbl", "rsidtbl", "generator", "xmlnstbl", "themedata", "colorschememapping",
        "datastore", "latentstyles", "pgdsctbl", "object", "fldinst", "NeXTGraphic", "expandedcolortbl",
    ]

    /// The text of RTF bytes.
    static func text(_ bytes: [UInt8]) -> String {
        var units: [UInt16] = []
        var pendingBytes: [UInt8] = []   // \'hh bytes, in the Windows-1252 code page
        // Per group: whether its text is skipped, and how many characters
        // follow a \uN as its fallback.
        var stack: [(skip: Bool, unicodeSkip: Int)] = [(false, 1)]
        var skipChars = 0
        var index = 0

        func flushBytes() {
            guard !pendingBytes.isEmpty else { return }
            units += Array((String(bytes: pendingBytes, encoding: .windowsCP1252) ?? String(decoding: pendingBytes, as: UTF8.self)).utf16)
            pendingBytes = []
        }
        func emit(_ text: String) {
            guard !stack[stack.count - 1].skip else { return }
            if skipChars > 0 { skipChars -= 1; return }
            flushBytes()
            units += Array(text.utf16)
        }

        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "{"):
                flushBytes()
                stack.append(stack[stack.count - 1])
                index += 1
            case UInt8(ascii: "}"):
                flushBytes()
                if stack.count > 1 { stack.removeLast() }
                index += 1
            case UInt8(ascii: "\\"):
                index += 1
                guard index < bytes.count else { break }
                let next = bytes[index]
                if next == UInt8(ascii: "'") {
                    // A byte in hexadecimal.
                    let hex = bytes[min(index + 1, bytes.count)..<min(index + 3, bytes.count)]
                    index += 3
                    if let value = UInt8(String(decoding: hex, as: UTF8.self), radix: 16), !stack[stack.count - 1].skip {
                        if skipChars > 0 { skipChars -= 1 } else { pendingBytes.append(value) }
                    }
                } else if (next >= UInt8(ascii: "a") && next <= UInt8(ascii: "z")) || (next >= UInt8(ascii: "A") && next <= UInt8(ascii: "Z")) {
                    // A control word, with an optional number and one space.
                    var end = index
                    while end < bytes.count, (bytes[end] >= UInt8(ascii: "a") && bytes[end] <= UInt8(ascii: "z"))
                            || (bytes[end] >= UInt8(ascii: "A") && bytes[end] <= UInt8(ascii: "Z")) { end += 1 }
                    let word = String(decoding: bytes[index..<end], as: UTF8.self)
                    var numberEnd = end
                    if numberEnd < bytes.count, bytes[numberEnd] == UInt8(ascii: "-") { numberEnd += 1 }
                    while numberEnd < bytes.count, bytes[numberEnd] >= UInt8(ascii: "0"), bytes[numberEnd] <= UInt8(ascii: "9") { numberEnd += 1 }
                    let number = Int(String(decoding: bytes[end..<numberEnd], as: UTF8.self))
                    index = numberEnd
                    if index < bytes.count, bytes[index] == UInt8(ascii: " ") { index += 1 }
                    switch word {
                    case "par", "line", "sect", "page": emit("\n")
                    case "tab": emit("\t")
                    case "emdash": emit("\u{2014}")
                    case "endash": emit("\u{2013}")
                    case "bullet": emit("\u{2022}")
                    case "lquote": emit("\u{2018}")
                    case "rquote": emit("\u{2019}")
                    case "ldblquote": emit("\u{201C}")
                    case "rdblquote": emit("\u{201D}")
                    case "uc": stack[stack.count - 1].unicodeSkip = number ?? 1
                    case "u":
                        if let number, !stack[stack.count - 1].skip {
                            flushBytes()
                            units.append(UInt16(truncatingIfNeeded: number < 0 ? number + 65536 : number))
                            skipChars = stack[stack.count - 1].unicodeSkip
                        }
                    default:
                        if skipped.contains(word) { stack[stack.count - 1].skip = true }
                    }
                } else {
                    // A control symbol.
                    index += 1
                    switch next {
                    case UInt8(ascii: "*"): stack[stack.count - 1].skip = true
                    case UInt8(ascii: "~"): emit("\u{00A0}")
                    case UInt8(ascii: "-"): break
                    case UInt8(ascii: "_"): emit("\u{2011}")
                    case UInt8(ascii: "\n"), UInt8(ascii: "\r"): emit("\n")
                    default: emit(String(UnicodeScalar(next)))
                    }
                }
            case UInt8(ascii: "\n"), UInt8(ascii: "\r"):
                index += 1
            default:
                // A run of plain text.
                var end = index
                while end < bytes.count, ![UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "\\"), UInt8(ascii: "\n"), UInt8(ascii: "\r")].contains(bytes[end]) {
                    end += 1
                }
                var text = String(decoding: bytes[index..<end], as: UTF8.self)
                index = end
                if skipChars > 0 {
                    let dropped = min(skipChars, text.count)
                    text.removeFirst(dropped)
                    skipChars -= dropped
                }
                emit(text)
            }
        }
        flushBytes()
        return String(decoding: units, as: UTF16.self)
    }

    /// The text of a document: RTF's, or the bytes as UTF-8 (Latin-1 where
    /// they are not).
    static func documentText(_ bytes: [UInt8]) -> String {
        if isRTF(bytes) { return text(bytes) }
        return String(validating: bytes, as: UTF8.self) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }
}
