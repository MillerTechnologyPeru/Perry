import CPerryGeometry
import Glibc
import PerryObjCInterop

// CIFilter and the filters Perry renders: the blend modes and Porter-Duff
// compositing, blurs and sharpening, color adjustments and effects,
// geometry, a generator and transitions; enough for iWork's and iLife's
// editors and for iOS apps' image touch-ups. Each filter's inputs carry the
// attributes Core Image describes them with, which inspectors build their
// controls from. A filter Perry doesn't know gives its input image back.

/// An input a filter takes, with its default and range.
struct FilterInput {
    enum Kind {
        case image
        case number(Double)
        case color(CGFloat, CGFloat, CGFloat, CGFloat)
        case vector([CGFloat])
        case transform
    }

    let key: String
    let kind: Kind
    var type: String?
    var minimum: Double?
    var maximum: Double?
    var sliderMinimum: Double?
    var sliderMaximum: Double?
    var identity: Double?

    static func image(_ key: String = "inputImage") -> FilterInput { FilterInput(key: key, kind: .image, type: "CIAttributeTypeImage") }

    static func number(_ key: String, _ value: Double, _ type: String = "CIAttributeTypeScalar", min: Double? = nil, max: Double? = nil,
                       sliderMin: Double? = nil, sliderMax: Double? = nil, identity: Double? = nil) -> FilterInput {
        FilterInput(key: key, kind: .number(value), type: type, minimum: min, maximum: max, sliderMinimum: sliderMin ?? min,
                    sliderMaximum: sliderMax ?? max, identity: identity)
    }

    static func color(_ key: String, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> FilterInput {
        FilterInput(key: key, kind: .color(r, g, b, a), type: "CIAttributeTypeColor")
    }

    static func vector(_ key: String, _ values: [CGFloat], _ type: String? = nil) -> FilterInput {
        FilterInput(key: key, kind: .vector(values), type: type)
    }

    static func transform(_ key: String = "inputTransform") -> FilterInput {
        FilterInput(key: key, kind: .transform, type: "CIAttributeTypeTransform")
    }

    /// "inputBackgroundImage" as "Background Image".
    var displayName: String { FilterSpec.words(key.hasPrefix("input") ? String(key.dropFirst(5)) : key) }

    var className: String {
        switch kind {
        case .image: return "CIImage"
        case .number: return "NSNumber"
        case .color: return "CIColor"
        case .vector: return "CIVector"
        case .transform:
            #if arch(i386) || arch(x86_64)
            return "NSAffineTransform"
            #else
            return "NSValue"
            #endif
        }
    }

    /// The default as an object, as -setDefaults sets it; nil for images
    /// and transforms.
    var defaultObject: NSObject? {
        switch kind {
        case .image, .transform: return nil
        case .number(let value): return NSNumber.make(double: value)
        case .color(let r, let g, let b, let a): return CIColor.make(r, g, b, a)
        case .vector(let values): return CIVector.make(values)
        }
    }

    /// The input's attribute dictionary.
    var attributes: NSMutableDictionary {
        let attributes = NSMutableDictionary.empty()
        attributes.set(className.objectValue, forKey: "CIAttributeClass")
        attributes.set(key.objectValue, forKey: "CIAttributeName")
        attributes.set(displayName.objectValue, forKey: "CIAttributeDisplayName")
        if let type { attributes.set(type.objectValue, forKey: "CIAttributeType") }
        if let value = defaultObject { attributes.set(value, forKey: "CIAttributeDefault") }
        for (value, name) in [(minimum, "CIAttributeMin"), (maximum, "CIAttributeMax"), (sliderMinimum, "CIAttributeSliderMin"),
                              (sliderMaximum, "CIAttributeSliderMax"), (identity, "CIAttributeIdentity")] {
            if let value { attributes.set(NSNumber.make(double: value), forKey: name) }
        }
        return attributes
    }
}

/// The inputs a filter was given, read with its defaults.
struct FilterValues {
    let values: [String: NSObject]
    let spec: FilterSpec?

    private func input(_ key: String) -> FilterInput? { spec?.inputs.first { $0.key == key } }

