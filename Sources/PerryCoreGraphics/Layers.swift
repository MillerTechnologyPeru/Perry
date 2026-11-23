import CPerryCoreGraphics
import CPerryGeometry
import Glibc
import PerryObjCInterop

// CGLayers, tiled images and images masked by a color range.
//
// A layer is an offscreen bitmap context, premultiplied BGRA (UIKit's and
// Cairo's own layout) in the reference context's color space, one pixel per
// unit of the size asked for, which is in base space: the reference
// context's device space. Drawing a layer draws a snapshot of its bitmap,
// scaled into the rect.

final class LayerState: @unchecked Sendable {
    let size: CGSize
    let context: Ref

    init(size: CGSize, context: Ref) {
        self.size = size
        self.context = context
    }

    deinit { ObjCRuntime.release(context) }
}

@ObjCClass("CGLayer")
public final class CGLayerObject: NSObject {
    static let states = StateTable<LayerState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CGLayerObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CGLayerObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.layer }
}

@c(_CGLayerGetTypeID) public func CGLayerGetTypeID() -> UInt { TypeIDs.layer }

@DarwinC("_CGLayerCreateWithContext")
public func CGLayerCreateWithContext(_ context: Ref?, _ size: CGSize, _ auxiliaryInfo: Ref?) -> Ref? {
    guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return nil }
    let width = Int(Double(size.width).rounded(.up)), height = Int(Double(size.height).rounded(.up))
    let reference = Contexts.state(context).flatMap { ColorSpaces.state($0.space)?.model == 1 ? $0.space : nil }
    let space = reference.flatMap { ObjCRuntime.retain($0) } ?? CGColorSpaceCreateDeviceRGB()
    defer { ObjCRuntime.release(space) }
    // kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little.
    guard let bitmap = CGBitmapContextCreate(nil, width, height, 8, 0, space, 0x2002) else { return nil }
    return makeObject(CGLayerObject.objCClass, CGLayerObject.states, LayerState(size: size, context: bitmap))
}

@c(_CGLayerRetain) public func CGLayerRetain(_ layer: Ref?) -> Ref? { ObjCRuntime.retain(layer) }
@c(_CGLayerRelease) public func CGLayerRelease(_ layer: Ref?) { ObjCRuntime.release(layer) }

@DarwinC("_CGLayerGetSize")
public func CGLayerGetSize(_ layer: Ref?) -> CGSize { CGLayerObject.states[layer]?.size ?? CGSize(width: 0, height: 0) }

@c(_CGLayerGetContext) public func CGLayerGetContext(_ layer: Ref?) -> Ref? { CGLayerObject.states[layer]?.context }

/// The layer's contents scaled into the rect, in user space.
@DarwinC("_CGContextDrawLayerInRect")
public func CGContextDrawLayerInRect(_ context: Ref?, _ rect: CGRect, _ layer: Ref?) {
    guard let state = CGLayerObject.states[layer], Contexts.state(context) != nil,
          let image = CGBitmapContextCreateImage(state.context) else { return }
    defer { ObjCRuntime.release(image) }
    CGContextDrawImage(context, rect, image)
}

/// The layer at its own size with its origin at the point.
@DarwinC("_CGContextDrawLayerAtPoint")
public func CGContextDrawLayerAtPoint(_ context: Ref?, _ point: CGPoint, _ layer: Ref?) {
    guard let state = CGLayerObject.states[layer] else { return }
    CGContextDrawLayerInRect(context, CGRect(origin: point, size: state.size), layer)
}

/// The image repeated across the whole of what the context can draw into
/// (in user space), each copy the rect's size, one of them in the rect.
@DarwinC("_CGContextDrawTiledImage")
public func CGContextDrawTiledImage(_ context: Ref?, _ rect: CGRect, _ image: Ref?) {
    guard let state = Contexts.state(context), let image = Images.state(image) else { return }
    let r = CGRectStandardize(rect)
    let tileWidth = Double(r.size.width), tileHeight = Double(r.size.height)
    guard tileWidth > 0, tileHeight > 0, tileWidth.isFinite, tileHeight.isFinite else { return }
    // The device's area in user space.
    let device = CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: CGFloat(state.width), height: CGFloat(state.height)))
    let area = CGRectApplyAffineTransform(device, CGAffineTransformInvert(CGContextGetCTM(context)))
    let x0 = Double(r.origin.x), y0 = Double(r.origin.y)
    let firstColumn = ((Double(area.origin.x) - x0) / tileWidth).rounded(.down)
    let lastColumn = ((Double(area.origin.x + area.size.width) - x0) / tileWidth).rounded(.up)
    let firstRow = ((Double(area.origin.y) - y0) / tileHeight).rounded(.down)
    let lastRow = ((Double(area.origin.y + area.size.height) - y0) / tileHeight).rounded(.up)
    guard firstColumn.isFinite, lastColumn.isFinite, firstRow.isFinite, lastRow.isFinite else { return }
    let columns = lastColumn - firstColumn, rows = lastRow - firstRow
    // Tiles smaller than a pixel would be millions of draws for one color.
    guard columns > 0, rows > 0, columns * rows <= 4_000_000 else { return }
    Contexts.paint(context) { canvas in
        var row = firstRow
        while row < lastRow {
            var column = firstColumn
            while column < lastColumn {
                canvas.draw(image, x0 + column * tileWidth, y0 + row * tileHeight, tileWidth, tileHeight)
                column += 1
            }
            row += 1
        }
    }
}

/// A copy of the image in which pixels whose every color component lies in
/// its range, given as minimum and maximum pairs in the image's sample
/// values (0 to 2^bitsPerComponent - 1), are transparent. Nil for a mask or
/// an image with alpha, as CoreGraphics refuses those, and for color spaces
/// other than gray and RGB.
@c(_CGImageCreateWithMaskingColors)
public func CGImageCreateWithMaskingColors(_ image: Ref?, _ components: UnsafePointer<CGFloat>?) -> Ref? {
    guard let state = Images.state(image), let components, !state.format.hasAlpha else { return nil }
    let count = state.format.colorComponents
    guard count == 1 || count == 3 else { return nil }
    // The bitmap's 8-bit samples in the image's own range.
    let sampleScale = Double((1 << state.format.bitsPerComponent) - 1) / 255
    let ranges = (0..<count).map { (Double(components[$0 * 2]), Double(components[$0 * 2 + 1])) }
    var bitmap = state.bitmap
    bitmap.pixels.withUnsafeMutableBufferPointer { pixels in
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            var masked = true
            for channel in 0..<count {
                let value = Double(pixels[offset + channel]) * sampleScale
                if value < ranges[channel].0 || value > ranges[channel].1 {
                    masked = false
                    break
                }
            }
            if masked { for channel in 0..<4 { pixels[offset + channel] = 0 } }
        }
    }
    return Images.make(bitmap)
}
