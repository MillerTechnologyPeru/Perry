#if os(macOS)
import AppKit
#else
import UIKit
#endif
import simd

// SpriteKit's Swift API: SKColor, warp geometry grids from arrays of
// positions, and the (deprecated) playground quick looks of nodes and
// textures.

#if os(macOS)
public typealias SKColor = NSColor
#else
public typealias SKColor = UIColor
#endif

@available(macOS 10.12, *)
extension SKWarpGeometryGrid {
    /// A grid of (columns + 1) x (rows + 1) vertices; empty arrays leave
    /// the grid's positions at their regular defaults.
    public convenience init(columns: Int, rows: Int,
                            sourcePositions: [SIMD2<Float>] = [SIMD2<Float>](),
                            destinationPositions: [SIMD2<Float>] = [SIMD2<Float>]()) {
        let vertices = (columns + 1) * (rows + 1)
        let source = Self.checked(sourcePositions, vertices)
        let destination = Self.checked(destinationPositions, vertices)
        self.init(__columns: columns, rows: rows, sourcePositions: source, destPositions: destination)
    }

    public func replacingBySourcePositions(positions source: [SIMD2<Float>]) -> SKWarpGeometryGrid {
        __replacingSourcePositions(source)
    }

    public func replacingByDestinationPositions(positions destination: [SIMD2<Float>]) -> SKWarpGeometryGrid {
        __replacingDestPositions(destination)
    }

    private static func checked(_ positions: [SIMD2<Float>], _ vertices: Int) -> [SIMD2<Float>]? {
        if positions.isEmpty { return nil }
        precondition(positions.count >= vertices, "a warp geometry grid needs a position for each of its vertices")
        return positions
    }
}

extension SKShapeNode: _CustomPlaygroundQuickLookable {
    @available(*, deprecated, message: "SKShapeNode.customPlaygroundQuickLook will be removed in a future Swift version")
    @MainActor @preconcurrency public var customPlaygroundQuickLook: PlaygroundQuickLook {
        .sprite(self)
    }
}

extension SKSpriteNode: _CustomPlaygroundQuickLookable {
    @available(*, deprecated, message: "SKSpriteNode.customPlaygroundQuickLook will be removed in a future Swift version")
    @MainActor @preconcurrency public var customPlaygroundQuickLook: PlaygroundQuickLook {
        if let texture { return texture.customPlaygroundQuickLook }
        return .color(color)
    }
}

extension SKTextureAtlas: _CustomPlaygroundQuickLookable {
    @available(*, deprecated, message: "SKTextureAtlas.customPlaygroundQuickLook will be removed in a future Swift version")
    public var customPlaygroundQuickLook: PlaygroundQuickLook {
        guard let name = textureNames.sorted().first else { return .text("SKTextureAtlas") }
        return textureNamed(name).customPlaygroundQuickLook
    }
}

extension SKTexture: _CustomPlaygroundQuickLookable {
    @available(*, deprecated, message: "SKTexture.customPlaygroundQuickLook will be removed in a future Swift version")
    public var customPlaygroundQuickLook: PlaygroundQuickLook {
        let image = cgImage()
        #if os(macOS)
        return .image(NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
        #else
        return .image(UIImage(cgImage: image))
        #endif
    }
}
