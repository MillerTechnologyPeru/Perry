import Foundation

// MTL4Compiler's Swift API: the synchronous calls throw, the asynchronous
// ones wrap the completion-handler forms.

/// Resumes a continuation from a completion handler's result and error.
private func resume<T>(_ continuation: CheckedContinuation<T, Error>, _ result: T?, _ error: Error?) {
    if let result {
        continuation.resume(returning: result)
    } else {
        continuation.resume(throwing: error ?? NSError(domain: MTLLibraryErrorDomain, code: Int(MTLLibraryError.Code.internal.rawValue)))
    }
}

/// An object handed to a continuation across concurrency domains.
private struct Unchecked<T>: @unchecked Sendable {
    let value: T
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension MTL4Compiler {
    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeComputePipelineState(descriptor: MTL4ComputePipelineDescriptor,
                                         dynamicLinkingDescriptor: MTL4PipelineStageDynamicLinkingDescriptor? = nil,
                                         compilerTaskOptions: MTL4CompilerTaskOptions? = nil) throws -> MTLComputePipelineState {
        if let dynamicLinkingDescriptor {
            return try __newComputePipelineState(with: descriptor, dynamicLinkingDescriptor: dynamicLinkingDescriptor, compilerTaskOptions: compilerTaskOptions)
        }
        return try __newComputePipelineState(with: descriptor, compilerTaskOptions: compilerTaskOptions)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeComputePipelineState(descriptor: MTL4ComputePipelineDescriptor,
                                         dynamicLinkingDescriptor: MTL4PipelineStageDynamicLinkingDescriptor? = nil,
                                         compilerTaskOptions: MTL4CompilerTaskOptions? = nil) async throws -> MTLComputePipelineState {
        let arguments = Unchecked(value: (self, descriptor, dynamicLinkingDescriptor, compilerTaskOptions))
        let state: Unchecked<MTLComputePipelineState> = try await withCheckedThrowingContinuation { continuation in
            let (compiler, descriptor, linking, options) = arguments.value
            let handler: (MTLComputePipelineState?, Error?) -> Void = { state, error in
                resume(continuation, state.map { Unchecked(value: $0) }, error)
            }
            if let linking {
                _ = compiler.__newComputePipelineState(with: descriptor, dynamicLinkingDescriptor: linking, compilerTaskOptions: options, completionHandler: handler)
            } else {
                _ = compiler.__newComputePipelineState(with: descriptor, compilerTaskOptions: options, completionHandler: handler)
            }
        }
        return state.value
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeRenderPipelineState(descriptor: MTL4PipelineDescriptor,
                                        dynamicLinkingDescriptor: MTL4RenderPipelineDynamicLinkingDescriptor? = nil,
                                        compilerTaskOptions: MTL4CompilerTaskOptions? = nil) throws -> MTLRenderPipelineState {
        if let dynamicLinkingDescriptor {
            return try __newRenderPipelineState(with: descriptor, dynamicLinkingDescriptor: dynamicLinkingDescriptor, compilerTaskOptions: compilerTaskOptions)
        }
        return try __newRenderPipelineState(with: descriptor, compilerTaskOptions: compilerTaskOptions)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeRenderPipelineState(descriptor: MTL4PipelineDescriptor,
                                        dynamicLinkingDescriptor: MTL4RenderPipelineDynamicLinkingDescriptor? = nil,
                                        compilerTaskOptions: MTL4CompilerTaskOptions? = nil) async throws -> MTLRenderPipelineState {
        let arguments = Unchecked(value: (self, descriptor, dynamicLinkingDescriptor, compilerTaskOptions))
        let state: Unchecked<MTLRenderPipelineState> = try await withCheckedThrowingContinuation { continuation in
            let (compiler, descriptor, linking, options) = arguments.value
            let handler: (MTLRenderPipelineState?, Error?) -> Void = { state, error in
                resume(continuation, state.map { Unchecked(value: $0) }, error)
            }
            if let linking {
                _ = compiler.__newRenderPipelineState(with: descriptor, dynamicLinkingDescriptor: linking, compilerTaskOptions: options, completionHandler: handler)
            } else {
                _ = compiler.__newRenderPipelineState(with: descriptor, compilerTaskOptions: options, completionHandler: handler)
            }
        }
        return state.value
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeRenderPipelineStateBySpecialization(descriptor: MTL4PipelineDescriptor, pipeline: MTLRenderPipelineState) throws -> MTLRenderPipelineState {
        try __newRenderPipelineStateBySpecialization(with: descriptor, pipeline: pipeline)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeRenderPipelineStateBySpecialization(descriptor: MTL4PipelineDescriptor, pipeline: MTLRenderPipelineState) async throws -> MTLRenderPipelineState {
        let arguments = Unchecked(value: (self, descriptor, pipeline))
        let state: Unchecked<MTLRenderPipelineState> = try await withCheckedThrowingContinuation { continuation in
            let (compiler, descriptor, pipeline) = arguments.value
            _ = compiler.__newRenderPipelineStateBySpecialization(with: descriptor, pipeline: pipeline) { state, error in
                resume(continuation, state.map { Unchecked(value: $0) }, error)
            }
        }
        return state.value
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeBinaryFunction(descriptor: MTL4BinaryFunctionDescriptor, compilerTaskOptions: MTL4CompilerTaskOptions? = nil) throws -> MTL4BinaryFunction {
        try __newBinaryFunction(with: descriptor, compilerTaskOptions: compilerTaskOptions)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeBinaryFunction(descriptor: MTL4BinaryFunctionDescriptor, compilerTaskOptions: MTL4CompilerTaskOptions? = nil) async throws -> MTL4BinaryFunction {
        let arguments = Unchecked(value: (self, descriptor, compilerTaskOptions))
        let function: Unchecked<MTL4BinaryFunction> = try await withCheckedThrowingContinuation { continuation in
            let (compiler, descriptor, options) = arguments.value
            _ = compiler.__newBinaryFunction(with: descriptor, compilerTaskOptions: options) { function, error in
                resume(continuation, function.map { Unchecked(value: $0) }, error)
            }
        }
        return function.value
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeLibrary(descriptor: MTL4LibraryDescriptor) async throws -> MTLLibrary {
        let arguments = Unchecked(value: (self, descriptor))
        let library: Unchecked<MTLLibrary> = try await withCheckedThrowingContinuation { continuation in
            let (compiler, descriptor) = arguments.value
            _ = compiler.__newLibrary(with: descriptor) { library, error in
                resume(continuation, library.map { Unchecked(value: $0) }, error)
            }
        }
        return library.value
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeDynamicLibrary(library: MTLLibrary) async throws -> MTLDynamicLibrary {
        let arguments = Unchecked(value: (self, library))
        let dynamic: Unchecked<MTLDynamicLibrary> = try await withCheckedThrowingContinuation { continuation in
            let (compiler, library) = arguments.value
            _ = compiler.__newDynamicLibrary(library) { dynamic, error in
                resume(continuation, dynamic.map { Unchecked(value: $0) }, error)
            }
        }
        return dynamic.value
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeDynamicLibrary(url: URL) async throws -> MTLDynamicLibrary {
        let arguments = Unchecked(value: (self, url))
        let dynamic: Unchecked<MTLDynamicLibrary> = try await withCheckedThrowingContinuation { continuation in
            let (compiler, url) = arguments.value
            _ = compiler.__newDynamicLibrary(with: url) { dynamic, error in
                resume(continuation, dynamic.map { Unchecked(value: $0) }, error)
            }
        }
        return dynamic.value
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeMachineLearningPipelineState(descriptor: MTL4MachineLearningPipelineDescriptor) throws -> MTL4MachineLearningPipelineState {
        try __newMachineLearningPipelineState(with: descriptor)
    }

    @available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public func makeMachineLearningPipelineState(descriptor: MTL4MachineLearningPipelineDescriptor) async throws -> MTL4MachineLearningPipelineState {
        let arguments = Unchecked(value: (self, descriptor))
        let state: Unchecked<MTL4MachineLearningPipelineState> = try await withCheckedThrowingContinuation { continuation in
            let (compiler, descriptor) = arguments.value
            _ = compiler.__newMachineLearningPipelineState(with: descriptor) { state, error in
                resume(continuation, state.map { Unchecked(value: $0) }, error)
            }
        }
        return state.value
    }
}
