import PerryObjCInterop

/// GL_APPLE_framebuffer_multisample, which every iOS GPU has and no other
/// has: programs draw into multisampled renderbuffers and resolve them into
/// the drawable's before presenting it. The storage is OpenGL ES 3's, whose
/// read and draw framebuffer bindings are Apple's by the same numbers, and
/// the resolve is a blit of the read framebuffer's color buffer.
enum GLMultisample {
    typealias Storage = @convention(c) (UInt32, Int32, UInt32, Int32, Int32) -> Void
    typealias Resolve = @convention(c) () -> Void
    typealias Blit = @convention(c) (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32) -> Void
    typealias GetAttachment = @convention(c) (UInt32, UInt32, UInt32, UnsafeMutablePointer<Int32>?) -> Void

    static let name = "GL_APPLE_framebuffer_multisample"

    nonisolated(unsafe) static var storage: Storage?
    nonisolated(unsafe) static var blit: Blit?
    nonisolated(unsafe) static var getAttachment: GetAttachment?

    /// Whether the host has what the extension is made of.
    static func bind(_ host: (String) -> UnsafeMutableRawPointer?) -> Bool {
        if storage == nil { storage = host("glRenderbufferStorageMultisample").map { unsafeBitCast($0, to: Storage.self) } }
        if blit == nil { blit = host("glBlitFramebuffer").map { unsafeBitCast($0, to: Blit.self) } }
        if getAttachment == nil {
            getAttachment = host("glGetFramebufferAttachmentParameteriv").map { unsafeBitCast($0, to: GetAttachment.self) }
        }
        return storage != nil && blit != nil && getAttachment != nil
    }

    /// glRenderbufferStorageMultisampleAPPLE, with no more samples than the
    /// host has: asking for more is an error there.
    static let renderbufferStorageMultisample: Storage = { target, samples, format, width, height in
        var most: Int32 = 0
        GLES.getIntegerv(0x8D57, &most)     // GL_MAX_SAMPLES
        storage?(target, most > 0 ? min(samples, most) : samples, format, width, height)
    }

    /// glResolveMultisampleFramebufferAPPLE: the whole of the read
    /// framebuffer's color renderbuffer into the draw framebuffer, within
    /// the scissor box when that test is on, as Apple's is.
    static let resolveMultisampleFramebuffer: Resolve = {
        guard let blit, let getAttachment else { return }
        var type: Int32 = 0, name: Int32 = 0
        getAttachment(0x8CA8, 0x8CE0, 0x8CD0, &type)    // GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0: the object's type
        getAttachment(0x8CA8, 0x8CE0, 0x8CD1, &name)    // and its name
        guard type == 0x8D41, name > 0 else { return }  // GL_RENDERBUFFER
        var bound: Int32 = 0, width: Int32 = 0, height: Int32 = 0
        GLES.getIntegerv(0x8CA7, &bound)                // GL_RENDERBUFFER_BINDING
        GLES.bindRenderbuffer(0x8D41, UInt32(name))
        GLES.getRenderbufferParameteriv(0x8D41, 0x8D42, &width)
        GLES.getRenderbufferParameteriv(0x8D41, 0x8D43, &height)
        GLES.bindRenderbuffer(0x8D41, UInt32(bound))
        blit(0, 0, width, height, 0, 0, width, height, 0x4000, 0x2600)  // GL_COLOR_BUFFER_BIT, GL_NEAREST
    }
}