    func image(_ key: String = "inputImage") -> ImageNode? {
        if let image = values[key]?.as(CIImage.self) { return image.node }
        return values[key]?.as(CISampler.self)?.sampler.image?.node
    }

    func number(_ key: String) -> Double {
        if let value = values[key], value.responds(to: "doubleValue") { return value.sendDoubleValue() }
        if case .number(let value)? = input(key)?.kind { return value }
        return 0
    }

    /// Unpremultiplied.
    func color(_ key: String) -> RGBA {
        if let color = values[key]?.as(CIColor.self) { return color.color.straight }
        if case .color(let r, let g, let b, let a)? = input(key)?.kind { return RGBA(Float(r), Float(g), Float(b), Float(a)) }
        return RGBA(0, 0, 0, 1)
    }

    func vector(_ key: String) -> [CGFloat] {
        if let vector = values[key]?.as(CIVector.self) { return vector.values }
        if case .vector(let values)? = input(key)?.kind { return values }
        return []
    }

    /// An NSValue of a CGAffineTransform, as iOS gives it, or an
    /// NSAffineTransform, as the Mac does.
    func transform(_ key: String = "inputTransform") -> CGAffineTransform {
        guard let value = values[key] else { return .identity }
        if let boxed = value.as(NSValue.self)?.unboxed(CGAffineTransform.self) { return boxed }
        return value.responds(to: "transformStruct") ? value.sendTransformStruct() : .identity
    }
}

/// A filter Perry renders.
struct FilterSpec {
    let name: String
    let categories: [String]
    let inputs: [FilterInput]
    let output: (FilterValues) -> ImageNode?

    /// "CIGaussianBlur" as "Gaussian Blur".
    var displayName: String { FilterSpec.words(name.hasPrefix("CI") ? String(name.dropFirst(2)) : name) }

    /// Words of a camel-case name.
    static func words(_ name: String) -> String {
        var out = ""
        var previous: Character?
        for character in name {
            if let previous, character.isUppercase, !previous.isUppercase { out.append(" ") }
            out.append(character)
            previous = character
        }
        return out
    }

    nonisolated(unsafe) static let byName: [String: FilterSpec] = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

    nonisolated(unsafe) static let all: [FilterSpec] = compositing + adjustments + geometry + effects + transitions

    // MARK: Compositing

    nonisolated(unsafe) static let compositing: [FilterSpec] = ImageCompositing.names.map { name in
        FilterSpec(name: name, categories: ["CICategoryCompositeOperation"], inputs: [.image(), .image("inputBackgroundImage")]) { values in
            guard let image = values.image() else { return nil }
            return ImageCompositing.node(named: name, image, values.image("inputBackgroundImage") ?? .empty)
        }
    }

    // MARK: Color

    static let luma = SIMD3<Float>(0.2125, 0.7154, 0.0721)

    static func rgb(_ c: RGBA) -> SIMD3<Float> { SIMD3(c.x, c.y, c.z) }
    static func with(_ rgb: SIMD3<Float>, _ alpha: Float) -> RGBA { RGBA(rgb.x, rgb.y, rgb.z, alpha) }

