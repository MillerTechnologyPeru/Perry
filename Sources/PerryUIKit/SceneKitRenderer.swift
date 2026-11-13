import CPerryGeometry
import Glibc
import PerryObjCInterop

// SceneKit's renderer: a view's scene drawn with OpenGL ES 2 into a
// renderbuffer of its own (with a depth buffer), which is shown in the
// view's layer as a GLKView's frame is. Each frame walks the scene's nodes,
// then draws the opaque geometry, and after it what is translucent back to
// front, a draw an element: one program lights each vertex's surface by a
// light at the camera when the view enables default lighting, by nothing
// otherwise, and not at all for a constant lighting model.

/// The OpenGL ES functions of SceneKit's drawing that SpriteKit's don't use.
enum SCNGL {
    nonisolated(unsafe) static var loaded = false
    nonisolated(unsafe) static var uniform1f: (@convention(c) (Int32, Float) -> Void)!
    nonisolated(unsafe) static var uniform3f: (@convention(c) (Int32, Float, Float, Float) -> Void)!
    nonisolated(unsafe) static var uniform4f: (@convention(c) (Int32, Float, Float, Float, Float) -> Void)!
    nonisolated(unsafe) static var uniformMatrix3fv: (@convention(c) (Int32, Int32, UInt8, UnsafePointer<Float>?) -> Void)!
    nonisolated(unsafe) static var uniformMatrix4fv: (@convention(c) (Int32, Int32, UInt8, UnsafePointer<Float>?) -> Void)!
    nonisolated(unsafe) static var depthMask: (@convention(c) (UInt8) -> Void)!
    nonisolated(unsafe) static var cullFace: (@convention(c) (GLenum) -> Void)!
    nonisolated(unsafe) static var uniform3fv: (@convention(c) (Int32, Int32, UnsafePointer<Float>?) -> Void)!
    nonisolated(unsafe) static var uniform4fv: (@convention(c) (Int32, Int32, UnsafePointer<Float>?) -> Void)!
    nonisolated(unsafe) static var generateMipmap: (@convention(c) (GLenum) -> Void)!
    nonisolated(unsafe) static var disableVertexAttribArray: (@convention(c) (GLuint) -> Void)!

    static func load() -> Bool {
        if loaded { return true }
        guard SKGL.load() else { return false }
        func bind<T>(_ name: String) -> T? { GLES.symbol("_" + name).map { unsafeBitCast($0, to: T.self) } }
        uniform1f = bind("glUniform1f")
        uniform3f = bind("glUniform3f")
        uniform4f = bind("glUniform4f")
        uniformMatrix3fv = bind("glUniformMatrix3fv")
        uniformMatrix4fv = bind("glUniformMatrix4fv")
        depthMask = bind("glDepthMask")
        cullFace = bind("glCullFace")
        uniform3fv = bind("glUniform3fv")
        uniform4fv = bind("glUniform4fv")
        generateMipmap = bind("glGenerateMipmap")
        disableVertexAttribArray = bind("glDisableVertexAttribArray")
        loaded = uniform1f != nil && uniform3f != nil && uniform4f != nil && uniformMatrix3fv != nil && uniformMatrix4fv != nil
            && depthMask != nil && cullFace != nil && uniform3fv != nil && uniform4fv != nil && generateMipmap != nil && disableVertexAttribArray != nil
        return loaded
    }

    static let depthBufferBit: UInt32 = 0x100, back: GLenum = 0x0405, front: GLenum = 0x0404
    static let repeatWrap: Int32 = 0x2901, mirroredRepeat: Int32 = 0x8370, linearMipmapLinear: Int32 = 0x2703
    static let texture1: GLenum = 0x84C1, texture2: GLenum = 0x84C2, texture3: GLenum = 0x84C3
    static let maxLights = 4
}

/// One view's drawing: its context, renderbuffers, program and meshes.
final class SCNRenderer {
    private let context: EAGLContext
    private var framebuffer: GLuint = 0, color: GLuint = 0, depth: GLuint = 0
    private var size = (width: 0, height: 0)
    private var program: GLuint = 0
    private var attributes: (GLuint, GLuint, GLuint, GLuint) = (0, 1, 2, 3)
    private struct Uniforms {
        var mvp: Int32 = -1, model: Int32 = -1, normalMatrix: Int32 = -1
        var diffuse: Int32 = -1, emission: Int32 = -1, lightPosition: Int32 = -1, lightColor: Int32 = -1, ambient: Int32 = -1
        var diffuseMap: Int32 = -1, emissionMap: Int32 = -1
        var skyColor: Int32 = -1, groundColor: Int32 = -1, environment: Int32 = -1
        var lightMap: Int32 = -1, occlusionMap: Int32 = -1, maps: Int32 = -1
    }
    private var uniforms = Uniforms()
    /// Each geometry's vertices' buffer, by its identifier.
    private var buffers: [Int: (revision: Int, buffer: GLuint, used: Int)] = [:]
    private var frame = 0
    /// Textures by picture, with the frame each was last drawn in; the
    /// picture is retained while its texture is kept.
    private var textures: [UnsafeMutableRawPointer: (texture: GLuint, used: Int)] = [:]
    private var white: GLuint = 0
    /// The vertices of skinned geometry, made again for each draw.
    private var skinBuffer: GLuint = 0
    private var quadBuffer: GLuint = 0
    private var lavaProgram: GLuint = 0
    /// Seconds since the view began, which shaders that animate read.
    var time: Float = 0
    private var skyProgram: GLuint = 0

    init?() {
        guard SCNGL.load(), let made = EAGLContext.objCClass.object.allocated().unsafeCast(to: EAGLContext.self).initialize(api: 2)
        else { return nil }
        context = made
    }

