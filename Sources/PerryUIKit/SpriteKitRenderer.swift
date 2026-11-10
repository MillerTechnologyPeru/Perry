import CPerryGeometry
import Glibc
import PerryObjCInterop

// SpriteKit's renderer: a view's scene drawn with OpenGL ES 2 into a
// renderbuffer of its own, which is shown in the view's layer as a
// GLKView's frame is. Nodes are not layers: each frame the visible sprites
// and shapes are put back to front (by z position, then in tree order) and
// drawn as triangles, batched while they share a texture. Sprites are
// textured quads, their colour blended in by the colour blend factor; a
// shape's path is filled as triangle fans of its subpaths and stroked as a
// quad a segment, which suits the rectangles and polygons games draw.

private typealias GLuint = UInt32
private typealias GLenum = UInt32

/// The OpenGL ES functions the renderer calls, the host's.
private enum SKGL {
    nonisolated(unsafe) static var loaded = false
    nonisolated(unsafe) static var createShader: (@convention(c) (GLenum) -> GLuint)!
    nonisolated(unsafe) static var shaderSource: (@convention(c) (GLuint, Int32, UnsafePointer<UnsafePointer<CChar>?>?, UnsafePointer<Int32>?) -> Void)!
    nonisolated(unsafe) static var compileShader: (@convention(c) (GLuint) -> Void)!
    nonisolated(unsafe) static var createProgram: (@convention(c) () -> GLuint)!
    nonisolated(unsafe) static var attachShader: (@convention(c) (GLuint, GLuint) -> Void)!
    nonisolated(unsafe) static var bindAttribLocation: (@convention(c) (GLuint, GLuint, UnsafePointer<CChar>) -> Void)!
    nonisolated(unsafe) static var linkProgram: (@convention(c) (GLuint) -> Void)!
    nonisolated(unsafe) static var useProgram: (@convention(c) (GLuint) -> Void)!
    nonisolated(unsafe) static var getAttribLocation: (@convention(c) (GLuint, UnsafePointer<CChar>) -> Int32)!
    nonisolated(unsafe) static var getUniformLocation: (@convention(c) (GLuint, UnsafePointer<CChar>) -> Int32)!
    nonisolated(unsafe) static var uniform1i: (@convention(c) (Int32, Int32) -> Void)!
    nonisolated(unsafe) static var enableVertexAttribArray: (@convention(c) (GLuint) -> Void)!
    nonisolated(unsafe) static var vertexAttribPointer: (@convention(c) (GLuint, Int32, GLenum, UInt8, Int32, UnsafeRawPointer?) -> Void)!
    nonisolated(unsafe) static var drawArrays: (@convention(c) (GLenum, Int32, Int32) -> Void)!
    nonisolated(unsafe) static var enable: (@convention(c) (GLenum) -> Void)!
    nonisolated(unsafe) static var disable: (@convention(c) (GLenum) -> Void)!
    nonisolated(unsafe) static var blendFunc: (@convention(c) (GLenum, GLenum) -> Void)!
    nonisolated(unsafe) static var clearColor: (@convention(c) (Float, Float, Float, Float) -> Void)!
    nonisolated(unsafe) static var clear: (@convention(c) (UInt32) -> Void)!
    nonisolated(unsafe) static var activeTexture: (@convention(c) (GLenum) -> Void)!
    nonisolated(unsafe) static var pixelStorei: (@convention(c) (GLenum, Int32) -> Void)!
    nonisolated(unsafe) static var bindBuffer: (@convention(c) (GLenum, GLuint) -> Void)!
    nonisolated(unsafe) static var genBuffers: (@convention(c) (Int32, UnsafeMutablePointer<GLuint>?) -> Void)!
    nonisolated(unsafe) static var deleteBuffers: (@convention(c) (Int32, UnsafePointer<GLuint>?) -> Void)!
    nonisolated(unsafe) static var bufferData: (@convention(c) (GLenum, Int, UnsafeRawPointer?, GLenum) -> Void)!