    nonisolated(unsafe) static let adjustments: [FilterSpec] = [
        FilterSpec(name: "CIColorControls", categories: ["CICategoryColorAdjustment"], inputs: [
            .image(),
            .number("inputSaturation", 1, min: 0, max: 2, identity: 1),
            .number("inputBrightness", 0, min: -1, max: 1, identity: 0),
            .number("inputContrast", 1, min: 0, max: 4, sliderMin: 0.25, identity: 1),
        ]) { values in
            let saturation = Float(values.number("inputSaturation")), brightness = Float(values.number("inputBrightness"))
            let contrast = Float(values.number("inputContrast"))
            return values.image()?.mapped { c in
                var color = rgb(c)
                let l = (color * luma).sum()
                color = l + (color - l) * saturation + brightness
                color = (color - 0.5) * contrast + 0.5
                return with(color, c.w)
            }
        },
        FilterSpec(name: "CIColorMatrix", categories: ["CICategoryColorAdjustment"], inputs: [
            .image(),
            .vector("inputRVector", [1, 0, 0, 0]), .vector("inputGVector", [0, 1, 0, 0]),
            .vector("inputBVector", [0, 0, 1, 0]), .vector("inputAVector", [0, 0, 0, 1]),
            .vector("inputBiasVector", [0, 0, 0, 0]),
        ]) { values in
            func four(_ key: String) -> RGBA {
                let v = values.vector(key)
                return RGBA((0..<4).map { $0 < v.count ? Float(v[$0]) : 0 })
            }
            let r = four("inputRVector"), g = four("inputGVector"), b = four("inputBVector"), a = four("inputAVector")
            let bias = four("inputBiasVector")
            return values.image()?.mapped { c in RGBA((r * c).sum(), (g * c).sum(), (b * c).sum(), (a * c).sum()) + bias }
        },
        FilterSpec(name: "CIHueAdjust", categories: ["CICategoryColorAdjustment"], inputs: [
            .image(), .number("inputAngle", 0, "CIAttributeTypeAngle", sliderMin: -.pi, sliderMax: .pi, identity: 0),
        ]) { values in
            let angle = values.number("inputAngle")
            let (cosine, sine) = (Float(cos(angle)), Float(sin(angle)))
            return values.image()?.mapped { c in
                // Turned about the gray axis in YIQ.
                let y = 0.299 * c.x + 0.587 * c.y + 0.114 * c.z
                let i0 = 0.596 * c.x - 0.274 * c.y - 0.322 * c.z, q0 = 0.211 * c.x - 0.523 * c.y + 0.312 * c.z
                let i = i0 * cosine - q0 * sine, q = i0 * sine + q0 * cosine
                return RGBA(y + 0.956 * i + 0.621 * q, y - 0.272 * i - 0.647 * q, y - 1.106 * i + 1.703 * q, c.w)
            }
        },
        FilterSpec(name: "CIExposureAdjust", categories: ["CICategoryColorAdjustment"], inputs: [
            .image(), .number("inputEV", 0, sliderMin: -10, sliderMax: 10, identity: 0),
        ]) { values in
            let gain = Float(pow(2, values.number("inputEV")))
            return values.image()?.mapped { c in with(rgb(c) * gain, c.w) }
        },
        FilterSpec(name: "CIGammaAdjust", categories: ["CICategoryColorAdjustment"], inputs: [
            .image(), .number("inputPower", 1, sliderMin: 0.25, sliderMax: 4, identity: 1),
        ]) { values in
            let power = Float(values.number("inputPower"))
            return values.image()?.mapped { c in RGBA(powf(c.x, power), powf(c.y, power), powf(c.z, power), c.w) }
        },
        FilterSpec(name: "CIColorInvert", categories: ["CICategoryColorEffect"], inputs: [.image()]) { values in
            values.image()?.mapped { c in RGBA(1 - c.x, 1 - c.y, 1 - c.z, c.w) }
        },
        FilterSpec(name: "CIColorMonochrome", categories: ["CICategoryColorEffect"], inputs: [
            .image(), .color("inputColor", 0.6, 0.45, 0.3), .number("inputIntensity", 1, min: 0, max: 1, identity: 0),
        ]) { values in
            let tint = rgb(values.color("inputColor")), intensity = Float(values.number("inputIntensity"))
            return values.image()?.mapped { c in
                // Black to the color at middle gray to white.
                let l = (rgb(c) * luma).sum()
                let mono = l < 0.5 ? 2 * l * tint : 1 - 2 * (1 - l) * (1 - tint)
                return with(rgb(c) + (mono - rgb(c)) * intensity, c.w)
            }
        },
        FilterSpec(name: "CIFalseColor", categories: ["CICategoryColorEffect"], inputs: [
            .image(), .color("inputColor0", 0.3, 0, 0), .color("inputColor1", 1, 0.9, 0.8),
        ]) { values in
            let low = values.color("inputColor0"), high = values.color("inputColor1")
            return values.image()?.mapped { c in
                let l = (rgb(c) * luma).sum()
                let mixed = low + (high - low) * l
                return with(rgb(mixed), c.w * mixed.w)
            }
        },
        FilterSpec(name: "CISepiaTone", categories: ["CICategoryColorEffect"], inputs: [
            .image(), .number("inputIntensity", 1, min: 0, max: 1, identity: 0),
        ]) { values in
            let intensity = Float(values.number("inputIntensity"))
            return values.image()?.mapped { c in
                let sepia = SIMD3<Float>(0.393 * c.x + 0.769 * c.y + 0.189 * c.z, 0.349 * c.x + 0.686 * c.y + 0.168 * c.z,
                                         0.272 * c.x + 0.534 * c.y + 0.131 * c.z)
                return with(rgb(c) + (sepia - rgb(c)) * intensity, c.w)
            }
        },
        FilterSpec(name: "CIConstantColorGenerator", categories: ["CICategoryGenerator"], inputs: [.color("inputColor", 1, 0, 0)]) { values in
            let c = values.color("inputColor")
            return .color(RGBA(c.x * c.w, c.y * c.w, c.z * c.w, c.w))
        },
    ]

