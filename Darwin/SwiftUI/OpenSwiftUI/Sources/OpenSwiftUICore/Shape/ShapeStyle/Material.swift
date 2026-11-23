//
//  Material.swift
//  OpenSwiftUICore
//
//  Audited for 6.0.87
//  Status: WIP
//  ID: B2CCB444DA7C00CFB13A219298A4122C (SwiftUICore)

package import Foundation

// MARK: Material

/// A background material type.
///
/// You can apply a blur effect to a view that appears behind another view by
/// adding a material with the ``View/background(_:ignoresSafeAreaEdges:)``
/// modifier:
///
///     ZStack {
///         Color.teal
///         Label("Flag", systemImage: "flag.fill")
///             .padding()
///             .background(.regularMaterial)
///     }
///
/// In the example above, the ``ZStack`` layers a ``Label`` on top of the color
/// ``ShapeStyle/teal``. The background modifier inserts the
/// regular material below the label, blurring the part of
/// the background that the label --- including its padding --- covers:
///
/// ![A screenshot of a label on a teal background, where the area behind
/// the label appears blurred.](Material-1)
///
/// A material isn't a view, but adding a material is like inserting a
/// translucent layer between the modified view and its background:
///
/// ![An illustration that shows a background layer below a material layer,
/// which in turn appears below a foreground layer.](Material-2)
///
/// The blurring effect provided by the material isn't simple opacity. Instead,
/// it uses a platform-specific blending that produces an effect that resembles
/// heavily frosted glass. You can see this more easily with a complex
/// background, like an image:
///
///     ZStack {
///         Image("chili_peppers")
///             .resizable()
///             .aspectRatio(contentMode: .fit)
///         Label("Flag", systemImage: "flag.fill")
///             .padding()
///             .background(.regularMaterial)
///     }
///
/// ![A screenshot of a label on an image background, where the area behind
/// the label appears blurred.](Material-3)
///
/// For physical materials, the degree to which the background colors pass
/// through depends on the thickness. The effect also varies with light and
/// dark appearance:
///
/// ![An array of labels on a teal background. The first column, labeled light
/// appearance, shows a succession of labels on blurred backgrounds where the
/// blur increases from top to bottom, resulting in lighter and lighter blur.
/// The second column, labeled dark appearance, shows a similar succession of
/// labels, except that the blur gets darker from top to bottom. The rows are
/// labeled, from top to bottom: no material, ultra thin, thin, regular, thick,
/// and ultra thick.](Material-4)
///
/// If you need a material to have a particular shape, you can use the
/// ``View/background(_:in:fillStyle:)`` modifier. For example, you can
/// create a material with rounded corners:
///
///     ZStack {
///         Color.teal
///         Label("Flag", systemImage: "flag.fill")
///             .padding()
///             .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
///     }
///
/// ![A screenshot of a label on a teal background, where the area behind
/// the label appears blurred. The blurred area has rounded corners.](Material-5)
///
/// When you add a material, foreground elements exhibit vibrancy,
/// a context-specific blend of the foreground and background colors
/// that improves contrast. However using ``View/foregroundStyle(_:)``
/// to set a custom foreground style --- excluding the hierarchical styles,
/// like ``ShapeStyle/secondary-swift.type.property`` --- disables vibrancy.
///
/// > Note: A material blurs a background that's part of your app, but not
/// what appears behind your app on the screen.
/// For example, the content on the Home Screen doesn't affect the appearance
/// of a widget.
public struct Material: Sendable {
    package enum ID: Hashable {
        case ultraThin
        case thin
        case regular
        case thick
        case ultraThick
        case systemBars
        case intelligenceLightSource_Unreactive
        case intelligenceLightSource_AudioReactive
        indirect case coreMaterial(light: String, dark: String, bundle: Bundle?)
    }

    package struct ResolvedMaterial: Hashable {
        package struct Flags: OptionSet, Hashable {
            package let rawValue: UInt32

            package init(rawValue: UInt32) { self.rawValue = rawValue }

            package static let darkColorScheme = Flags(rawValue: 1 << 0)

            package static let reduceTransparency = Flags(rawValue: 1 << 1)

            package static let increasedContrast = Flags(rawValue: 1 << 2)

            package static let disableChameleon = Flags(rawValue: 1 << 3)

            package static let isActive = Flags(rawValue: 1 << 4)

            package static let noBlur = Flags(rawValue: 1 << 5)

            package static let isEmphasized = Flags(rawValue: 1 << 6)

            package static let filtersInPlace = Flags(rawValue: 1 << 7)

            package static let noTransparentBlur = Flags(rawValue: 1 << 8)

            package static let isVisionEnabled = Flags(rawValue: 1 << 9)

            package static let noNormalizedEdgesBlur = Flags(rawValue: 1 << 10)

            package static let applyHardEdgesBlur = Flags(rawValue: 1 << 11)

            package init(environment: EnvironmentValues) {
                var flags = Flags()
                if environment.colorScheme == .dark {
                    flags.insert(.darkColorScheme)
                }
                if environment.accessibilityReduceTransparency {
                    flags.insert(.reduceTransparency)
                }
                if environment.colorSchemeContrast == .increased {
                    flags.insert(.increasedContrast)
                }
                self = flags
            }
        }

        package var id: Material.ID

        package var flags: Material.ResolvedMaterial.Flags

        package var colorScheme: ColorScheme {
            flags.contains(.darkColorScheme) ? .dark : .light
        }

        package var colorSchemeContrast: ColorSchemeContrast {
            flags.contains(.increasedContrast) ? .increased : .standard
        }

        package var isEmphasized: Swift.Bool {
            flags.contains(.isEmphasized)
        }
    }