    deinit {
        guard EAGLContexts.setCurrent(context) else { return }
        for entry in buffers.values {
            var name = entry.buffer
            SKGL.deleteBuffers(1, &name)
        }
        for (image, entry) in textures {
            var name = entry.texture
            GLES.deleteTextures?(1, &name)
            ObjCRuntime.release(image)
        }
        if white != 0 { GLES.deleteTextures?(1, &white) }
        if skinBuffer != 0 { SKGL.deleteBuffers(1, &skinBuffer) }
        if quadBuffer != 0 { SKGL.deleteBuffers(1, &quadBuffer) }
        if depth != 0 { GLES.deleteRenderbuffers(1, &depth) }
        if color != 0 { GLES.deleteRenderbuffers(1, &color) }
        if framebuffer != 0 { GLES.deleteFramebuffers(1, &framebuffer) }
        _ = EAGLContexts.setCurrent(nil)
    }

    // MARK: Setting up

    private func prepare(width: Int, height: Int) -> Bool {
        if program == 0 {
            guard let made = makeProgram() else { return false }
            program = made
            func attribute(_ name: String, _ asked: GLuint) -> GLuint {
                let found = SKGL.getAttribLocation(made, name)
                return found >= 0 ? GLuint(found) : asked
            }
            func uniform(_ name: String) -> Int32 { SKGL.getUniformLocation(made, name) }
            attributes = (attribute("position", 0), attribute("normal", 1), attribute("coordinate", 2), attribute("coordinate2", 3))
            uniforms = Uniforms(mvp: uniform("mvp"), model: uniform("model"), normalMatrix: uniform("normalMatrix"),
                                diffuse: uniform("diffuse"), emission: uniform("emission"),
                                lightPosition: max(uniform("lightPosition"), uniform("lightPosition[0]")),
                                lightColor: max(uniform("lightColor"), uniform("lightColor[0]")), ambient: uniform("ambient"),
                                diffuseMap: uniform("diffuseMap"), emissionMap: uniform("emissionMap"),
                                skyColor: uniform("skyColor"), groundColor: uniform("groundColor"), environment: uniform("environment"),
                                lightMap: uniform("lightMap"), occlusionMap: uniform("occlusionMap"), maps: uniform("maps"))
            white = makeTexture(pixels: [255, 255, 255, 255], width: 1, height: 1, mipmaps: false)
        }
        guard framebuffer == 0 || size != (width, height) else { return true }
        if depth != 0 { GLES.deleteRenderbuffers(1, &depth) }
        if color != 0 { GLES.deleteRenderbuffers(1, &color) }
        if framebuffer != 0 { GLES.deleteFramebuffers(1, &framebuffer) }
        GLES.genFramebuffers(1, &framebuffer)
        GLES.bindFramebuffer(GLES.framebuffer, framebuffer)
        GLES.genRenderbuffers(1, &color)
        GLES.bindRenderbuffer(GLES.renderbuffer, color)
        GLES.renderbufferStorage(GLES.renderbuffer, GLES.rgba8, Int32(width), Int32(height))
        GLES.framebufferRenderbuffer(GLES.framebuffer, GLES.colorAttachment0, GLES.renderbuffer, color)
        GLES.genRenderbuffers(1, &depth)
        GLES.bindRenderbuffer(GLES.renderbuffer, depth)
        GLES.renderbufferStorage(GLES.renderbuffer, GLES.depth16, Int32(width), Int32(height))
        GLES.framebufferRenderbuffer(GLES.framebuffer, GLES.depthAttachment, GLES.renderbuffer, depth)
        size = (width, height)
        return true
    }

