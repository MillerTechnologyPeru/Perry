// Decodes an asset catalog's images with macOS's CoreUI and writes each as
// <name>@<scale>x.png into <catalog>.images, and each rendition for the dark
// appearance as <name>~dark@<scale>x.png, for Perry to read where it can't
// decode a rendition itself (CoreUI's deepmap2 compression, which Apple
// hasn't documented). CoreUI is private: it is loaded at run time and
// reached through the Objective-C runtime, with no headers.
//
// Usage: extract-assets <Assets.car>...
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard dlopen("/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI", RTLD_NOW) != nil,
      let catalogClass = NSClassFromString("CUICatalog") as? NSObject.Type else {
    FileHandle.standardError.write(Data("extract-assets: CoreUI is not available\n".utf8))
    exit(1)
}

/// Sends `selector`, which returns a C pointer or object, to `object`.
func pointer(_ object: AnyObject, _ selector: String) -> UnsafeRawPointer? {
    let sel = NSSelectorFromString(selector)
    guard object.responds(to: sel), let method = class_getInstanceMethod(type(of: object), sel) else { return nil }
    typealias Getter = @convention(c) (AnyObject, Selector) -> UnsafeRawPointer?
    return unsafeBitCast(method_getImplementation(method), to: Getter.self)(object, sel)
}

func double(_ object: AnyObject, _ selector: String) -> Double {
    let sel = NSSelectorFromString(selector)
    guard object.responds(to: sel), let method = class_getInstanceMethod(type(of: object), sel) else { return 0 }
    typealias Getter = @convention(c) (AnyObject, Selector) -> Double
    return unsafeBitCast(method_getImplementation(method), to: Getter.self)(object, sel)
}

func integer(_ object: AnyObject, _ selector: String) -> Int {
    let sel = NSSelectorFromString(selector)
    guard object.responds(to: sel), let method = class_getInstanceMethod(type(of: object), sel) else { return -1 }
    typealias Getter = @convention(c) (AnyObject, Selector) -> Int
    return unsafeBitCast(method_getImplementation(method), to: Getter.self)(object, sel)
}

var failed = false
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    let initializer = NSSelectorFromString("initWithURL:error:")
    typealias Init = @convention(c) (AnyObject, Selector, NSURL, UnsafeMutablePointer<NSError?>?) -> AnyObject?
    guard let method = class_getInstanceMethod(catalogClass, initializer) else { exit(1) }
    var error: NSError?
    guard let allocated = (catalogClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
          let catalog = unsafeBitCast(method_getImplementation(method), to: Init.self)(allocated, initializer,
                                                                                       url as NSURL, &error) else {
        FileHandle.standardError.write(Data("extract-assets: \(path): \(error?.localizedDescription ?? "unreadable")\n".utf8))
        failed = true
        continue
    }
    let names = (catalog.perform(NSSelectorFromString("allImageNames"))?.takeUnretainedValue() as? [String]) ?? []
    let output = URL(fileURLWithPath: path + ".images")
    try? FileManager.default.removeItem(at: output)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    var written = 0
    for name in names {
        let images = (catalog.perform(NSSelectorFromString("imagesWithName:"), with: name)?.takeUnretainedValue() as? [AnyObject]) ?? []
        // One image a scale and appearance: a phone's (idiom 1) over a
        // universal one (0); others (iPad, Mac…) only when there is nothing
        // for the phone. Appearances other than dark are the default's.
        struct Slot: Hashable { let scale: Int, dark: Bool }
        var chosen: [Slot: (idiom: Int, image: CGImage)] = [:]
        for named in images {
            guard let raw = pointer(named, "image") else { continue }
            let image = Unmanaged<CGImage>.fromOpaque(raw).takeUnretainedValue()
            let scale = max(Int(double(named, "scale").rounded()), 1)
            let appearance = pointer(named, "appearance").map { Unmanaged<NSString>.fromOpaque($0).takeUnretainedValue() as String }
            let slot = Slot(scale: scale, dark: appearance == "UIAppearanceDark")
            let idiom = integer(named, "idiom")
            let rank = idiom == 1 ? 0 : idiom == 0 ? 1 : 2
            if let existing = chosen[slot], (existing.idiom == 1 ? 0 : existing.idiom == 0 ? 1 : 2) <= rank { continue }
            chosen[slot] = (idiom, image)
        }
        for (slot, entry) in chosen {
            let file = output.appendingPathComponent("\(name)\(slot.dark ? "~dark" : "")@\(slot.scale)x.png")
            guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                continue
            }
            CGImageDestinationAddImage(destination, entry.image, nil)
            if CGImageDestinationFinalize(destination) { written += 1 }
        }
    }
    print("\(output.path): \(written) images of \(names.count) names")
}
exit(failed ? 1 : 0)