    // MARK: Geometry

    nonisolated(unsafe) static let geometry: [FilterSpec] = [
        FilterSpec(name: "CIAffineTransform", categories: ["CICategoryGeometryAdjustment"], inputs: [.image(), .transform()]) { values in
            values.image()?.transformed(values.transform())
        },
        FilterSpec(name: "CIAffineClamp", categories: ["CICategoryTileEffect"], inputs: [.image(), .transform()]) { values in
            values.image()?.transformed(values.transform()).clamped()
        },
        FilterSpec(name: "CILanczosScaleTransform", categories: ["CICategoryGeometryAdjustment"], inputs: [
            .image(), .number("inputScale", 1, min: 0, sliderMin: 0.05, sliderMax: 1.5, identity: 1),
            .number("inputAspectRatio", 1, min: 0, sliderMin: 0.05, sliderMax: 2, identity: 1),
        ]) { values in
            let scale = CGFloat(values.number("inputScale")), aspect = CGFloat(values.number("inputAspectRatio"))
            guard scale > 0, aspect > 0 else { return .empty }
            return values.image()?.transformed(CGAffineTransform(a: scale * aspect, b: 0, c: 0, d: scale, tx: 0, ty: 0))
        },
        FilterSpec(name: "CICrop", categories: ["CICategoryGeometryAdjustment"], inputs: [
            .image(), .vector("inputRectangle", CIVector.rect(CoreImageGeometry.infinite), "CIAttributeTypeRectangle"),
        ]) { values in
            let v = values.vector("inputRectangle")
            guard v.count >= 4 else { return values.image() }
            return values.image()?.cropped(to: CGRect(x: v[0], y: v[1], width: v[2], height: v[3]))
        },
    ]

    // MARK: Blur and sharpening

    nonisolated(unsafe) static let effects: [FilterSpec] = [
        FilterSpec(name: "CIGaussianBlur", categories: ["CICategoryBlur"], inputs: [
            .image(), .number("inputRadius", 10, "CIAttributeTypeDistance", min: 0, sliderMax: 100, identity: 0),
        ]) { values in
            values.image()?.blurred(sigma: values.number("inputRadius"))
        },
        FilterSpec(name: "CISharpenLuminance", categories: ["CICategorySharpen"], inputs: [
            .image(), .number("inputSharpness", 0.4, min: 0, sliderMax: 2, identity: 0),
        ]) { values in
            guard let image = values.image() else { return nil }
            let amount = Float(values.number("inputSharpness"))
            // An unsharp mask of the image's own blur, its edges as they are.
            return ImageNode.combined(image, image.blurred(sigma: 1.6), extent: image.extent) { c, blurred, _, _ in
                with(rgb(c + (c - blurred) * amount), c.w)
            }
        },
    ]

    // MARK: Transitions

    static func transition(_ name: String, extra: [FilterInput] = [], _ body: ((FilterValues, ImageNode, ImageNode, Float) -> ImageNode)? = nil)
        -> FilterSpec {
        FilterSpec(name: name, categories: ["CICategoryTransition"],
                   inputs: [.image(), .image("inputTargetImage"), .number("inputTime", 0, "CIAttributeTypeTime", min: 0, max: 1, identity: 0)]
                       + extra) { values in
            guard let image = values.image() else { return nil }
            let target = values.image("inputTargetImage") ?? .empty
            let time = Float(min(max(values.number("inputTime"), 0), 1))
            if let body { return body(values, image, target, time) }
            // Others Perry dissolves.
            return .combined(image, target, extent: CoreImageGeometry.union(image.extent, target.extent)) { a, b, _, _ in a + (b - a) * time }
        }
    }