    private func makeProgram() -> GLuint? {
        let vertex = """
            attribute vec3 position;
            attribute vec3 normal;
            attribute vec2 coordinate;
            attribute vec2 coordinate2;
            uniform mat4 mvp;
            uniform mat4 model;
            uniform mat3 normalMatrix;
            varying vec3 v_normal;
            varying vec3 v_position;
            varying vec2 v_coordinate;
            varying vec2 v_coordinate2;
            void main() {
                v_normal = normalMatrix * normal;
                v_position = (model * vec4(position, 1.0)).xyz;
                v_coordinate = vec2(coordinate.x, 1.0 - coordinate.y);
                v_coordinate2 = vec2(coordinate2.x, coordinate2.y);
                gl_Position = mvp * vec4(position, 1.0);
            }
            """
        let fragment = """
            precision mediump float;
            uniform vec4 diffuse;
            uniform vec3 emission;
            uniform vec4 lightPosition[4];
            uniform vec3 lightColor[4];
            uniform vec3 ambient;
            uniform vec3 skyColor;
            uniform vec3 groundColor;
            uniform float environment;
            uniform sampler2D diffuseMap;
            uniform sampler2D emissionMap;
            uniform sampler2D lightMap;
            uniform sampler2D occlusionMap;
            uniform vec4 maps;
            varying vec3 v_normal;
            varying vec3 v_position;
            varying vec2 v_coordinate;
            varying vec2 v_coordinate2;
            void main() {
                vec3 n = normalize(v_normal);
                if (!gl_FrontFacing) { n = -n; }
                vec4 base = diffuse * texture2D(diffuseMap, v_coordinate);
                // The environment lights a surface by where it faces: the sky from above, the ground's glow from below.
                // maps: x is 1 with a light map, y is 1 with an occlusion map, and z and w are 1 where either is laid out by the second coordinates.
                vec3 indirect = ambient + mix(groundColor, skyColor, n.y * 0.5 + 0.5) * environment;
                vec3 occlusion = maps.y > 0.5 ? texture2D(occlusionMap, maps.w > 0.5 ? v_coordinate2 : v_coordinate).rgb : vec3(1.0);
                vec3 light = indirect * occlusion;
                for (int i = 0; i < 4; i++) {
                    // w is 0 for a direction toward the light, 1 for a position.
                    vec3 toLight = lightPosition[i].w > 0.5 ? normalize(lightPosition[i].xyz - v_position) : lightPosition[i].xyz;
                    light += lightColor[i] * max(dot(n, toLight), 0.0);
                }
                vec3 rgb = base.rgb * light + emission * texture2D(emissionMap, v_coordinate).rgb;
                // A baked light map: the light that fell on the surface, as it was when it was made.
                if (maps.x > 0.5) { rgb += base.rgb * texture2D(lightMap, maps.z > 0.5 ? v_coordinate2 : v_coordinate).rgb; }
                gl_FragColor = vec4(rgb * base.a, base.a);
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
        SKGL.bindAttribLocation(program, 1, "normal")
        SKGL.bindAttribLocation(program, 2, "coordinate")
        SKGL.bindAttribLocation(program, 3, "coordinate2")
        SKGL.linkProgram(program)
        return program
    }

    private func makeTexture(pixels: UnsafeRawPointer?, width: Int, height: Int, mipmaps: Bool) -> GLuint {
        var name: GLuint = 0
        GLES.genTextures?(1, &name)
        GLES.bindTexture?(SKGL.texture2D, name)
        SKGL.pixelStorei(SKGL.unpackAlignment, 1)
        GLES.texParameteri?(SKGL.texture2D, SKGL.wrapS, SKGL.clampToEdge)
        GLES.texParameteri?(SKGL.texture2D, SKGL.wrapT, SKGL.clampToEdge)
        GLES.texParameteri?(SKGL.texture2D, SKGL.magFilter, SKGL.linear)
        GLES.texImage2D?(SKGL.texture2D, 0, Int32(SKGL.rgba), Int32(width), Int32(height), 0, SKGL.rgba, SKGL.unsignedByte, pixels)
        // Mipmaps, where the picture's sides are powers of two as OpenGL ES 2 asks.
        if mipmaps, width & (width - 1) == 0, height & (height - 1) == 0 {
            SCNGL.generateMipmap(SKGL.texture2D)
            GLES.texParameteri?(SKGL.texture2D, SKGL.minFilter, SCNGL.linearMipmapLinear)
        } else {
            GLES.texParameteri?(SKGL.texture2D, SKGL.minFilter, SKGL.linear)
        }
        return name
    }

    private func makeTexture(pixels: [UInt8], width: Int, height: Int, mipmaps: Bool) -> GLuint {
        pixels.withUnsafeBytes { makeTexture(pixels: $0.baseAddress, width: width, height: height, mipmaps: mipmaps) }
    }

    /// The texture of a material property's picture: its pixels drawn once
    /// into premultiplied RGBA, top row first; white when it has none.
    private func texture(of contents: UnsafeMutableRawPointer?) -> GLuint {
        guard let contents, NSObject(contents).responds(to: "CGImage"), let image = NSObject(contents).skCGImage() else { return white }
        if let entry = textures[image] {
            textures[image]?.used = frame
            return entry.texture
        }
        let width = CG.imageGetWidth(image), height = CG.imageGetHeight(image)
        guard width > 0, height > 0, let space = CG.colorSpaceCreateDeviceRGB(),
              let bitmap = CG.bitmapContextCreate(nil, width, height, 8, width * 4, space, 1 | 0x4000) else { return white }
        defer { CG.release(bitmap); CG.release(space) }
        CG.drawImage(bitmap, CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)), image)
        guard let pixels = CG.bitmapContextGetData(bitmap) else { return white }
        let name = makeTexture(pixels: pixels, width: width, height: height, mipmaps: true)
        _ = ObjCRuntime.retain(image)
        textures[image] = (name, frame)
        return name
    }

    private func evictTextures() {
        for (image, entry) in textures where frame - entry.used > 600 {
            var name = entry.texture
            GLES.deleteTextures?(1, &name)
            ObjCRuntime.release(image)
            textures[image] = nil
        }
    }

    private static func wrap(_ mode: Int) -> Int32 {
        switch mode {
        case 2: return SCNGL.repeatWrap
        case 4: return SCNGL.mirroredRepeat
        default: return SKGL.clampToEdge
        }
    }

    // MARK: Drawing

    private struct Item {
        var geometry: SCNGeometry
        var model: Matrix
        var opacity: Float
        /// The bones that move the geometry's vertices, if it is skinned.
        var skinner: SCNSkinnerState?
        /// Distance along the view, for the translucent's order.
        var depth: Float = 0
    }

    /// Draws the scene's frame, seen from `pointOfView` or the scene's first
    /// camera, and shows it in `layer`.
    func draw(_ scene: SCNScene, pointOfView: SCNNode?, in view: SCNView, scale: CGFloat, layer: CALayer, defaultLighting: Bool) {
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
        let backgroundImage = scene.scene.background?.property.contents.flatMap { NSObject($0).responds(to: "CGImage") ? $0 : nil }
        let background = backgroundImage == nil ? backgroundColor(of: scene, in: view) : (0, 0, 0)
        SKGL.clearColor(background.0, background.1, background.2, 1)
        SCNGL.depthMask(1)
        SKGL.clear(SKGL.colorBufferBit | SCNGL.depthBufferBit)
        SKGL.useProgram(program)
        SKGL.enable(SKGL.depthTest)
        SKGL.enable(SKGL.cullFace)
        SKGL.disable(SKGL.blend)
        SKGL.bindBuffer(SKGL.arrayBuffer, 0)

        let root = scene.rootNode()
        let camera = pointOfView ?? SCNRenderer.findCamera(in: root)
        let cameraWorld = camera?.world ?? SCNMath.identity
        let viewMatrix = SCNMath.inverse(cameraWorld)
        let projection = SCNRenderer.projection(camera?.node.camera?.camera, aspect: Float(width) / Float(height))
        let viewProjection = SCNMath.multiply(projection, viewMatrix)
        SKGL.uniform1i(uniforms.diffuseMap, 0)
        SKGL.uniform1i(uniforms.lightMap, 2)
        SKGL.uniform1i(uniforms.occlusionMap, 3)
        SCNGL.uniform3f(uniforms.skyColor, 0.38, 0.46, 0.62)
        SCNGL.uniform3f(uniforms.groundColor, 0.30, 0.20, 0.13)
        SKGL.uniform1i(uniforms.emissionMap, 1)

        if let backgroundImage {
            if let image = NSObject(backgroundImage).skCGImage(), CG.imageGetWidth(image) == CG.imageGetHeight(image) * 6 {
                drawSkybox(backgroundImage, projection: projection, cameraWorld: cameraWorld)
            } else {
                drawBackground(backgroundImage, aspect: Float(width) / Float(height))
            }
            SKGL.useProgram(program)
        }

        var items: [Item] = []
        var lights: [(light: SCNLight, world: Matrix)] = []
        collect(root, parent: SCNMath.identity, opacity: 1, into: &items, lights: &lights)
        frameLights = shading(lights, cameraWorld: cameraWorld, defaultLighting: defaultLighting)
        if frame == 5 || frame == 120, getenv("PERRY_SCENEKIT_TRACE") != nil {
            // PERRY_SCENEKIT_TRACE: what the view is drawing, twice.
            let line = "perry: SceneKit: frame \(frame): \(items.count) items, \(lights.count) lights, camera \(camera?.node.name ?? "none") at (\(cameraWorld[12]), \(cameraWorld[13]), \(cameraWorld[14])) front (\(-cameraWorld[8]), \(-cameraWorld[9]), \(-cameraWorld[10])), \(camera?.node.constraints.count ?? -1) constraints, root has \(root.node.children.count) children: \(root.node.children.prefix(12).map { $0.unsafeCast(to: SCNNode.self).node.name ?? "-" })\n"
            line.withCString { _ = write(2, $0, strlen($0)) }
        }
        for index in items.indices {
            let p = SCNMath.multiply(viewMatrix, items[index].model)
            items[index].depth = p[14]
        }
        for item in items { draw(item, viewProjection: viewProjection, translucent: false, defaultLighting: defaultLighting) }
        // Translucent geometry is drawn far to near, and doesn't write depth.
        let translucent = items.sorted { $0.depth < $1.depth }
        SKGL.enable(SKGL.blend)
        SKGL.blendFunc(SKGL.one, SKGL.oneMinusSourceAlpha)
        SCNGL.depthMask(0)
        for item in translucent { draw(item, viewProjection: viewProjection, translucent: true, defaultLighting: defaultLighting) }
        SCNGL.depthMask(1)
        SKGL.disable(SKGL.blend)
        evictBuffers()
        evictTextures()

        if Renderbuffers.show(color, context: context.state.context, layer: layer, opaque: true) { Display.markDirty() }
    }

    /// A cube map's six faces in a row (+x, -x, +y, -y, +z, -z), drawn as the sky: each pixel looks along its ray from the camera.
    private func drawSkybox(_ contents: UnsafeMutableRawPointer, projection: Matrix, cameraWorld: Matrix) {
        if skyProgram == 0 {
            let vertex = """
                attribute vec2 position;
                varying vec2 v_ndc;
                void main() {
                    v_ndc = position;
                    gl_Position = vec4(position, 0.999, 1.0);
                }
                """
            let fragment = """
                precision highp float;
                uniform mat4 inverseProjection;
                uniform mat3 cameraRotation;
                uniform sampler2D strip;
                varying vec2 v_ndc;
                void main() {
                    vec4 p = inverseProjection * vec4(v_ndc, 1.0, 1.0);
                    vec3 d = cameraRotation * normalize(p.xyz / p.w);
                    vec3 a = abs(d);
                    float face; float s; float t; float m;
                    if (a.x >= a.y && a.x >= a.z) {
                        m = a.x;
                        if (d.x > 0.0) { face = 0.0; s = -d.z; } else { face = 1.0; s = d.z; }
                        t = -d.y;
                    } else if (a.y >= a.z) {
                        m = a.y;
                        if (d.y > 0.0) { face = 2.0; t = d.z; } else { face = 3.0; t = -d.z; }
                        s = d.x;
                    } else {
                        m = a.z;
                        if (d.z > 0.0) { face = 4.0; s = d.x; } else { face = 5.0; s = -d.x; }
                        t = -d.y;
                    }
                    vec2 uv = clamp(vec2(s, t) / m * 0.5 + 0.5, 0.002, 0.998);
                    gl_FragColor = vec4(texture2D(strip, vec2((face + uv.x) / 6.0, uv.y)).rgb, 1.0);
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
            let made = SKGL.createProgram()
            SKGL.attachShader(made, compile(SKGL.vertexShader, vertex))
            SKGL.attachShader(made, compile(SKGL.fragmentShader, fragment))
            SKGL.bindAttribLocation(made, 0, "position")
            SKGL.linkProgram(made)
            skyProgram = made
        }
        SKGL.useProgram(skyProgram)
        let positions: [Float] = [-1, -1, 1, -1, 1, 1, -1, -1, 1, 1, -1, 1]
        if quadBuffer == 0 { SKGL.genBuffers(1, &quadBuffer) }
        SKGL.bindBuffer(SKGL.arrayBuffer, quadBuffer)
        positions.withUnsafeBytes { SKGL.bufferData(SKGL.arrayBuffer, $0.count, $0.baseAddress, SKGL.streamDraw) }
        SKGL.enableVertexAttribArray(0)
        SKGL.vertexAttribPointer(0, 2, SKGL.float, 0, 8, UnsafeRawPointer(bitPattern: 0))
        SCNGL.disableVertexAttribArray(1)
        SCNGL.disableVertexAttribArray(2)
        let inverse = SCNMath.inverse(projection)
        inverse.withUnsafeBufferPointer { SCNGL.uniformMatrix4fv(SKGL.getUniformLocation(skyProgram, "inverseProjection"), 1, 0, $0.baseAddress) }
        // The camera's turn, without its place or scale.
        func column(_ i: Int) -> [Float] {
            let v = [cameraWorld[i * 4], cameraWorld[i * 4 + 1], cameraWorld[i * 4 + 2]]
            let length = max((v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).squareRoot(), 1e-9)
            return v.map { $0 / length }
        }
        (column(0) + column(1) + column(2)).withUnsafeBufferPointer { SCNGL.uniformMatrix3fv(SKGL.getUniformLocation(skyProgram, "cameraRotation"), 1, 0, $0.baseAddress) }
        SKGL.uniform1i(SKGL.getUniformLocation(skyProgram, "strip"), 0)
        SKGL.activeTexture(SKGL.texture0)
        GLES.bindTexture?(SKGL.texture2D, texture(of: contents))
        GLES.texParameteri?(SKGL.texture2D, SKGL.wrapS, SKGL.clampToEdge)
        GLES.texParameteri?(SKGL.texture2D, SKGL.wrapT, SKGL.clampToEdge)
        SKGL.disable(SKGL.depthTest)
        SKGL.disable(SKGL.cullFace)
        SKGL.drawArrays(SKGL.triangles, 0, 6)
        SKGL.enable(SKGL.depthTest)
        SKGL.enable(SKGL.cullFace)
        SCNGL.disableVertexAttribArray(0)
    }

