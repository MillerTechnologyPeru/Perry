// The bundle of the image an address is in, as Apple's Foundation overlay
// gives it to code that names its own bundle by its #dsohandle: the
// framework bundle a framework's binary sits in, or the main bundle for the
// app's own executable.

/// The path of the loaded image containing an address; nil for none.
@_silgen_name("dyld_image_path_containing_address")
private func _imagePath(containing address: UnsafeRawPointer) -> UnsafePointer<CChar>?

extension Bundle {
    public convenience init?(__dsoHandle: UnsafeRawPointer) {
        guard let found = _imagePath(containing: __dsoHandle) else { return nil }
        let image = String(cString: found)
        let directory = (image as NSString).deletingLastPathComponent
        // The app's executable sits in the main bundle's directory; a
        // framework's in its own; a library elsewhere has no bundle but the
        // directory it is in.
        if let main = Bundle.main.executablePath, (main as NSString).standardizingPath == (image as NSString).standardizingPath {
            self.init(path: Bundle.main.bundlePath)
        } else {
            self.init(path: directory)
        }
    }
}