    nonisolated(unsafe) static let transitions: [FilterSpec] = [
        transition("CIDissolveTransition"),
        transition("CIDisintegrateWithMaskTransition", extra: [
            .image("inputMaskImage"), .number("inputShadowRadius", 8, "CIAttributeTypeDistance", min: 0, sliderMax: 50),
            .number("inputShadowDensity", 0.65, min: 0, max: 1), .vector("inputShadowOffset", [0, -10], "CIAttributeTypeOffset"),
        ]) { values, image, target, time in
            let mask = values.image("inputMaskImage") ?? .empty
            let extent = CoreImageGeometry.union(image.extent, target.extent)
            return ImageNode(extent: extent) { rect in
                let from = image.render(rect), to = target.render(rect), masked = mask.render(rect)
                var out = Pixels(rect)
                for i in out.data.indices {
                    // The target shows where the mask is darker than the time.
                    out.data[i] = (rgb(masked.data[i]) * luma).sum() < time ? to.data[i] : from.data[i]
                }
                return out
            }
        },
        transition("CISwipeTransition", extra: [
            .vector("inputExtent", [0, 0, 300, 300], "CIAttributeTypeRectangle"), .color("inputColor", 1, 1, 1),
            .number("inputAngle", 0, "CIAttributeTypeAngle", sliderMin: -.pi, sliderMax: .pi),
            .number("inputWidth", 300, "CIAttributeTypeDistance", min: 0.1, sliderMax: 1000), .number("inputOpacity", 0, min: 0, max: 1),
        ]) { values, image, target, time in
            // Left to right across the extent, whatever the angle.
            let extent = CoreImageGeometry.union(image.extent, target.extent)
            let v = values.vector("inputExtent")
            let across = v.count >= 4 && v[2] > 0 ? (Float(v[0]), Float(v[2])) : (Float(extent.minX), Float(extent.width))
            let edge = across.0 + across.1 * time
            return .combined(image, target, extent: extent) { a, b, x, _ in Float(x) < edge ? b : a }
        },
        transition("CICopyMachineTransition"), transition("CIFlashTransition"), transition("CIModTransition"),
        transition("CIPageCurlTransition"), transition("CIRippleTransition"), transition("CIBarsSwipeTransition"),
    ]
}

// MARK: - Compositing

/// The blend modes and Porter-Duff operators, on premultiplied pixels.
enum ImageCompositing {
    static let names = blendModes.map(\.0) + operators.map(\.0)

    typealias Blend = (SIMD3<Float>, SIMD3<Float>) -> SIMD3<Float>

    /// Each channel blended alike.
    static func separable(_ body: @escaping (Float, Float) -> Float) -> Blend {
        { b, s in SIMD3(body(b.x, s.x), body(b.y, s.y), body(b.z, s.z)) }
    }

    static func hardLight(_ b: Float, _ s: Float) -> Float { s <= 0.5 ? b * 2 * s : b + (2 * s - 1) - b * (2 * s - 1) }

    static func lum(_ c: SIMD3<Float>) -> Float { 0.3 * c.x + 0.59 * c.y + 0.11 * c.z }

    static func clipColor(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let l = lum(c), n = c.min(), x = c.max()
        var c = c
        if n < 0 { c = l + (c - l) * l / (l - n) }
        if x > 1 { c = l + (c - l) * (1 - l) / (x - l) }
        return c
    }

    static func setLum(_ c: SIMD3<Float>, _ l: Float) -> SIMD3<Float> { clipColor(c + (l - lum(c))) }
    static func sat(_ c: SIMD3<Float>) -> Float { c.max() - c.min() }

    static func setSat(_ c: SIMD3<Float>, _ s: Float) -> SIMD3<Float> {
        let low = c.min(), high = c.max()
        return high > low ? (c - low) * s / (high - low) : .zero
    }