    /// A picture over the whole view, behind everything: the scene's background, scaled to fill.
    private func drawBackground(_ contents: UnsafeMutableRawPointer, aspect: Float) {
        guard let image = NSObject(contents).skCGImage() else { return }
        let w = Float(CG.imageGetWidth(image)), h = Float(CG.imageGetHeight(image))
        guard w > 0, h > 0 else { return }
        // The part of the picture that fills the view.
        let pictureAspect = w / h
        let (uSpan, vSpan): (Float, Float) = aspect > pictureAspect ? (1, pictureAspect / aspect) : (aspect / pictureAspect, 1)
        let u0 = (1 - uSpan) / 2, v0 = (1 - vSpan) / 2
        // Clip-space corners with positions, normal, and coordinates (the program flips the second one).
        func corner(_ x: Float, _ y: Float, _ u: Float, _ v: Float) -> [Float] { [x, y, 0.999, 0, 0, 1, u0 + u * uSpan, 1 - (v0 + v * vSpan)] }
        let vertices = corner(-1, -1, 0, 1) + corner(1, -1, 1, 1) + corner(1, 1, 1, 0) + corner(-1, -1, 0, 1) + corner(1, 1, 1, 0) + corner(-1, 1, 0, 0)
        if quadBuffer == 0 { SKGL.genBuffers(1, &quadBuffer) }
        SKGL.bindBuffer(SKGL.arrayBuffer, quadBuffer)
        vertices.withUnsafeBytes { SKGL.bufferData(SKGL.arrayBuffer, $0.count, $0.baseAddress, SKGL.streamDraw) }
        let stride: Int32 = 32
        SKGL.enableVertexAttribArray(attributes.0)
        SKGL.vertexAttribPointer(attributes.0, 3, SKGL.float, 0, stride, UnsafeRawPointer(bitPattern: 0))
        SKGL.enableVertexAttribArray(attributes.1)
        SKGL.vertexAttribPointer(attributes.1, 3, SKGL.float, 0, stride, UnsafeRawPointer(bitPattern: 12))
        SKGL.enableVertexAttribArray(attributes.2)
        SKGL.vertexAttribPointer(attributes.2, 2, SKGL.float, 0, stride, UnsafeRawPointer(bitPattern: 24))
        SCNGL.disableVertexAttribArray(attributes.3)
        SCNMath.identity.withUnsafeBufferPointer {
            SCNGL.uniformMatrix4fv(uniforms.mvp, 1, 0, $0.baseAddress)
            SCNGL.uniformMatrix4fv(uniforms.model, 1, 0, $0.baseAddress)
        }
        [Float(1), 0, 0, 0, 1, 0, 0, 0, 1].withUnsafeBufferPointer { SCNGL.uniformMatrix3fv(uniforms.normalMatrix, 1, 0, $0.baseAddress) }
        SCNGL.uniform4f(uniforms.diffuse, 1, 1, 1, 1)
        SCNGL.uniform3f(uniforms.emission, 0, 0, 0)
        SCNGL.uniform3f(uniforms.ambient, 1, 1, 1)
        SCNGL.uniform1f(uniforms.environment, 0)
        SCNGL.uniform3fv(uniforms.lightColor, 4, [Float](repeating: 0, count: 12))
        SKGL.activeTexture(SKGL.texture0)
        GLES.bindTexture?(SKGL.texture2D, texture(of: contents))
        GLES.texParameteri?(SKGL.texture2D, SKGL.wrapS, SKGL.clampToEdge)
        GLES.texParameteri?(SKGL.texture2D, SKGL.wrapT, SKGL.clampToEdge)
        SKGL.activeTexture(SCNGL.texture1)
        GLES.bindTexture?(SKGL.texture2D, white)
        SKGL.disable(SKGL.depthTest)
        SKGL.disable(SKGL.cullFace)
        SKGL.drawArrays(SKGL.triangles, 0, 6)
        SKGL.enable(SKGL.depthTest)
        SKGL.enable(SKGL.cullFace)
    }