    static func load() -> Bool {
        if loaded { return true }
        func bind<T>(_ name: String) -> T? { GLES.symbol("_" + name).map { unsafeBitCast($0, to: T.self) } }
        guard GLES.load(), GLES.genTextures != nil, GLES.bindTexture != nil, GLES.texImage2D != nil, GLES.texParameteri != nil,
              let createShader: @convention(c) (GLenum) -> GLuint = bind("glCreateShader") else { return false }
        self.createShader = createShader
        shaderSource = bind("glShaderSource")
        compileShader = bind("glCompileShader")
        createProgram = bind("glCreateProgram")
        attachShader = bind("glAttachShader")
        bindAttribLocation = bind("glBindAttribLocation")
        linkProgram = bind("glLinkProgram")
        useProgram = bind("glUseProgram")
        getAttribLocation = bind("glGetAttribLocation")
        getUniformLocation = bind("glGetUniformLocation")
        uniform1i = bind("glUniform1i")
        enableVertexAttribArray = bind("glEnableVertexAttribArray")
        vertexAttribPointer = bind("glVertexAttribPointer")
        drawArrays = bind("glDrawArrays")
        enable = bind("glEnable")
        disable = bind("glDisable")
        blendFunc = bind("glBlendFunc")
        clearColor = bind("glClearColor")
        clear = bind("glClear")
        activeTexture = bind("glActiveTexture")
        pixelStorei = bind("glPixelStorei")
        bindBuffer = bind("glBindBuffer")
        genBuffers = bind("glGenBuffers")
        deleteBuffers = bind("glDeleteBuffers")
        bufferData = bind("glBufferData")
        loaded = shaderSource != nil && compileShader != nil && createProgram != nil && attachShader != nil && bindAttribLocation != nil
            && linkProgram != nil && useProgram != nil && getAttribLocation != nil && getUniformLocation != nil && uniform1i != nil && enableVertexAttribArray != nil
            && vertexAttribPointer != nil && drawArrays != nil && enable != nil && disable != nil && blendFunc != nil && clearColor != nil
            && clear != nil && activeTexture != nil && pixelStorei != nil && bindBuffer != nil && genBuffers != nil
            && deleteBuffers != nil && bufferData != nil
        return loaded
    }

    static let triangles: GLenum = 4, texture2D: GLenum = 0x0DE1, rgba: GLenum = 0x1908, unsignedByte: GLenum = 0x1401
    static let float: GLenum = 0x1406, blend: GLenum = 0x0BE2, one: GLenum = 1, oneMinusSourceAlpha: GLenum = 0x0303
    static let colorBufferBit: UInt32 = 0x4000, minFilter: GLenum = 0x2801, magFilter: GLenum = 0x2800
    static let nearest: Int32 = 0x2600, linear: Int32 = 0x2601, wrapS: GLenum = 0x2802, wrapT: GLenum = 0x2803, clampToEdge: Int32 = 0x812F
    static let vertexShader: GLenum = 0x8B31, fragmentShader: GLenum = 0x8B30, arrayBuffer: GLenum = 0x8892, texture0: GLenum = 0x84C0
    static let unpackAlignment: GLenum = 0x0CF5, streamDraw: GLenum = 0x88E0, scissorTest: GLenum = 0x0C11, depthTest: GLenum = 0x0B71, cullFace: GLenum = 0x0B44
}

/// One view's drawing: its context, renderbuffer, program and textures.
final class SKRenderer {
    private let context: EAGLContext
    private var framebuffer: GLuint = 0, color: GLuint = 0
    private var size = (width: 0, height: 0)
    private var program: GLuint = 0
    /// The position, coordinate and color attributes' locations, as linked.
    private var attributes: (GLuint, GLuint, GLuint) = (0, 1, 2)
    /// Textures by picture, with the frame each was last drawn in; the
    /// picture is retained while its texture is kept.
    private var textures: [UnsafeMutableRawPointer: (texture: GLuint, used: Int)] = [:]
    private var white: GLuint = 0
    /// The vertices' buffer, filled again for each batch.
    private var buffer: GLuint = 0
    private var frame = 0
    /// x, y in clip space, u, v, then premultiplied red, green, blue, alpha.
    private var vertices: [Float] = []
    private var batch: (texture: GLuint, nearest: Bool)?