    /// Backdrop and source colors, unpremultiplied, to the blend.
    nonisolated(unsafe) static let blendModes: [(String, Blend)] = [
        ("CIMultiplyBlendMode", separable { b, s in b * s }),
        ("CIScreenBlendMode", separable { b, s in b + s - b * s }),
        ("CIOverlayBlendMode", separable { b, s in hardLight(s, b) }),
        ("CIDarkenBlendMode", separable { b, s in min(b, s) }),
        ("CILightenBlendMode", separable { b, s in max(b, s) }),
        ("CIColorDodgeBlendMode", separable { b, s in b <= 0 ? 0 : s >= 1 ? 1 : min(1, b / (1 - s)) }),
        ("CIColorBurnBlendMode", separable { b, s in b >= 1 ? 1 : s <= 0 ? 0 : 1 - min(1, (1 - b) / s) }),
        ("CISoftLightBlendMode", separable { b, s in
            if s <= 0.5 { return b - (1 - 2 * s) * b * (1 - b) }
            let d = b <= 0.25 ? ((16 * b - 12) * b + 4) * b : sqrtf(b)
            return b + (2 * s - 1) * (d - b)
        }),
        ("CIHardLightBlendMode", separable { b, s in hardLight(b, s) }),
        ("CIDifferenceBlendMode", separable { b, s in abs(b - s) }),
        ("CIExclusionBlendMode", separable { b, s in b + s - 2 * b * s }),
        ("CIHueBlendMode", { b, s in setLum(setSat(s, sat(b)), lum(b)) }),
        ("CISaturationBlendMode", { b, s in setLum(setSat(b, sat(s)), lum(b)) }),
        ("CIColorBlendMode", { b, s in setLum(s, lum(b)) }),
        ("CILuminosityBlendMode", { b, s in setLum(b, lum(s)) }),
    ]

    /// Source and backdrop, premultiplied, to the result.
    nonisolated(unsafe) static let operators: [(String, (RGBA, RGBA) -> RGBA)] = [
        ("CISourceOverCompositing", { s, b in s + b * (1 - s.w) }),
        ("CISourceInCompositing", { s, b in s * b.w }),
        ("CISourceOutCompositing", { s, b in s * (1 - b.w) }),
        ("CISourceAtopCompositing", { s, b in s * b.w + b * (1 - s.w) }),
        ("CIMultiplyCompositing", { s, b in s * b }),
        ("CIAdditionCompositing", { s, b in s + b }),
        ("CIMinimumCompositing", { s, b in simd_min_rgba(s, b) }),
        ("CIMaximumCompositing", { s, b in simd_max_rgba(s, b) }),
    ]

    static func simd_min_rgba(_ a: RGBA, _ b: RGBA) -> RGBA { a.replacing(with: b, where: b .< a) }
    static func simd_max_rgba(_ a: RGBA, _ b: RGBA) -> RGBA { a.replacing(with: b, where: b .> a) }

    /// The source composited onto the backdrop by the named filter.
    static func node(named name: String, _ source: ImageNode, _ backdrop: ImageNode) -> ImageNode {
        if let blend = blendModes.first(where: { $0.0 == name })?.1 {
            let extent = CoreImageGeometry.union(source.extent, backdrop.extent)
            return .combined(source, backdrop, extent: extent) { s, b, _, _ in
                let cs = s.w > 0 ? FilterSpec.rgb(s) / s.w : .zero, cb = b.w > 0 ? FilterSpec.rgb(b) / b.w : .zero
                let mixed = Bitmaps.simd_clamp(FilterSpec.with(blend(cb, cs), 1))
                let color = FilterSpec.rgb(s) * (1 - b.w) + FilterSpec.rgb(b) * (1 - s.w) + s.w * b.w * FilterSpec.rgb(mixed)
                return FilterSpec.with(color, s.w + b.w - s.w * b.w)
            }
        }
        let operation = operators.first(where: { $0.0 == name })?.1 ?? operators[0].1
        let extent: CGRect
        switch name {
        case "CISourceInCompositing": extent = CoreImageGeometry.intersection(source.extent, backdrop.extent)
        case "CISourceOutCompositing": extent = source.extent
        case "CISourceAtopCompositing": extent = backdrop.extent
        default: extent = CoreImageGeometry.union(source.extent, backdrop.extent)
        }
        return .combined(source, backdrop, extent: extent) { s, b, _, _ in operation(s, b) }
    }
}

// MARK: - CIFilter

final class CIFilterState {
    var name = ""
    var values: [String: NSObject] = [:]
    var enabled = true
}

@ObjCClass("CIFilter")
open class CIFilter: NSObject {
    static let states = ObjectStates { CIFilterState() }
    var filter: CIFilterState { CIFilter.states[objcObject] }
    var spec: FilterSpec? { FilterSpec.byName[filter.name] }