    private func backgroundColor(of scene: SCNScene, in view: SCNView) -> (Float, Float, Float) {
        if let contents = scene.scene.background?.property.contents, let rgb = SCNRenderer.rgb(of: contents) { return rgb }
        if let color = view.state.geometry.backgroundColor, let values = CG.colorGetComponents(color) {
            switch CG.colorGetNumberOfComponents(color) {
            case 2: return (Float(values[0]), Float(values[0]), Float(values[0]))
            case 4...: return (Float(values[0]), Float(values[1]), Float(values[2]))
            default: break
            }
        }
        return (0, 0, 0)
    }

    /// The first node, in tree order, that has a camera.
    static func findCamera(in node: SCNNode) -> SCNNode? {
        if node.node.camera != nil { return node }
        for child in node.node.children {
            if let found = SCNRenderer.findCamera(in: child.unsafeCast(to: SCNNode.self)) { return found }
        }
        return nil
    }

    static func projection(_ camera: SCNCameraState?, aspect: Float) -> Matrix {
        let near = Float(camera?.zNear ?? 1), far = Float(camera?.zFar ?? 100)
        if let camera, camera.orthographic {
            return SCNMath.orthographic(scale: Float(camera.orthographicScale), aspect: aspect, near: near, far: far)
        }
        var fieldOfView = Float(camera?.fieldOfView ?? 60)
        if let camera, camera.horizontal {
            // The angle is the horizontal one; the projection wants the vertical.
            fieldOfView = 2 * atanf(tanf(fieldOfView * .pi / 360) / aspect) * 180 / .pi
        }
        return SCNMath.perspective(fieldOfView: fieldOfView, aspect: aspect, near: near, far: far)
    }

