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
        loaded = uniform1f != nil && uniform3f != nil && uniform4f != nil && uniformMatrix3fv != nil && uniformMatrix4fv != nil
            && depthMask != nil && cullFace != nil
        return loaded
    }

    static let depthBufferBit: UInt32 = 0x100, back: GLenum = 0x0405, front: GLenum = 0x0404
}

/// One view's drawing: its context, renderbuffers, program and meshes.
final class SCNRenderer {
    private let context: EAGLContext
    private var framebuffer: GLuint = 0, color: GLuint = 0, depth: GLuint = 0
    private var size = (width: 0, height: 0)
    private var program: GLuint = 0
    private var attributes: (GLuint, GLuint, GLuint) = (0, 1, 2)
    private struct Uniforms {
        var mvp: Int32 = -1, model: Int32 = -1, normalMatrix: Int32 = -1
        var diffuse: Int32 = -1, emission: Int32 = -1, light: Int32 = -1, ambient: Int32 = -1, amount: Int32 = -1
    }
    private var uniforms = Uniforms()
    /// Each geometry's vertices' buffer, by its identifier.
    private var buffers: [Int: (revision: Int, buffer: GLuint, used: Int)] = [:]
    private var frame = 0

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
            attributes = (attribute("position", 0), attribute("normal", 1), attribute("coordinate", 2))
            uniforms = Uniforms(mvp: uniform("mvp"), model: uniform("model"), normalMatrix: uniform("normalMatrix"),
                                diffuse: uniform("diffuse"), emission: uniform("emission"), light: uniform("lightPosition"),
                                ambient: uniform("ambient"), amount: uniform("amount"))
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
            uniform mat4 mvp;
            uniform mat4 model;
            uniform mat3 normalMatrix;
            varying vec3 v_normal;
            varying vec3 v_position;
            varying vec2 v_coordinate;
            void main() {
                v_normal = normalMatrix * normal;
                v_position = (model * vec4(position, 1.0)).xyz;
                v_coordinate = coordinate;
                gl_Position = mvp * vec4(position, 1.0);
            }
            """
        let fragment = """
            precision mediump float;
            uniform vec4 diffuse;
            uniform vec3 emission;
            uniform vec3 lightPosition;
            uniform float ambient;
            uniform float amount;
            varying vec3 v_normal;
            varying vec3 v_position;
            varying vec2 v_coordinate;
            void main() {
                vec3 n = normalize(v_normal);
                if (!gl_FrontFacing) { n = -n; }
                float lit = max(dot(n, normalize(lightPosition - v_position)), 0.0);
                vec3 rgb = diffuse.rgb * (ambient + amount * lit) + emission;
                gl_FragColor = vec4(rgb * diffuse.a, diffuse.a);
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
        SKGL.linkProgram(program)
        return program
    }

    // MARK: Drawing

    private struct Item {
        var geometry: SCNGeometry
        var model: Matrix
        var opacity: Float
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
        let background = backgroundColor(of: scene, in: view)
        SKGL.clearColor(background.0, background.1, background.2, 1)
        SCNGL.depthMask(1)
        SKGL.clear(SKGL.colorBufferBit | SCNGL.depthBufferBit)
        SKGL.useProgram(program)
        SKGL.enable(SKGL.depthTest)
        SKGL.enable(SKGL.cullFace)
        SKGL.disable(SKGL.blend)
        SKGL.bindBuffer(SKGL.arrayBuffer, 0)

        let root = scene.rootNode()
        let camera = pointOfView ?? findCamera(in: root)
        let cameraWorld = camera?.world ?? SCNMath.identity
        let viewMatrix = SCNMath.inverse(cameraWorld)
        let projection = self.projection(camera?.node.camera?.camera, aspect: Float(width) / Float(height))
        let viewProjection = SCNMath.multiply(projection, viewMatrix)
        SCNGL.uniform3f(uniforms.light, cameraWorld[12], cameraWorld[13], cameraWorld[14])

        var items: [Item] = []
        collect(root, parent: SCNMath.identity, opacity: 1, into: &items)
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

        if Renderbuffers.show(color, context: context.state.context, layer: layer, opaque: true) { Display.markDirty() }
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
    private func findCamera(in node: SCNNode) -> SCNNode? {
        if node.node.camera != nil { return node }
        for child in node.node.children {
            if let found = findCamera(in: child.unsafeCast(to: SCNNode.self)) { return found }
        }
        return nil
    }

