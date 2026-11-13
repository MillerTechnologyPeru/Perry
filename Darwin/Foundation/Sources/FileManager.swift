// NSFileManager's Swift API over its Objective-C methods: the enumerator of
// a directory's URLs, whose error handler takes Swift's URL and Error, as
// Apple's Foundation overlay has it. swift-foundation's FileManager hides
// NSFileManager's Swift name here, and only unavailable declarations may
// name it by its Objective-C name; availability is the compiler's and binds
// nothing.

@available(*, unavailable)
extension NSFileManager {
    /// An enumerator of the URLs under `url`; the handler is asked whether
    /// to go on after an error, and going on is the default.
    public func enumerator(at url: URL, includingPropertiesForKeys keys: [NSURLResourceKey]?,
                           options mask: NSFileManager.DirectoryEnumerationOptions = [],
                           errorHandler handler: ((URL, Error) -> Bool)? = nil) -> NSDirectoryEnumerator? {
        __enumerator(at: url, includingPropertiesForKeys: keys, options: mask) { url, error in
            handler?(url, error) ?? true
        }
    }

    /// The same, by the name apps built with older compilers bind it
    /// (Swift Playgrounds 4.7): the error parameter of the handler mangled
    /// before `any` was spelled out.
    @_silgen_name("$sSo13NSFileManagerC10FoundationE10enumerator2at26includingPropertiesForKeys7options12errorHandlerSo21NSDirectoryEnumeratorCSgAC3URLV_SaySo16NSURLResourceKeyaGSgSo0M18EnumerationOptionsVSbAM_s5ErrorpXEcSgtF")
    public func _enumeratorBeforeAny(at url: URL, includingPropertiesForKeys keys: [NSURLResourceKey]?,
                                     options mask: NSFileManager.DirectoryEnumerationOptions,
                                     errorHandler handler: ((URL, Error) -> Bool)?) -> NSDirectoryEnumerator? {
        enumerator(at: url, includingPropertiesForKeys: keys, options: mask, errorHandler: handler)
    }
}
