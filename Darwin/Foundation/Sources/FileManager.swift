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

    /// Replaces the item at a URL with another, which is moved there; the
    /// URL the new item ends up at.
    public func replaceItemAt(_ originalItemURL: URL, withItemAt newItemURL: URL, backupItemName: String? = nil,
                              options: NSFileManager.ItemReplacementOptions = []) throws -> URL? {
        var result: NSURL?
        try replaceItem(at: originalItemURL, withItemAt: newItemURL, backupItemName: backupItemName, options: options,
                        resultingItemURL: &result)
        return result.map { $0 as URL }
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

// MARK: - URL's standard directories

extension URL {
    private static func standard(_ directory: FileManager.SearchPathDirectory) -> URL {
        FileManager.default.urls(for: directory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// The app's Documents directory.
    public static var documentsDirectory: URL { standard(.documentDirectory) }
    /// The app's Library directory.
    public static var libraryDirectory: URL { standard(.libraryDirectory) }
    /// The app's Library/Caches directory.
    public static var cachesDirectory: URL { standard(.cachesDirectory) }
    /// The app's Library/Application Support directory.
    public static var applicationSupportDirectory: URL { standard(.applicationSupportDirectory) }
}
