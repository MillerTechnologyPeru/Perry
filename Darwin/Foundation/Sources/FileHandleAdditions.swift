// NSFileHandle's Swift API over its Objective-C methods that read, write and
// report the offset: those that throw, whose results are nil at the end of
// the file, as Apple's Foundation overlay has them. swift-foundation's
// FileHandle hides NSFileHandle's Swift name here, and only unavailable
// declarations may name it by its Objective-C name; availability is the
// compiler's and binds nothing.

@available(*, unavailable)
extension NSFileHandle {
    /// The data from the offset to the end of the file; nil when there is none.
    public func readToEnd() throws -> Data? {
        let data = readDataToEndOfFile()
        return data.isEmpty ? nil : data
    }

    /// Up to `count` bytes from the offset; nil at the end of the file.
    public func read(upToCount count: Int) throws -> Data? {
        let data = readData(ofLength: count)
        return data.isEmpty ? nil : data
    }

    /// The offset in the file.
    public func offset() throws -> UInt64 {
        offsetInFile
    }

    /// Writes the data at the offset.
    public func write<T: DataProtocol>(contentsOf data: T) throws {
        write(Data(data))
    }
}