    @ObjCMethod("dealloc")
    func dealloc() {
        CIFilter.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CIFilter.objCClass.pointer)
    }

    /// A filter of the name with its defaults set, as iOS gives one; a
    /// Mac app sets them again with -setDefaults.
    static func make(named name: String, cls: ObjCClass) -> CIFilter {
        let made = cls.object.allocated().initialized().unsafeCast(to: CIFilter.self)
        made.filter.name = name
        made.setDefaults()
        return made
    }

    /// An app's own subclass keeps its inputs as its properties, through
    /// NSObject's key-value coding.
    private var isSubclassInstance: Bool { ObjCRuntime.objectClass(objcObject) != CIFilter.objCClass.pointer }

    private static func nsObjectImplementation(_ selector: String) -> UnsafeRawPointer? {
        Methods.implementation(ObjCRuntime.classObject("NSObject"), ObjCRuntime.selector(selector))
    }

    func setValues(from parameters: NSDictionary?) {
        guard let parameters else { return }
        for key in parameters.allKeys().elements.map(\.stringValue) {
            setValue(parameters.object(forKey: key), forKey: key)
        }
    }

    // MARK: Creating

    @ObjCClassMethod("filterWithName:")
    static func filter(_ cls: ObjCClass, name: String?) -> CIFilter? { name.map { make(named: $0, cls: cls) } }

    @ObjCClassMethod("filterWithName:withInputParameters:")
    static func filter(_ cls: ObjCClass, name: String?, parameters: NSObject?) -> CIFilter? {
        guard let name else { return nil }
        let made = make(named: name, cls: cls)
        made.setValues(from: parameters?.as(NSDictionary.self))
        return made
    }

    /// The filters in every one of the categories; all for none. Each is
    /// built in, for still images and video alike.
    static func names(in categories: [String]) -> [String] {
        let everywhere: Set<String> = ["CICategoryBuiltIn", "CICategoryStillImage", "CICategoryVideo", "CICategoryNonSquarePixels"]
        return FilterSpec.all.filter { spec in categories.allSatisfy { everywhere.contains($0) || spec.categories.contains($0) } }.map(\.name)
    }

    @ObjCClassMethod("filterNamesInCategory:")
    static func filterNames(_ cls: ObjCClass, category: String?) -> NSObject {
        NSMutableArray.of(names(in: category.map { [$0] } ?? []).map(\.objectValue))
    }

    @ObjCClassMethod("filterNamesInCategories:")
    static func filterNames(_ cls: ObjCClass, categories: NSObject?) -> NSObject {
        let list = categories?.as(NSArray.self)?.elements.map(\.stringValue) ?? []
        return NSMutableArray.of(names(in: list).map(\.objectValue))
    }

    @ObjCClassMethod("localizedNameForFilterName:")
    static func localizedName(_ cls: ObjCClass, filterName: String?) -> String? {
        filterName.map { FilterSpec.byName[$0]?.displayName ?? $0 }
    }

    @ObjCClassMethod("localizedNameForCategory:")
    static func localizedName(_ cls: ObjCClass, category: String?) -> String? {
        category.map { FilterSpec.words($0.hasPrefix("CICategory") ? String($0.dropFirst(10)) : $0) }
    }

    @ObjCClassMethod("localizedDescriptionForFilterName:")
    static func localizedDescription(_ cls: ObjCClass, filterName: String?) -> String? { nil }

    @ObjCClassMethod("localizedReferenceDocumentationForFilterName:")
    static func localizedReferenceDocumentation(_ cls: ObjCClass, filterName: String?) -> NSObject? { nil }

    @ObjCClassMethod("registerFilterName:constructor:classAttributes:")
    static func register(_ cls: ObjCClass, name: String?, constructor: NSObject?, classAttributes: NSObject?) {}