    private func collect(_ node: SCNNode, parent: Matrix, opacity: Float, into items: inout [Item],
                         lights: inout [(light: SCNLight, world: Matrix)]) {
        let state = node.node
        guard !state.hidden, state.opacity > 0 else { return }
        let model = SCNMath.multiply(parent, state.local)
        let combined = opacity * Float(state.opacity)
        if let geometry = state.geometry { items.append(Item(geometry: geometry, model: model, opacity: combined, skinner: state.skinner?.skinner)) }
        if let light = state.light { lights.append((light, model)) }
        for child in state.children {
            collect(child.unsafeCast(to: SCNNode.self), parent: model, opacity: combined, into: &items, lights: &lights)
        }
    }

    /// A frame's lights as the program takes them: up to four, each a
    /// direction toward the light (w 0) or a position (w 1) and a colour
    /// scaled by the intensity (1000 lumens is full), and the ambient light.
    private struct Shading {
        var positions = [Float](repeating: 0, count: 16)
        var colors = [Float](repeating: 0, count: 12)
        var ambient: [Float] = [0, 0, 0]
    }
    private var frameLights = Shading()

    private func shading(_ lights: [(light: SCNLight, world: Matrix)], cameraWorld: Matrix, defaultLighting: Bool) -> Shading {
        var result = Shading(), count = 0
        for (light, world) in lights {
            let state = light.light
            let rgb = SCNRenderer.rgb(of: state.color) ?? (1, 1, 1)
            let scale = Float(state.intensity) / 1000
            let color = [rgb.0 * scale, rgb.1 * scale, rgb.2 * scale]
            switch state.kind {
            case "ambient":
                for i in 0..<3 { result.ambient[i] += color[i] }
            case "directional", "omni", "spot":
                guard count < SCNGL.maxLights else { continue }
                if state.kind == "directional" {
                    // A directional light shines along its node's -z.
                    let z = (world[8], world[9], world[10]), length = max((z.0 * z.0 + z.1 * z.1 + z.2 * z.2).squareRoot(), 1e-6)
                    result.positions.replaceSubrange(count * 4..<count * 4 + 4, with: [z.0 / length, z.1 / length, z.2 / length, 0])
                } else {
                    result.positions.replaceSubrange(count * 4..<count * 4 + 4, with: [world[12], world[13], world[14], 1])
                }
                result.colors.replaceSubrange(count * 3..<count * 3 + 3, with: color)
                count += 1
            default: break
            }
        }
        // Without lights, the view's default one is at the camera.
        if lights.isEmpty, defaultLighting {
            result.ambient = [0.3, 0.3, 0.3]
            result.positions.replaceSubrange(0..<4, with: [cameraWorld[12], cameraWorld[13], cameraWorld[14], 1])
            result.colors.replaceSubrange(0..<3, with: [0.9, 0.9, 0.9])
        }
        return result
    }

    /// A material property's red, green and blue, when it is a colour; white
    /// for a picture or anything else, until textures are drawn.
    static func rgb(of contents: UnsafeMutableRawPointer?) -> (Float, Float, Float)? {
        guard let contents else { return nil }
        guard NSObject(contents).responds(to: "CGColor"), let c = SKRenderer.components(contents) else { return (1, 1, 1) }
        return (Float(c.0), Float(c.1), Float(c.2))
    }

    private static func alpha(of contents: UnsafeMutableRawPointer?) -> Float {
        guard let contents, NSObject(contents).responds(to: "CGColor"), let c = SKRenderer.components(contents) else { return 1 }
        return Float(c.3)
    }

    private func buffer(for geometry: SCNGeometry, mesh: SCNMesh) -> GLuint {
        let state = geometry.geometry
        if var entry = buffers[state.identifier] {
            if entry.revision != state.revision {
                SKGL.bindBuffer(SKGL.arrayBuffer, entry.buffer)
                SCNRenderer.interleaved(mesh.vertices, mesh.uv2).withUnsafeBytes { SKGL.bufferData(SKGL.arrayBuffer, $0.count, $0.baseAddress, SKGL.streamDraw) }
                entry.revision = state.revision
            }
            entry.used = frame
            buffers[state.identifier] = entry
            return entry.buffer
        }
        var name: GLuint = 0
        SKGL.genBuffers(1, &name)
        SKGL.bindBuffer(SKGL.arrayBuffer, name)
        SCNRenderer.interleaved(mesh.vertices, mesh.uv2).withUnsafeBytes { SKGL.bufferData(SKGL.arrayBuffer, $0.count, $0.baseAddress, SKGL.streamDraw) }
        buffers[state.identifier] = (state.revision, name, frame)
        return name
    }

    /// The vertices with their second texture coordinates (the first's again where there are none): ten floats each.
    static func interleaved(_ vertices: [Float], _ uv2: [Float]) -> [Float] {
        let count = vertices.count / 8
        var out = [Float](repeating: 0, count: count * 10)
        let second = uv2.count == count * 2
        for v in 0..<count {
            for k in 0..<8 { out[v * 10 + k] = vertices[v * 8 + k] }
            out[v * 10 + 8] = second ? uv2[v * 2] : vertices[v * 8 + 6]
            out[v * 10 + 9] = second ? uv2[v * 2 + 1] : vertices[v * 8 + 7]
        }
        return out
    }

    private func evictBuffers() {
        for (key, entry) in buffers where frame - entry.used > 600 {
            var name = entry.buffer
            SKGL.deleteBuffers(1, &name)
            buffers[key] = nil
        }
    }

    private func hasLightMap(_ material: SCNMaterial) -> Bool {
        material.selfIllumination().property.contents.map { NSObject($0).responds(to: "CGImage") } ?? false
    }

    /// The five pictures of the lava shader (flow, noise, cold, medium, hot), if the material has them.
    private func lavaSlots(of material: SCNMaterial) -> [UnsafeMutableRawPointer?]? {
        guard let objects = SCNExtras.materials.existing(material.objcObject)?.objects else { return nil }
        let slots = (0..<5).map { objects["Property\($0)"]?.unsafeCast(to: SCNMaterialProperty.self).property.contents }
        return slots.allSatisfy({ $0 != nil }) ? slots : nil
    }

