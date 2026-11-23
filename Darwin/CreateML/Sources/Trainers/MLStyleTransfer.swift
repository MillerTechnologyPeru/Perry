// MLStyleTransfer: its parameters, data sources and options, which work in Perry,
// and its training, prediction and export, which need Apple's private
// engine and throw MLCreateError.generic saying so (see README.md). Its
// instance members are never reached: no instance can be made.

import CoreGraphics
import CoreML
import Foundation
import Vision

@available(macOS 11.0, iOS 15.0, *)
@available(tvOS, unavailable)
public struct MLStyleTransfer : Sendable {
    public init(trainingData: MLStyleTransfer.DataSource, parameters: MLStyleTransfer.ModelParameters = .init()) throws {
        throw trainingUnavailable(Self.self)
    }
    public init(checkpoint: MLCheckpoint) throws {
        throw trainingUnavailable(Self.self)
    }
    public static func train(trainingData: MLStyleTransfer.DataSource, parameters: MLStyleTransfer.ModelParameters = .init(), sessionParameters: MLTrainingSessionParameters = .init()) throws -> MLJob<MLStyleTransfer> {
        throw trainingUnavailable(Self.self)
    }
    public static func makeTrainingSession(trainingData: MLStyleTransfer.DataSource, parameters: MLStyleTransfer.ModelParameters = .init(), sessionParameters: MLTrainingSessionParameters = .init()) throws -> MLTrainingSession<MLStyleTransfer> {
        throw trainingUnavailable(Self.self)
    }
    public static func restoreTrainingSession(sessionParameters: MLTrainingSessionParameters) throws -> MLTrainingSession<MLStyleTransfer> {
        throw trainingUnavailable(Self.self)
    }
    public static func resume(_ session: MLTrainingSession<MLStyleTransfer>) throws -> MLJob<MLStyleTransfer> {
        throw trainingUnavailable(Self.self)
    }
    public func stylize(image: CGImage) throws -> CGImage? {
        throw unavailable("Running \(Self.self)")
    }
    public func write(to fileURL: URL, metadata: MLModelMetadata? = .init()) throws {
        throw unavailable("Exporting \(Self.self)")
    }
    public func write(toFile path: String, metadata: MLModelMetadata? = .init()) throws {
        throw unavailable("Exporting \(Self.self)")
    }
    @available(macOS 12.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public static func downloadAssets() throws {
        throw unavailable("Running \(Self.self)")
    }
}

@available(macOS 11.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLStyleTransfer : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            "\(Self.self): not trained. \(trainingUnavailable(Self.self).failureReason ?? "")"
        }
    }
    public var debugDescription: String {
        get {
            "\(Self.self): not trained. \(trainingUnavailable(Self.self).failureReason ?? "")"
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(macOS 11.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLStyleTransfer {
    public struct __Defaults : Sendable {
        public static var maxIterations: Int { 500 }
        public static var textelDensity: Int { 256 }
        public static var styleStrength: Int { 5 }
    }
}

extension MLStyleTransfer {
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public enum DataSource : Sendable {
        case images(styleImage: URL, contentDirectory: URL, processingOption: VNImageCropAndScaleOption? = .centerCrop)
        public func processImages(textelDensity: Int, styleImageDestination: URL? = nil, contentImagesDestination: URL? = nil) throws -> (processedStyleImage: URL, processedContentImages: URL) {
            throw unavailable("Processing style transfer images")
        }
    }
}

extension MLStyleTransfer {
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public struct ModelParameters : Sendable {
        public var algorithm: MLStyleTransfer.ModelParameters.ModelAlgorithmType
        public var validation: MLStyleTransfer.ModelParameters.ValidationData
        public var maxIterations: Int
        public var textelDensity: Int
        public var styleStrength: Int
        public init(algorithm: MLStyleTransfer.ModelParameters.ModelAlgorithmType = .cnn, validation: MLStyleTransfer.ModelParameters.ValidationData = .none, maxIterations: Int = MLStyleTransfer.__Defaults.maxIterations, textelDensity: Int = MLStyleTransfer.__Defaults.textelDensity, styleStrength: Int = MLStyleTransfer.__Defaults.styleStrength) {
            self.algorithm = algorithm
            self.validation = validation
            self.maxIterations = maxIterations
            self.textelDensity = textelDensity
            self.styleStrength = styleStrength
        }
        public enum ModelAlgorithmType : String, Sendable {
            case cnn
            case cnnLite
            @available(macOS 11.0, iOS 15.0, *)
            @available(tvOS, unavailable)
            public typealias RawValue = String
        }
    }
}

@available(macOS 11.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLStyleTransfer.ModelParameters : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            "ModelParameters(algorithm: \(String(describing: algorithm)), validation: \(String(describing: validation)), maxIterations: \(String(describing: maxIterations)), textelDensity: \(String(describing: textelDensity)), styleStrength: \(String(describing: styleStrength)))"
        }
    }
    public var debugDescription: String {
        get {
            "ModelParameters(algorithm: \(String(describing: algorithm)), validation: \(String(describing: validation)), maxIterations: \(String(describing: maxIterations)), textelDensity: \(String(describing: textelDensity)), styleStrength: \(String(describing: styleStrength)))"
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

@available(macOS 11.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLStyleTransfer.ModelParameters.ModelAlgorithmType : CustomStringConvertible, CustomDebugStringConvertible, CustomPlaygroundDisplayConvertible {
    public var description: String {
        get {
            switch self {
            case .cnn: return "cnn"
            case .cnnLite: return "cnnLite"
            }
        }
    }
    public var debugDescription: String {
        get {
            switch self {
            case .cnn: return "cnn"
            case .cnnLite: return "cnnLite"
            }
        }
    }
    public var playgroundDescription: Any {
        get {
            description
        }
    }
}

extension MLStyleTransfer.ModelParameters {
    @available(macOS 11.0, iOS 15.0, *)
    @available(tvOS, unavailable)
    public enum ValidationData : Sendable {
        case content(URL)
        case none
    }
}

@available(macOS 11.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLStyleTransfer.ModelParameters.ValidationData : Equatable {
}

@available(macOS 11.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLStyleTransfer.ModelParameters.ModelAlgorithmType : Equatable {}

@available(macOS 11.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLStyleTransfer.ModelParameters.ModelAlgorithmType : Hashable {}

@available(macOS 11.0, iOS 15.0, *)
@available(tvOS, unavailable)
extension MLStyleTransfer.ModelParameters.ModelAlgorithmType : RawRepresentable {}