    // MARK: Inputs

    @ObjCMethod("name") func name() -> String { filter.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { filter.name = name ?? "" }
    @ObjCMethod("isEnabled") func isEnabled() -> Bool { filter.enabled }
    @ObjCMethod("setEnabled:") func setEnabled(_ enabled: Bool) { filter.enabled = enabled }

    @ObjCMethod("setDefaults")
    func setDefaults() {
        guard !isSubclassInstance, let spec else { return }
        for input in spec.inputs { if let value = input.defaultObject { filter.values[input.key] = value } }
    }

    @ObjCMethod("inputKeys")
    func inputKeys() -> NSObject { NSMutableArray.of((spec?.inputs.map(\.key) ?? ["inputImage"]).map(\.objectValue)) }

    @ObjCMethod("outputKeys") func outputKeys() -> NSObject { NSMutableArray.of(["outputImage".objectValue]) }

    @ObjCMethod("attributes")
    func attributes() -> NSObject {
        let attributes = NSMutableDictionary.empty()
        let name = filter.name
        attributes.set(name.objectValue, forKey: "CIAttributeFilterName")
        attributes.set((spec?.displayName ?? name).objectValue, forKey: "CIAttributeFilterDisplayName")
        let categories = (spec?.categories ?? []) + ["CICategoryBuiltIn", "CICategoryStillImage", "CICategoryVideo"]
        attributes.set(NSMutableArray.of(categories.map(\.objectValue)), forKey: "CIAttributeFilterCategories")
        for input in spec?.inputs ?? [.image()] { attributes.set(input.attributes, forKey: input.key) }
        return attributes
    }

    @ObjCMethod("setValue:forKey:")
    func setValue(_ value: NSObject?, forKey key: String) {
        if isSubclassInstance, let implementation = CIFilter.nsObjectImplementation("setValue:forKey:") {
            typealias Set = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
            unsafeBitCast(implementation, to: Set.self)(objcObject, ObjCRuntime.selector("setValue:forKey:"), value?.objcObject,
                                                        key.objCArgument())
            return
        }
        filter.values[key] = value
    }

    @ObjCMethod("valueForKey:")
    func value(forKey key: String) -> NSObject? {
        if isSubclassInstance, let implementation = CIFilter.nsObjectImplementation("valueForKey:") {
            typealias Get = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
            return unsafeBitCast(implementation, to: Get.self)(objcObject, ObjCRuntime.selector("valueForKey:"), key.objCArgument())
                .map { NSObject($0) }
        }
        switch key {
        case "outputImage": return outputImage()
        case "name": return filter.name.objectValue
        case "attributes": return attributes()
        case "inputKeys": return inputKeys()
        case "outputKeys": return outputKeys()
        default: return filter.values[key]
        }
    }

    @ObjCMethod("setValuesForKeysWithDictionary:")
    func setValuesForKeys(_ dictionary: NSObject?) { setValues(from: dictionary?.as(NSDictionary.self)) }

    // MARK: Output

    /// The inputs worked by the filter; the input image for one Perry
    /// doesn't render.
    @ObjCMethod("outputImage")
    func outputImage() -> CIImage? {
        let values = FilterValues(values: filter.values, spec: spec)
        guard filter.enabled, let spec else { return values.values["inputImage"]?.as(CIImage.self) }
        return spec.output(values).map { CIImage.make($0) }
    }

    /// A kernel's result: Perry runs no kernels, so the first image the
    /// kernel would sample.
    @ObjCMethod("apply:arguments:options:")
    func apply(_ kernel: NSObject?, arguments: NSObject?, options: NSObject?) -> CIImage? {
        for argument in arguments?.as(NSArray.self)?.elements ?? [] {
            if let image = argument.as(CIImage.self) { return image }
            if let image = argument.as(CISampler.self)?.sampler.image { return image }
        }
        return nil
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let cls = ObjCRuntime.objectClass(objcObject) else { return nil }
        let copy = ObjCClass(cls).object.allocated().initialized().unsafeCast(to: CIFilter.self)
        copy.filter.name = filter.name
        copy.filter.values = filter.values
        copy.filter.enabled = filter.enabled
        return copy.objCOwnedReturnValue()
    }
}