    /// Flowing lava, as the scene's shader modifier makes it: two copies of the hot, medium and cold pictures slide
    /// along the flow map's directions and fade into one another, and the speed of the flow says which picture shows.
    private func drawLava(_ slots: [UnsafeMutableRawPointer?], element: (first: Int, count: Int), mvp: Matrix, model: Matrix) {
        if lavaProgram == 0 {
            let vertex = """
                attribute vec3 position;
                attribute vec3 normal;
                attribute vec2 coordinate;
                attribute vec2 coordinate2;
                uniform mat4 mvp;
                varying vec2 v_coordinate;
                void main() {
                    v_coordinate = vec2(coordinate.x, 1.0 - coordinate.y);
                    gl_Position = mvp * vec4(position, 1.0);
                }
                """
            let fragment = """
                precision highp float;
                uniform sampler2D flow;
                uniform sampler2D noise;
                uniform sampler2D cold;
                uniform sampler2D medium;
                uniform sampler2D hot;
                uniform float time;
                varying vec2 v_coordinate;
                void main() {
                    float tiling = 2.5;
                    // A noise map offsets the time, to hide where one loop fades to the next.
                    float cycleOffset = texture2D(noise, v_coordinate * 0.4).r;
                    float time0 = (2.0 * fract(time * 0.5) * 0.5) + cycleOffset;
                    float time1 = fract(time0 * 0.5);
                    float time2 = fract(time0 * 0.5 + 0.5);
                    vec2 direction = texture2D(flow, v_coordinate).rg * 2.0 - 1.0;
                    direction.r = -direction.r;
                    direction.g = -direction.g;
                    float strength = length(direction);
                    direction *= 0.12;
                    vec2 uv1 = fract((v_coordinate - direction / 2.0 + time1 * direction + 0.5 * direction) * tiling);
                    vec2 uv2 = fract((v_coordinate - direction / 2.0 + time2 * direction + 0.5 * direction) * tiling);
                    float blend = abs(0.5 - time1) / 0.5;
                    vec3 hotColor = mix(texture2D(hot, uv1).rgb, texture2D(hot, uv2).rgb, blend) * 1.3;
                    vec3 mediumColor = mix(texture2D(medium, uv1).rgb, texture2D(medium, uv2).rgb, blend) * 1.3;
                    vec3 coldColor = mix(texture2D(cold, uv1).rgb, texture2D(cold, uv2).rgb, blend);
                    strength = pow(strength * 2.5, 0.6);
                    vec3 result = mix(mediumColor, hotColor, clamp((strength - 0.5) * 2.0, 0.0, 1.0));
                    strength = (pow(strength, 0.5) - 0.5) * 2.2 + 0.5;
                    result = mix(result, coldColor, clamp(1.0 - strength, 0.0, 1.0));
                    gl_FragColor = vec4(result, 1.0);
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
            let made = SKGL.createProgram()
            SKGL.attachShader(made, compile(SKGL.vertexShader, vertex))
            SKGL.attachShader(made, compile(SKGL.fragmentShader, fragment))
            SKGL.bindAttribLocation(made, 0, "position")
            SKGL.bindAttribLocation(made, 1, "normal")
            SKGL.bindAttribLocation(made, 2, "coordinate")
            SKGL.bindAttribLocation(made, 3, "coordinate2")
            SKGL.linkProgram(made)
            lavaProgram = made
        }
        SKGL.useProgram(lavaProgram)
        mvp.withUnsafeBufferPointer { SCNGL.uniformMatrix4fv(SKGL.getUniformLocation(lavaProgram, "mvp"), 1, 0, $0.baseAddress) }
        SCNGL.uniform1f(SKGL.getUniformLocation(lavaProgram, "time"), time)
        let units: [(String, GLenum)] = [("flow", SKGL.texture0), ("noise", SCNGL.texture1), ("cold", SCNGL.texture2), ("medium", SCNGL.texture3), ("hot", 0x84C4)]
        for (index, (name, unit)) in units.enumerated() {
            SKGL.uniform1i(SKGL.getUniformLocation(lavaProgram, name), Int32(index))
            SKGL.activeTexture(unit)
            GLES.bindTexture?(SKGL.texture2D, texture(of: slots[index]))
            GLES.texParameteri?(SKGL.texture2D, SKGL.wrapS, SKGL.clampToEdge)
            GLES.texParameteri?(SKGL.texture2D, SKGL.wrapT, SKGL.clampToEdge)
        }
        SKGL.drawArrays(SKGL.triangles, Int32(element.first), Int32(element.count))
        SKGL.useProgram(program)
        SKGL.activeTexture(SKGL.texture0)
    }

    private func draw(_ item: Item, viewProjection: Matrix, translucent: Bool, defaultLighting: Bool) {
        let mesh = item.geometry.geometry.mesh
        guard !mesh.vertices.isEmpty else { return }
        let materials = item.geometry.materialList.map { $0.unsafeCast(to: SCNMaterial.self) }
        // Which elements this pass draws, before the buffer is touched.
        var drawn: [(element: (first: Int, count: Int), material: SCNMaterial, alpha: Float)] = []
        for (index, element) in mesh.elements.enumerated() where element.count > 0 {
            let material = materials[min(index, materials.count - 1)]
            let contents = material.diffuse().property.contents
            let alpha = SCNRenderer.alpha(of: contents) * Float(material.material.transparency) * item.opacity
            if (alpha < 1) == translucent { drawn.append((element, material, alpha)) }
        }
        guard !drawn.isEmpty else { return }

        // A skinned geometry's vertices are made again each frame, in the scene's space.
        var model = item.model
        if let skinner = item.skinner, !skinner.bones.isEmpty {
            let skinned = SCNSkinning.skin(mesh, with: skinner)
            if skinBuffer == 0 { SKGL.genBuffers(1, &skinBuffer) }
            SKGL.bindBuffer(SKGL.arrayBuffer, skinBuffer)
            SCNRenderer.interleaved(skinned, mesh.uv2).withUnsafeBytes { SKGL.bufferData(SKGL.arrayBuffer, $0.count, $0.baseAddress, SKGL.streamDraw) }
            model = SCNMath.identity
        } else {
            SKGL.bindBuffer(SKGL.arrayBuffer, buffer(for: item.geometry, mesh: mesh))
        }
        let stride: Int32 = 40
        SKGL.enableVertexAttribArray(attributes.0)
        SKGL.vertexAttribPointer(attributes.0, 3, SKGL.float, 0, stride, UnsafeRawPointer(bitPattern: 0))
        SKGL.enableVertexAttribArray(attributes.1)
        SKGL.vertexAttribPointer(attributes.1, 3, SKGL.float, 0, stride, UnsafeRawPointer(bitPattern: 12))
        SKGL.enableVertexAttribArray(attributes.2)
        SKGL.vertexAttribPointer(attributes.2, 2, SKGL.float, 0, stride, UnsafeRawPointer(bitPattern: 24))
        SKGL.enableVertexAttribArray(attributes.3)
        SKGL.vertexAttribPointer(attributes.3, 2, SKGL.float, 0, stride, UnsafeRawPointer(bitPattern: 32))

        let mvp = SCNMath.multiply(viewProjection, model)
        mvp.withUnsafeBufferPointer { SCNGL.uniformMatrix4fv(uniforms.mvp, 1, 0, $0.baseAddress) }
        model.withUnsafeBufferPointer { SCNGL.uniformMatrix4fv(uniforms.model, 1, 0, $0.baseAddress) }
        SCNMath.normalMatrix(model).withUnsafeBufferPointer { SCNGL.uniformMatrix3fv(uniforms.normalMatrix, 1, 0, $0.baseAddress) }

        for entry in drawn {
            let material = entry.material.material
            let diffuse = SCNRenderer.rgb(of: entry.material.diffuse().property.contents) ?? (1, 1, 1)
            let emission = SCNRenderer.rgb(of: entry.material.emission().property.contents) ?? (0, 0, 0)
            SCNGL.uniform4f(uniforms.diffuse, diffuse.0, diffuse.1, diffuse.2, entry.alpha)
            SCNGL.uniform3f(uniforms.emission, emission.0, emission.1, emission.2)
            if material.lightingModel == "SCNLightingModelConstant" {
                SCNGL.uniform3f(uniforms.ambient, 1, 1, 1)
                SCNGL.uniform3fv(uniforms.lightColor, 4, [Float](repeating: 0, count: 12))
                SCNGL.uniform1f(uniforms.environment, 0)
            } else {
                // A physically based material is lit by its scene's environment too, which is not read: a sky
                // above and a ground glow below stand in for it.
                SCNGL.uniform3f(uniforms.ambient, frameLights.ambient[0], frameLights.ambient[1], frameLights.ambient[2])
                // A baked light map has the sky's light in it already.
                SCNGL.uniform1f(uniforms.environment, material.lightingModel == "SCNLightingModelPhysicallyBased" ? (hasLightMap(entry.material) ? 0.12 : 1) : 0)
                SCNGL.uniform3fv(uniforms.lightColor, 4, frameLights.colors)
            }
            SCNGL.uniform4fv(uniforms.lightPosition, 4, frameLights.positions)
            let diffuseProperty = entry.material.diffuse().property, emissionProperty = entry.material.emission().property
            SKGL.activeTexture(SKGL.texture0)
            GLES.bindTexture?(SKGL.texture2D, texture(of: diffuseProperty.contents))
            GLES.texParameteri?(SKGL.texture2D, SKGL.wrapS, SCNRenderer.wrap(diffuseProperty.wrapS))
            GLES.texParameteri?(SKGL.texture2D, SKGL.wrapT, SCNRenderer.wrap(diffuseProperty.wrapT))
            let lightProperty = entry.material.selfIllumination().property, occlusionProperty = entry.material.ambientOcclusion().property
            let hasLight = lightProperty.contents.map { NSObject($0).responds(to: "CGImage") } ?? false
            let hasOcclusion = occlusionProperty.contents.map { NSObject($0).responds(to: "CGImage") } ?? false
            SCNGL.uniform4f(uniforms.maps, hasLight ? 1 : 0, hasOcclusion ? 1 : 0, lightProperty.mappingChannel == 1 ? 1 : 0, occlusionProperty.mappingChannel == 1 ? 1 : 0)
            SKGL.activeTexture(SCNGL.texture2)
            GLES.bindTexture?(SKGL.texture2D, texture(of: lightProperty.contents))
            GLES.texParameteri?(SKGL.texture2D, SKGL.wrapS, SCNRenderer.wrap(lightProperty.wrapS))
            GLES.texParameteri?(SKGL.texture2D, SKGL.wrapT, SCNRenderer.wrap(lightProperty.wrapT))
            SKGL.activeTexture(SCNGL.texture3)
            GLES.bindTexture?(SKGL.texture2D, texture(of: occlusionProperty.contents))
            GLES.texParameteri?(SKGL.texture2D, SKGL.wrapS, SCNRenderer.wrap(occlusionProperty.wrapS))
            GLES.texParameteri?(SKGL.texture2D, SKGL.wrapT, SCNRenderer.wrap(occlusionProperty.wrapT))
            SKGL.activeTexture(SCNGL.texture1)
            GLES.bindTexture?(SKGL.texture2D, texture(of: emissionProperty.contents))
            GLES.texParameteri?(SKGL.texture2D, SKGL.wrapS, SCNRenderer.wrap(emissionProperty.wrapS))
            GLES.texParameteri?(SKGL.texture2D, SKGL.wrapT, SCNRenderer.wrap(emissionProperty.wrapT))
            if material.doubleSided {
                SKGL.disable(SKGL.cullFace)
            } else {
                SKGL.enable(SKGL.cullFace)
                SCNGL.cullFace(material.cullMode == 1 ? SCNGL.front : SCNGL.back)
            }
            if let slots = lavaSlots(of: entry.material) {
                drawLava(slots, element: entry.element, mvp: mvp, model: model)
            } else {
                SKGL.drawArrays(SKGL.triangles, Int32(entry.element.first), Int32(entry.element.count))
            }
        }
    }
}
