import Darwin

// objc_enumerateClasses: the classes of an image, or the ones made at run
// time, that match a name prefix, a protocol and a superclass. It is made
// here from the runtime's class list and each class's image name, which
// every runtime has, rather than the C function of the same name, which
// older runtimes (and Perry's) lack.

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public enum ObjCEnumerationImage {
    /// Classes registered at run time, which belong to no image.
    case dynamicClasses
    /// The image a handle from dlopen(3) names.
    case image(UnsafeRawPointer)
    /// The image loaded at this Mach header.
    case machHeader(UnsafeRawPointer)
}

@available(*, unavailable)
extension ObjCEnumerationImage: Sendable {}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public struct ObjCClassList: Sequence {
    public typealias Element = AnyClass

    fileprivate let image: ObjCEnumerationImage
    fileprivate let prefix: String?
    fileprivate let conformance: Protocol?
    fileprivate let superclass: AnyClass?

    public class Iterator: IteratorProtocol {
        public typealias Element = AnyClass

        private var classes: [AnyClass]
        private var position = 0

        fileprivate init(_ classes: [AnyClass]) {
            self.classes = classes
        }

        public func next() -> AnyClass? {
            guard position < classes.count else { return nil }
            defer { position += 1 }
            return classes[position]
        }
    }

    public func makeIterator() -> Iterator {
        Iterator(matchingClasses())
    }

    /// The runtime's classes that pass every test, in its order.
    private func matchingClasses() -> [AnyClass] {
        var count: UInt32 = 0
        guard let list = objc_copyClassList(&count) else { return [] }
        defer { free(UnsafeMutableRawPointer(list)) }
        let imageName = imagePath()
        var classes: [AnyClass] = []
        for index in 0..<Int(count) {
            let cls: AnyClass = list[index]
            guard isInImage(cls, imageName) else { continue }
            if let prefix, !String(cString: class_getName(cls)).hasPrefix(prefix) { continue }
            if let conformance, !class_conformsToProtocol(cls, conformance) { continue }
            if let superclass, !inherits(cls, from: superclass) { continue }
            classes.append(cls)
        }
        return classes
    }

    /// The path of the image to search, or nil for run-time classes.
    private func imagePath() -> String? {
        switch image {
        case .dynamicClasses:
            return nil
        case .machHeader(let header):
            var info = Dl_info()
            guard dladdr(header, &info) != 0, let name = info.dli_fname else { return "" }
            return String(cString: name)
        case .image:
            return ""
        }
    }

    private func isInImage(_ cls: AnyClass, _ path: String?) -> Bool {
        let name = class_getImageName(cls)
        switch image {
        case .dynamicClasses:
            return name == nil
        case .machHeader:
            guard let name, let path else { return false }
            return String(cString: name) == path
        case .image(let handle):
            // A handle is the image's own: open the class's image again,
            // without loading anything, and compare the handles.
            guard let name, let opened = dlopen(name, RTLD_NOLOAD | RTLD_LAZY) else { return false }
            defer { dlclose(opened) }
            return UnsafeRawPointer(opened) == handle
        }
    }

    /// Whether `superclass` is `cls`'s superclass, directly or not.
    private func inherits(_ cls: AnyClass, from superclass: AnyClass) -> Bool {
        var current: AnyClass? = class_getSuperclass(cls)
        while let ancestor = current {
            if ancestor == superclass { return true }
            current = class_getSuperclass(ancestor)
        }
        return false
    }
}

@available(*, unavailable)
extension ObjCClassList: Sendable {}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public func objc_enumerateClasses(fromImage: ObjCEnumerationImage = .machHeader(#dsohandle),
                                  matchingNamePrefix: String? = nil,
                                  conformingTo: Protocol? = nil,
                                  subclassing: AnyClass? = nil) -> ObjCClassList {
    ObjCClassList(image: fromImage, prefix: matchingNamePrefix, conformance: conformingTo, superclass: subclassing)
}