    init?() {
        guard SKGL.load(), let made = EAGLContext.objCClass.object.allocated().unsafeCast(to: EAGLContext.self).initialize(api: 2)
        else { return nil }
        context = made
    }

    deinit {
        guard EAGLContexts.setCurrent(context) else { return }
        for (image, entry) in textures {
            var name = entry.texture
            GLES.deleteTextures?(1, &name)
            ObjCRuntime.release(image)
        }
        if white != 0 { GLES.deleteTextures?(1, &white) }
        if buffer != 0 { SKGL.deleteBuffers(1, &buffer) }
        if color != 0 { GLES.deleteRenderbuffers(1, &color) }
        if framebuffer != 0 { GLES.deleteFramebuffers(1, &framebuffer) }
        _ = EAGLContexts.setCurrent(nil)
    }

    // MARK: Setting up

    private func prepare(width: Int, height: Int) -> Bool {
        if program == 0 {
            guard let made = makeProgram() else { return false }
            program = made
            // The host's linker may place them elsewhere than asked.
            func location(_ name: String, _ asked: GLuint) -> GLuint {
                let found = SKGL.getAttribLocation(made, name)
                return found >= 0 ? GLuint(found) : asked
            }
            attributes = (location("position", 0), location("coordinate", 1), location("color", 2))
            white = makeTexture(pixels: [255, 255, 255, 255], width: 1, height: 1)
            SKGL.genBuffers(1, &buffer)
        }
        guard framebuffer == 0 || size != (width, height) else { return true }
        if color != 0 { GLES.deleteRenderbuffers(1, &color) }
        if framebuffer != 0 { GLES.deleteFramebuffers(1, &framebuffer) }
        GLES.genFramebuffers(1, &framebuffer)
        GLES.bindFramebuffer(GLES.framebuffer, framebuffer)
        GLES.genRenderbuffers(1, &color)
        GLES.bindRenderbuffer(GLES.renderbuffer, color)
        GLES.renderbufferStorage(GLES.renderbuffer, GLES.rgba8, Int32(width), Int32(height))
        GLES.framebufferRenderbuffer(GLES.framebuffer, GLES.colorAttachment0, GLES.renderbuffer, color)
        size = (width, height)
        return true
    }

    private func makeProgram() -> GLuint? {
        let vertex = """
            attribute vec2 position;
            attribute vec2 coordinate;
            attribute vec4 color;
            varying vec2 v_coordinate;
            varying vec4 v_color;
            void main() {
                v_coordinate = coordinate;
                v_color = color;
                gl_Position = vec4(position, 0.0, 1.0);
            }
            """
        let fragment = """
            precision mediump float;
            uniform sampler2D picture;
            varying vec2 v_coordinate;
            varying vec4 v_color;
            void main() {
                gl_FragColor = texture2D(picture, v_coordinate) * v_color;
            }
            """
        func compile(_ type: GLenum, _ source: String) -> GLuint {
            let shader = SKGL.createShader(type)
            source.withCString { text in
                var pointer: UnsafePointer<CChar>? = text
                SKGL.shaderSource(shader, 1, &pointer, nil)
            }
            SKGL.compileShader(shader)
            return shader
        }
        let program = SKGL.createProgram()
        guard program != 0 else { return nil }
        SKGL.attachShader(program, compile(SKGL.vertexShader, vertex))
        SKGL.attachShader(program, compile(SKGL.fragmentShader, fragment))
        SKGL.bindAttribLocation(program, 0, "position")
        SKGL.bindAttribLocation(program, 1, "coordinate")
        SKGL.bindAttribLocation(program, 2, "color")
        SKGL.linkProgram(program)
        return program
    }

