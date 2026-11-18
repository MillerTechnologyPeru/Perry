//
//  ShaderLibrary.swift
//  OpenSwiftUICore
//
//  Status: Perry's implementation
//
//  Shader libraries, their functions, and the arguments a shader is called
//  with. Perry compiles and runs no Metal shader functions: a library names
//  where its functions would come from, a function names one of them, and
//  calling it gives a shader that draws nothing. Effects that take a shader
//  leave what they are applied to as it is. These sit with `Shader` because
//  its nested types have to be declared in its module.

public import Foundation

// MARK: - ShaderLibrary

/// A Metal shader library: where shader functions are looked up by name.
@available(OpenSwiftUI_v1_0, *)
@dynamicMemberLookup
public struct ShaderLibrary: @unchecked Sendable {
    /// The bundle whose default library the functions belong to.
    var source: Bundle

    /// The default shader library of `bundle`. The library isn't opened.
    public static func bundle(_ bundle: Bundle) -> ShaderLibrary {
        ShaderLibrary(source: bundle)
    }

    /// The function called `name` in the library. Nothing checks that the
    /// library has one.
    public subscript(dynamicMember name: String) -> ShaderFunction {
        ShaderFunction(library: self, name: name)
    }
}

// MARK: - ShaderFunction

/// A function in a shader library, by name.
@available(OpenSwiftUI_v1_0, *)
@dynamicCallable
public struct ShaderFunction: Sendable {
    /// The library the function is in.
    public var library: ShaderLibrary

    /// The function's name.
    public var name: String

    /// The function called `name` in `library`.
    public init(library: ShaderLibrary, name: String) {
        self.library = library
        self.name = name
    }

    /// A shader that calls the function with `args`. The shader keeps
    /// neither the function nor the arguments, as nothing would run them.
    public func dynamicallyCall(withArguments args: [Shader.Argument]) -> Shader {
        Shader()
    }
}

// MARK: - Shader.Argument

@available(OpenSwiftUI_v1_0, *)
extension Shader {
    /// A value passed to a shader function.
    public struct Argument: Sendable {
        enum Storage: Sendable {
            case float(Float)
            case float2(Float, Float)
            case floatArray([Float])
            case colorArray([Color])
        }

        var storage: Storage

        /// A single float; the generic `float(_:)` an app calls converts
        /// its value and comes here.
        @usableFromInline
        internal static func _float(_ x: Float) -> Shader.Argument {
            Argument(storage: .float(x))
        }

        /// A pair of floats, as `float2(_:_:)` and its point, size and
        /// vector forms pass them.
        @usableFromInline
        internal static func _float2(_ x: Float, _ y: Float) -> Shader.Argument {
            Argument(storage: .float2(x, y))
        }

        /// An array of floats.
        public static func floatArray(_ array: [Float]) -> Shader.Argument {
            Argument(storage: .floatArray(array))
        }

        /// An array of colors.
        public static func colorArray(_ array: [Color]) -> Shader.Argument {
            Argument(storage: .colorArray(array))
        }
    }
}

// MARK: - Shader.UsageType

@available(OpenSwiftUI_v1_0, *)
extension Shader {
    /// What a shader is used for, which decides how it would be compiled.
    public struct UsageType: Hashable, Sendable {
        var rawValue: Int

        /// A shader that maps each pixel's color to another.
        public static var colorEffect: Shader.UsageType { UsageType(rawValue: 1) }
    }

    /// Compiles the shader ahead of its first use. There is nothing to
    /// compile, so this returns at once and never throws.
    public func compile(as type: Shader.UsageType) async throws {}
}

// MARK: - VisualEffect + colorEffect

@available(OpenSwiftUI_v1_0, *)
extension VisualEffect {
    /// A visual effect that would filter each pixel's color through
    /// `shader`: the effect is returned unchanged.
    public func colorEffect(_ shader: Shader, isEnabled: Bool = true) -> some VisualEffect {
        self
    }
}
