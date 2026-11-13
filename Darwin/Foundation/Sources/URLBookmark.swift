// File URLs' bookmark data. A bookmark here is a marker and the file's
// path, so resolving one finds the file again as long as it has not been
// moved: there is no volume or inode tracking to follow a move.
//
// Their types are the Objective-C names, as URLResourceValues' keys are.

#if canImport(Darwin)
import Darwin
#endif

private let bookmarkMarker = Array("perry-bookmark:".utf8)

@available(*, unavailable)
extension URL {
    /// Returns bookmark data for the file the URL points to.
    public func bookmarkData(
        options: NSURLBookmarkCreationOptions = [],
        includingResourceValuesForKeys keys: Set<NSURLResourceKey>? = nil,
        relativeTo relativeURL: URL? = nil
    ) throws -> Data {
        guard isFileURL else { throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSURLErrorKey: self]) }
        var info = stat()
        guard stat(path, &info) == 0 else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: self, NSFilePathErrorKey: path])
        }
        return Data(bookmarkMarker + Array(standardizedFileURL.path.utf8))
    }

    /// Creates a URL from bookmark data, finding the file again.
    public init(
        resolvingBookmarkData data: Data,
        options: NSURLBookmarkResolutionOptions = [],
        relativeTo relativeURL: URL? = nil,
        bookmarkDataIsStale isStale: inout Bool
    ) throws {
        let bytes = Array(data)
        guard bytes.count > bookmarkMarker.count, Array(bytes.prefix(bookmarkMarker.count)) == bookmarkMarker else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let path = String(decoding: bytes.dropFirst(bookmarkMarker.count), as: UTF8.self)
        var info = stat()
        guard stat(path, &info) == 0 else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: path])
        }
        isStale = false
        self.init(fileURLWithPath: path)
    }
}
