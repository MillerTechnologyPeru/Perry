import Foundation
import PerryLoaderCore
import Testing

/// The loader's C property list reader, checked against Foundation's writer.
struct PlistTests {

    private func parse(_ data: Data) throws -> UnsafeMutablePointer<perry_plist> {
        var error: UnsafePointer<CChar>?
        let plist = data.withUnsafeBytes { buffer in
            perry_plist_parse(buffer.baseAddress!.assumingMemoryBound(to: UInt8.self), buffer.count, &error)
        }
        guard let plist else {
            Issue.record("parse failed: \(error.map { String(cString: $0) } ?? "unknown")")
            throw CancellationError()
        }
        return plist
    }

    private func string(_ dict: UnsafePointer<perry_plist>, _ key: String) -> String? {
        perry_plist_get_string(dict, key).map { String(cString: $0) }
    }

    private func value(_ dict: UnsafePointer<perry_plist>, _ key: String) -> UnsafePointer<perry_plist>? {
        perry_plist_get(dict, key)
    }

    static var sample: [String: Any] {
        [
            "CFBundleExecutable": "Game",
            "Name": "Café 🎮 ünïcode",
            "Count": 42,
            "Negative": -7,
            "Big": 1 << 40,
            "Ratio": 0.5,
            "Enabled": true,
            "Disabled": false,
            "Blob": Data([0, 1, 2, 254, 255]),
            "List": ["a", "b", "c"],
            "Nested": ["Inner": ["Deep": "value"]],
            "Empty": [String](),
        ]
    }

    @Test("Binary and XML plists written by Foundation", arguments: [
        PropertyListSerialization.PropertyListFormat.binary,
        PropertyListSerialization.PropertyListFormat.xml,
    ])
    func foundationRoundTrip(format: PropertyListSerialization.PropertyListFormat) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: Self.sample, format: format, options: 0)
        let plist = try parse(data)
        defer { perry_plist_free(plist) }

        #expect(plist.pointee.type == PERRY_PLIST_DICT)
        #expect(string(plist, "CFBundleExecutable") == "Game")
        #expect(string(plist, "Name") == "Café 🎮 ünïcode")
        #expect(value(plist, "Count")?.pointee.integer == 42)
        #expect(value(plist, "Negative")?.pointee.integer == -7)
        #expect(value(plist, "Big")?.pointee.integer == 1 << 40)
        #expect(value(plist, "Ratio")?.pointee.real == 0.5)
        #expect(value(plist, "Enabled")?.pointee.boolean == true)
        #expect(value(plist, "Disabled")?.pointee.boolean == false)

        let blob = try #require(value(plist, "Blob"))
        #expect(blob.pointee.type == PERRY_PLIST_DATA)
        #expect(Data(bytes: blob.pointee.data.bytes, count: blob.pointee.data.length) == Data([0, 1, 2, 254, 255]))

        let list = try #require(value(plist, "List"))
        #expect(list.pointee.type == PERRY_PLIST_ARRAY)
        #expect(list.pointee.container.count == 3)
        #expect(String(cString: list.pointee.container.values[2]!.pointee.string) == "c")

        let nested = try #require(value(plist, "Nested"))
        let inner = try #require(value(nested, "Inner"))
        #expect(string(inner, "Deep") == "value")

        #expect(value(plist, "Empty")?.pointee.container.count == 0)
        #expect(value(plist, "Missing") == nil)
    }

    @Test("XML entities, comments and empty elements")
    func xmlDetails() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <!-- a comment -->
        <dict>
            <key>Escaped</key><string>a &lt;b&gt; &amp; &quot;c&quot; &#65;&#x42;</string>
            <key>Empty</key><string/>
            <key>Hex</key><integer>0x10</integer>
            <key>NoValues</key><dict/>
        </dict>
        </plist>
        """
        let plist = try parse(Data(xml.utf8))
        defer { perry_plist_free(plist) }
        #expect(string(plist, "Escaped") == "a <b> & \"c\" AB")
        #expect(string(plist, "Empty") == "")
        #expect(value(plist, "Hex")?.pointee.integer == 16)
        #expect(value(plist, "NoValues")?.pointee.type == PERRY_PLIST_DICT)
    }

    @Test("Malformed input is rejected", arguments: [
        "<plist><dict><key>A</key></dict></plist>",
        "<plist><dict><string>no key</string></dict></plist>",
        "<plist><array><string>unterminated</array></plist>",
        "bplist00",
        "",
    ])
    func malformed(input: String) {
        var error: UnsafePointer<CChar>?
        let bytes = Array(input.utf8) + [0]
        let plist = perry_plist_parse(bytes, bytes.count - 1, &error)
        #expect(plist == nil)
        #expect(error != nil)
        perry_plist_free(plist)
    }
}