    private func projection(_ camera: SCNCameraState?, aspect: Float) -> Matrix {
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

    private func collect(_ node: SCNNode, parent: Matrix, opacity: Float, into items: inout [Item]) {
        let state = node.node
        guard !state.hidden, state.opacity > 0 else { return }
        let model = SCNMath.multiply(parent, state.local)
        let combined = opacity * Float(state.opacity)
        if let geometry = state.geometry { items.append(Item(geometry: geometry, model: model, opacity: combined)) }
        for child in state.children { collect(child.unsafeCast(to: SCNNode.self), parent: model, opacity: combined, into: &items) }
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
                mesh.vertices.withUnsafeBytes { SKGL.bufferData(SKGL.arrayBuffer, $0.count, $0.baseAddress, SKGL.streamDraw) }
                entry.revision = state.revision
            }
            entry.used = frame
            buffers[state.identifier] = entry
            return entry.buffer
        }
        var name: GLuint = 0
        SKGL.genBuffers(1, &name)
        SKGL.bindBuffer(SKGL.arrayBuffer, name)
        mesh.vertices.withUnsafeBytes { SKGL.bufferData(SKGL.arrayBuffer, $0.count, $0.baseAddress, SKGL.streamDraw) }
        buffers[state.identifier] = (state.revision, name, frame)
        return name
    }

    private func evictBuffers() {
        for (key, entry) in buffers where frame - entry.used > 600 {
            var name = entry.buffer
            SKGL.deleteBuffers(1, &name)
            buffers[key] = nil
        }
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

        SKGL.bindBuffer(SKGL.arrayBuffer, buffer(for: item.geometry, mesh: mesh))
        let stride: Int32 = 32
        SKGL.enableVertexAttribArray(attributes.0)
        SKGL.vertexAttribPointer(attributes.0, 3, SKGL.float, 0, stride, UnsafeRawPointer(bitPattern: 0))
        SKGL.enableVertexAttribArray(attributes.1)
        SKGL.vertexAttribPointer(attributes.1, 3, SKGL.float, 0, stride, UnsafeRawPointer(bitPattern: 12))
        SKGL.enableVertexAttribArray(attributes.2)
        SKGL.vertexAttribPointer(attributes.2, 2, SKGL.float, 0, stride, UnsafeRawPointer(bitPattern: 24))

        let mvp = SCNMath.multiply(viewProjection, item.model)
        mvp.withUnsafeBufferPointer { SCNGL.uniformMatrix4fv(uniforms.mvp, 1, 0, $0.baseAddress) }
        item.model.withUnsafeBufferPointer { SCNGL.uniformMatrix4fv(uniforms.model, 1, 0, $0.baseAddress) }
        SCNMath.normalMatrix(item.model).withUnsafeBufferPointer { SCNGL.uniformMatrix3fv(uniforms.normalMatrix, 1, 0, $0.baseAddress) }

        for entry in drawn {
            let material = entry.material.material
            let diffuse = SCNRenderer.rgb(of: entry.material.diffuse().property.contents) ?? (1, 1, 1)
            let emission = SCNRenderer.rgb(of: entry.material.emission().property.contents) ?? (0, 0, 0)
            SCNGL.uniform4f(uniforms.diffuse, diffuse.0, diffuse.1, diffuse.2, entry.alpha)
            SCNGL.uniform3f(uniforms.emission, emission.0, emission.1, emission.2)
            if material.lightingModel == "SCNLightingModelConstant" {
                SCNGL.uniform1f(uniforms.ambient, 1)
                SCNGL.uniform1f(uniforms.amount, 0)
            } else {
                SCNGL.uniform1f(uniforms.ambient, defaultLighting ? 0.3 : 0)
                SCNGL.uniform1f(uniforms.amount, defaultLighting ? 0.9 : 0)
            }
            if material.doubleSided {
                SKGL.disable(SKGL.cullFace)
            } else {
                SKGL.enable(SKGL.cullFace)
                SCNGL.cullFace(material.cullMode == 1 ? SCNGL.front : SCNGL.back)
            }
            SKGL.drawArrays(SKGL.triangles, Int32(entry.element.first), Int32(entry.element.count))
        }
    }
}