    private func makeTexture(pixels: UnsafeRawPointer?, width: Int, height: Int) -> GLuint {
        var name: GLuint = 0
        GLES.genTextures?(1, &name)
        GLES.bindTexture?(SKGL.texture2D, name)
        SKGL.pixelStorei(SKGL.unpackAlignment, 1)
        GLES.texParameteri?(SKGL.texture2D, SKGL.wrapS, SKGL.clampToEdge)
        GLES.texParameteri?(SKGL.texture2D, SKGL.wrapT, SKGL.clampToEdge)
        GLES.texParameteri?(SKGL.texture2D, SKGL.minFilter, SKGL.linear)
        GLES.texParameteri?(SKGL.texture2D, SKGL.magFilter, SKGL.linear)
        GLES.texImage2D?(SKGL.texture2D, 0, Int32(SKGL.rgba), Int32(width), Int32(height), 0, SKGL.rgba, SKGL.unsignedByte, pixels)
        return name
    }

    private func makeTexture(pixels: [UInt8], width: Int, height: Int) -> GLuint {
        pixels.withUnsafeBytes { makeTexture(pixels: $0.baseAddress, width: width, height: height) }
    }

    /// The picture's texture: its pixels drawn once into premultiplied RGBA,
    /// top row first.
    private func texture(for image: UnsafeMutableRawPointer) -> GLuint? {
        if let entry = textures[image] {
            textures[image]?.used = frame
            return entry.texture
        }
        let width = CG.imageGetWidth(image), height = CG.imageGetHeight(image)
        guard width > 0, height > 0, let space = CG.colorSpaceCreateDeviceRGB(),
              // Premultiplied last, bytes in order: R, G, B, A.
              let bitmap = CG.bitmapContextCreate(nil, width, height, 8, width * 4, space, 1 | 0x4000) else { return nil }
        defer { CG.release(bitmap); CG.release(space) }
        CG.drawImage(bitmap, CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)), image)
        guard let pixels = CG.bitmapContextGetData(bitmap) else { return nil }
        let name = makeTexture(pixels: pixels, width: width, height: height)
        _ = ObjCRuntime.retain(image)
        textures[image] = (name, frame)
        return name
    }

    // MARK: Drawing

    /// Draws the scene's frame at `width` by `height` pixels, the view's
    /// points times `scale`, and shows it in `layer`.
    func draw(_ scene: SKScene, in view: SKView, scale: CGFloat, layer: CALayer, opaque: Bool) {
        let bounds = view.state.bounds.size
        let width = Int((bounds.width * scale).rounded()), height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0 else { return }
        let previous = EAGLContexts.current?.object
        guard EAGLContexts.setCurrent(context) else { return }
        defer { _ = EAGLContexts.setCurrent(previous) }
        guard prepare(width: width, height: height) else { return }
        frame += 1

        GLES.bindFramebuffer(GLES.framebuffer, framebuffer)
        GLES.viewport(0, 0, Int32(width), Int32(height))
        SKGL.disable(SKGL.scissorTest)
        SKGL.disable(SKGL.depthTest)
        SKGL.disable(SKGL.cullFace)
        SKGL.clearColor(0, 0, 0, opaque ? 1 : 0)
        SKGL.clear(SKGL.colorBufferBit)
        SKGL.useProgram(program)
        SKGL.uniform1i(SKGL.getUniformLocation(program, "picture"), 0)
        SKGL.activeTexture(SKGL.texture0)
        SKGL.enable(SKGL.blend)
        SKGL.blendFunc(SKGL.one, SKGL.oneMinusSourceAlpha)
        SKGL.bindBuffer(SKGL.arrayBuffer, buffer)

        // From the scene's points to clip space: the view's points, then
        // pixels, then -1...1 with up up.
        let toView = scene.sceneToView(bounds: bounds)
        let toClip = CGAffineTransform(a: 2 / bounds.width, b: 0, c: 0, d: -2 / bounds.height, tx: -1, ty: 1)
        let sceneToClip = toView.concatenating(toClip)

        // The scene's background over its own rectangle.
        let sceneSize = scene.node.sceneSize, anchor = scene.node.sceneAnchor
        let background = SKRenderer.components(scene.node.backgroundColor) ?? (0.15, 0.15, 0.15, 1)
        quad(CGRect(x: -anchor.x * sceneSize.width, y: -anchor.y * sceneSize.height, width: sceneSize.width, height: sceneSize.height),
             matrix: sceneToClip, texture: white, nearest: false, coordinates: CGRect(x: 0, y: 0, width: 1, height: 1),
             color: SKRenderer.premultiplied(background, alpha: 1))

        var visible: [(node: SKNode, matrix: CGAffineTransform, alpha: CGFloat, z: CGFloat)] = []
        collect(scene, parent: sceneToClip, alpha: 1, z: 0, isScene: true, into: &visible)
        let ordered = visible.enumerated().sorted { ($0.element.z, $0.offset) < ($1.element.z, $1.offset) }.map(\.element)
        for item in ordered {
            let state = item.node.node
            if item.node.is(SKShapeNode.self) {
                drawShape(state, matrix: item.matrix, alpha: item.alpha, pixelsPerPoint: scale)
            } else {
                drawSprite(state, matrix: item.matrix, alpha: item.alpha)
            }
        }
        flush()
        evictTextures()

        if Renderbuffers.show(color, context: context.state.context, layer: layer, opaque: opaque) { Display.markDirty() }
    }

    private func collect(_ node: SKNode, parent: CGAffineTransform, alpha: CGFloat, z: CGFloat, isScene: Bool,
                         into list: inout [(node: SKNode, matrix: CGAffineTransform, alpha: CGFloat, z: CGFloat)]) {
        let state = node.node
        guard !state.hidden, state.alpha > 0 else { return }
        let matrix = isScene ? parent : SKSupport.rotationScale(state).concatenating(parent)
        let alpha = alpha * (isScene ? 1 : state.alpha)
        let z = z + (isScene ? 0 : state.zPosition)
        if node.is(SKSpriteNode.self) || node.is(SKShapeNode.self) { list.append((node, matrix, alpha, z)) }
        for child in state.children {
            collect(child.unsafeCast(to: SKNode.self), parent: matrix, alpha: alpha, z: z, isScene: false, into: &list)
        }
    }

    private func drawSprite(_ node: SKNodeState, matrix: CGAffineTransform, alpha: CGFloat) {
        let size = node.size
        let rect = CGRect(x: -node.anchor.x * size.width, y: -node.anchor.y * size.height, width: size.width, height: size.height)
        let tint = SKRenderer.components(node.color) ?? (1, 1, 1, 1)
        if let texture = node.texture, let image = texture.state.image, let name = self.texture(for: image) {
            // Texture rectangles start at the bottom left; the picture's rows at the top.
            let part = texture.state.rect
            let coordinates = CGRect(x: part.minX, y: 1 - part.maxY, width: part.width, height: part.height)
            // The colour blend factor moves the picture's colour toward its
            // product with the sprite's colour.
            let factor = Double(min(max(node.colorBlendFactor, 0), 1))
            let mix = (1 + (tint.0 - 1) * factor, 1 + (tint.1 - 1) * factor, 1 + (tint.2 - 1) * factor)
            let a = Double(alpha)
            quad(rect, matrix: matrix, texture: name, nearest: texture.state.filtering == 0, coordinates: coordinates,
                 color: (Float(mix.0 * a), Float(mix.1 * a), Float(mix.2 * a), Float(a)), flipped: true)
        } else {
            quad(rect, matrix: matrix, texture: white, nearest: false, coordinates: CGRect(x: 0, y: 0, width: 1, height: 1),
                 color: SKRenderer.premultiplied(tint, alpha: Double(alpha)))
        }
    }

    private func drawShape(_ node: SKNodeState, matrix: CGAffineTransform, alpha: CGFloat, pixelsPerPoint: CGFloat) {
        guard let path = node.path else { return }
        let subpaths = SKRenderer.polygons(of: path)
        if let fill = node.fillColor.flatMap({ SKRenderer.components($0) }), fill.3 > 0 {
            let color = SKRenderer.premultiplied(fill, alpha: Double(alpha))
            for polygon in subpaths where polygon.points.count >= 3 {
                let points = polygon.points.map { matrix.apply($0) }
                for index in 1..<(points.count - 1) { triangle(points[0], points[index], points[index + 1], color: color) }
            }
        }
        // A stroke is white unless set, as SpriteKit's is.
        let stroke = node.strokeColor.map { SKRenderer.components($0) } ?? (1, 1, 1, 1)
        if let stroke, stroke.3 > 0, node.lineWidth > 0 {
            let color = SKRenderer.premultiplied(stroke, alpha: Double(alpha))
            let half = node.lineWidth / 2
            for polygon in subpaths where polygon.points.count >= 2 {
                var points = polygon.points
                if polygon.closed, let first = points.first { points.append(first) }
                for index in 0..<(points.count - 1) {
                    let a = points[index], b = points[index + 1]
                    let dx = b.x - a.x, dy = b.y - a.y
                    let length = (dx * dx + dy * dy).squareRoot()
                    guard length > 0 else { continue }
                    // Out from the segment, by half the width, and past its ends to close the corners.
                    let nx = -dy / length * half, ny = dx / length * half
                    let ex = dx / length * half, ey = dy / length * half
                    let corners = [CGPoint(x: a.x - ex + nx, y: a.y - ey + ny), CGPoint(x: b.x + ex + nx, y: b.y + ey + ny),
                                   CGPoint(x: b.x + ex - nx, y: b.y + ey - ny), CGPoint(x: a.x - ex - nx, y: a.y - ey - ny)].map { matrix.apply($0) }
                    triangle(corners[0], corners[1], corners[2], color: color)
                    triangle(corners[0], corners[2], corners[3], color: color)
                }
            }
        }
    }

    /// A rectangle in a node's points, through `matrix` to clip space.
    private func quad(_ rect: CGRect, matrix: CGAffineTransform, texture: GLuint, nearest: Bool, coordinates: CGRect,
                      color: (Float, Float, Float, Float), flipped: Bool = false) {
        use(texture: texture, nearest: nearest)
        // Bottom left, bottom right, top right, top left; the picture's top
        // row is at the rectangle's top.
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)].map { matrix.apply($0) }
        let u0 = Float(coordinates.minX), u1 = Float(coordinates.maxX)
        let top = Float(coordinates.minY), bottom = Float(coordinates.maxY)
        let uv: [(Float, Float)] = flipped ? [(u0, bottom), (u1, bottom), (u1, top), (u0, top)] : [(u0, top), (u1, top), (u1, bottom), (u0, bottom)]
        for index in [0, 1, 2, 0, 2, 3] {
            vertices += [Float(corners[index].x), Float(corners[index].y), uv[index].0, uv[index].1, color.0, color.1, color.2, color.3]
        }
    }

    private func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, color: (Float, Float, Float, Float)) {
        use(texture: white, nearest: false)
        for point in [a, b, c] { vertices += [Float(point.x), Float(point.y), 0.5, 0.5, color.0, color.1, color.2, color.3] }
    }

    /// Starts a new batch when the texture or its filtering changes.
    private func use(texture: GLuint, nearest: Bool) {
        if let batch, batch.texture == texture, batch.nearest == nearest { return }
        flush()
        batch = (texture, nearest)
    }

    private func flush() {
        guard let batch, !vertices.isEmpty else {
            vertices.removeAll(keepingCapacity: true)
            return
        }
        GLES.bindTexture?(SKGL.texture2D, batch.texture)
        let filter = batch.nearest ? SKGL.nearest : SKGL.linear
        GLES.texParameteri?(SKGL.texture2D, SKGL.minFilter, filter)
        GLES.texParameteri?(SKGL.texture2D, SKGL.magFilter, filter)
        // Copied into the buffer: the draw may run after this returns.
        vertices.withUnsafeBytes { raw in
            SKGL.bufferData(SKGL.arrayBuffer, raw.count, raw.baseAddress, SKGL.streamDraw)
        }
        let stride = Int32(8 * MemoryLayout<Float>.size)
        let (position, coordinate, color) = attributes
        SKGL.enableVertexAttribArray(position)
        SKGL.enableVertexAttribArray(coordinate)
        SKGL.enableVertexAttribArray(color)
        SKGL.vertexAttribPointer(position, 2, SKGL.float, 0, stride, nil)
        SKGL.vertexAttribPointer(coordinate, 2, SKGL.float, 0, stride, UnsafeRawPointer(bitPattern: 2 * MemoryLayout<Float>.size))
        SKGL.vertexAttribPointer(color, 4, SKGL.float, 0, stride, UnsafeRawPointer(bitPattern: 4 * MemoryLayout<Float>.size))
        SKGL.drawArrays(SKGL.triangles, 0, Int32(vertices.count / 8))
        vertices.removeAll(keepingCapacity: true)
    }

    /// Lets go of textures not drawn for ten seconds.
    private func evictTextures() {
        batch = nil
        for (image, entry) in textures where frame - entry.used > 600 {
            var name = entry.texture
            GLES.deleteTextures?(1, &name)
            ObjCRuntime.release(image)
            textures[image] = nil
        }
    }

    // MARK: Colours and paths

    /// A UIColor-like object's red, green, blue and alpha; nil without one.
    static func components(_ color: UnsafeMutableRawPointer?) -> (Double, Double, Double, Double)? {
        guard let color, let cgColor = SKSupport.cgColor(color), let values = CG.colorGetComponents(cgColor) else { return nil }
        switch CG.colorGetNumberOfComponents(cgColor) {
        case 2: return (Double(values[0]), Double(values[0]), Double(values[0]), Double(values[1]))
        case 4...: return (Double(values[0]), Double(values[1]), Double(values[2]), Double(values[3]))
        default: return nil
        }
    }

    static func premultiplied(_ color: (Double, Double, Double, Double), alpha: Double) -> (Float, Float, Float, Float) {
        let a = color.3 * alpha
        return (Float(color.0 * a), Float(color.1 * a), Float(color.2 * a), Float(a))
    }

    struct Polygon {
        var points: [CGPoint] = []
        var closed = false
    }

    nonisolated(unsafe) private static var collecting: [Polygon] = []

    /// The path's subpaths as points, curves followed in eight steps.
    static func polygons(of path: CGRef) -> [Polygon] {
        collecting = []
        CG.pathApply(path, nil) { _, element in
            guard let element else { return }
            let type = element.load(as: Int32.self)
            let points = element.load(fromByteOffset: 8, as: UnsafePointer<CGPoint>.self)
            switch type {
            case 0: SKRenderer.collecting.append(Polygon(points: [points[0]]))
            case 1: SKRenderer.add([points[0]])
            case 2:
                guard let start = SKRenderer.collecting.last?.points.last else { return }
                SKRenderer.add((1...8).map { step in
                    let t = CGFloat(step) / 8, s = 1 - t
                    return CGPoint(x: s * s * start.x + 2 * s * t * points[0].x + t * t * points[1].x,
                                   y: s * s * start.y + 2 * s * t * points[0].y + t * t * points[1].y)
                })
            case 3:
                guard let start = SKRenderer.collecting.last?.points.last else { return }
                SKRenderer.add((1...8).map { step in
                    let t = CGFloat(step) / 8, s = 1 - t
                    let a = s * s * s, b = 3 * s * s * t, c = 3 * s * t * t, d = t * t * t
                    return CGPoint(x: a * start.x + b * points[0].x + c * points[1].x + d * points[2].x,
                                   y: a * start.y + b * points[0].y + c * points[1].y + d * points[2].y)
                })
            case 4: if !SKRenderer.collecting.isEmpty { SKRenderer.collecting[SKRenderer.collecting.count - 1].closed = true }
            default: break
            }
        }
        let result = collecting
        collecting = []
        return result
    }

    private static func add(_ points: [CGPoint]) {
        if collecting.isEmpty { collecting.append(Polygon()) }
        collecting[collecting.count - 1].points += points
    }
}