    package var id: Material.ID

    package var flags: Material.ResolvedMaterial.Flags

    package init(id: Material.ID) {
        self.id = id
        self.flags = []
    }

    package func resolve(in env: EnvironmentValues, role: ShapeRole? = nil) -> Material.ResolvedMaterial {
        ResolvedMaterial(
            id: id,
            flags: Material.ResolvedMaterial.Flags(environment: env).union(flags)
        )
    }
}

extension Material: ShapeStyle {
    /// A material that's somewhat translucent.
    public static let regular = Material(id: .regular)

    /// A material that's more opaque than translucent.
    public static let thick = Material(id: .thick)

    /// A material that's more translucent than opaque.
    public static let thin = Material(id: .thin)

    /// A mostly translucent material.
    public static let ultraThin = Material(id: .ultraThin)

    /// A mostly opaque material.
    public static let ultraThick = Material(id: .ultraThick)

    /// Fills the shape with the material as it resolves where the shape
    /// is: what is behind the shape, blurred, under the material's tint.
    public func _apply(to shape: inout _ShapeStyle_Shape) {
        switch shape.operation {
        case let .resolveStyle(name, levels):
            guard levels.lowerBound != levels.upperBound else {
                break
            }
            shape.stylePack[name, levels.lowerBound] = .init(.backgroundMaterial(resolve(in: shape.environment)))
        case .fallbackColor:
            // Where only a color can be drawn: the material's own, with
            // nothing showing through.
            shape.result = .color(shape.environment.colorScheme == .dark
                ? Color(red: 0.17, green: 0.17, blue: 0.18)
                : Color(red: 0.95, green: 0.95, blue: 0.97))
        default:
            break
        }
    }

    public typealias Resolved = Never
}

extension ShapeStyle where Self == Material {
    /// A material that's somewhat translucent.
    @_alwaysEmitIntoClient
    public static var regularMaterial: Material { .regular }

    /// A material that's more opaque than translucent.
    @_alwaysEmitIntoClient
    public static var thickMaterial: Material { .thick }

    /// A material that's more translucent than opaque.
    @_alwaysEmitIntoClient
    public static var thinMaterial: Material { .thin }

    /// A mostly translucent material.
    @_alwaysEmitIntoClient
    public static var ultraThinMaterial: Material { .ultraThin }

    /// A mostly opaque material.
    @_alwaysEmitIntoClient
    public static var ultraThickMaterial: Material { .ultraThick }
}

package struct ForegroundMaterialStyle: ShapeStyle, PrimitiveShapeStyle {
    package var material: Material

    package init(material: Material) {
        self.material = material
    }

    package func _apply(to shape: inout _ShapeStyle_Shape) {
        // TODO: CoreMaterial
        _openSwiftUIUnimplementedWarning()
        SystemColorsStyle()._apply(to: &shape)
    }

    package typealias Resolved = Swift.Never
}

private struct BackgroundMaterialKey: EnvironmentKey {
    static var defaultValue: Material? { nil }
}

extension EnvironmentValues {
    /// The material underneath the current view.
    ///
    /// This value is `nil` if the current background isn't one of the standard
    /// materials. If you set a material, the standard content styles enable
    /// their vibrant rendering modes.
    ///
    /// You set this value by calling one of the background modifiers that takes
    /// a ``ShapeStyle``, like ``View/background(_:ignoresSafeAreaEdges:)``
    /// or ``View/background(_:in:fillStyle:)``, and passing in a
    /// ``Material``. You can also set the value manually, using
    /// `nil` to disable vibrant rendering, or a ``Material`` instance to
    /// enable the vibrancy style associated with the specified material.
    public var backgroundMaterial: Material? {
        get { self[BackgroundMaterialKey.self] }
        set { self[BackgroundMaterialKey.self] = newValue }
  }
}
