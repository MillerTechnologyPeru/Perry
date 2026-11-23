// The geometry functions as members. The interface has most of them
// always emitted into clients; programs built against earlier SDKs, where
// they were ordinary members, link them, so they are inlinable here.

extension CGAffineTransform {
    @_alwaysEmitIntoClient public init(translationX tx: CGFloat, y ty: CGFloat) {
        self = CGAffineTransformMakeTranslation(tx, ty)
    }

    @_alwaysEmitIntoClient public init(scaleX sx: CGFloat, y sy: CGFloat) {
        self = CGAffineTransformMakeScale(sx, sy)
    }

    @_alwaysEmitIntoClient public init(rotationAngle angle: CGFloat) {
        self = CGAffineTransformMakeRotation(angle)
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    @_alwaysEmitIntoClient public init(_ components: CGAffineTransformComponents) {
        self = __CGAffineTransformMakeWithComponents(components)
    }

    @inlinable public var isIdentity: Bool {
        CGAffineTransformIsIdentity(self)
    }

    @_alwaysEmitIntoClient public func translatedBy(x tx: CGFloat, y ty: CGFloat) -> CGAffineTransform {
        CGAffineTransformTranslate(self, tx, ty)
    }

    @_alwaysEmitIntoClient public func scaledBy(x sx: CGFloat, y sy: CGFloat) -> CGAffineTransform {
        CGAffineTransformScale(self, sx, sy)
    }

    @_alwaysEmitIntoClient public func rotated(by angle: CGFloat) -> CGAffineTransform {
        CGAffineTransformRotate(self, angle)
    }

    @_alwaysEmitIntoClient public func inverted() -> CGAffineTransform {
        CGAffineTransformInvert(self)
    }

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    @_alwaysEmitIntoClient public func decomposed() -> CGAffineTransformComponents {
        __CGAffineTransformDecompose(self)
    }

    @_alwaysEmitIntoClient public func concatenating(_ t2: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransformConcat(self, t2)
    }

    @_alwaysEmitIntoClient public init(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ tx: CGFloat, _ ty: CGFloat) {
        self = CGAffineTransformMake(a, b, c, d, tx, ty)
    }
}

extension CGAffineTransformComponents {
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    @_alwaysEmitIntoClient public init(scale: CGSize = .init(width: 1, height: 1), horizontalShear: CGFloat = 0,
                                       rotation: CGFloat = 0, translation: CGVector = .zero) {
        self.init()
        self.scale = scale
        self.horizontalShear = horizontalShear
        self.rotation = rotation
        self.translation = translation
    }
}

extension CGPoint {
    @_alwaysEmitIntoClient public func applying(_ t: CGAffineTransform) -> CGPoint {
        CGPointApplyAffineTransform(self, t)
    }

    @_alwaysEmitIntoClient public func equalTo(_ point2: CGPoint) -> Bool {
        CGPointEqualToPoint(self, point2)
    }

    @inlinable public var dictionaryRepresentation: CFDictionary {
        CGPointCreateDictionaryRepresentation(self)
    }
}

extension CGSize {
    @_alwaysEmitIntoClient public func applying(_ t: CGAffineTransform) -> CGSize {
        CGSizeApplyAffineTransform(self, t)
    }

    @_alwaysEmitIntoClient public func equalTo(_ size2: CGSize) -> Bool {
        CGSizeEqualToSize(self, size2)
    }

    @inlinable public var dictionaryRepresentation: CFDictionary {
        CGSizeCreateDictionaryRepresentation(self)
    }
}

extension CGRect {
    @_alwaysEmitIntoClient public func applying(_ t: CGAffineTransform) -> CGRect {
        CGRectApplyAffineTransform(self, t)
    }

    @inlinable public static var null: CGRect { CGRectNull }
    @inlinable public static var infinite: CGRect { CGRectInfinite }
    @inlinable public var minX: CGFloat { CGRectGetMinX(self) }
    @inlinable public var midX: CGFloat { CGRectGetMidX(self) }
    @inlinable public var maxX: CGFloat { CGRectGetMaxX(self) }
    @inlinable public var minY: CGFloat { CGRectGetMinY(self) }
    @inlinable public var midY: CGFloat { CGRectGetMidY(self) }
    @inlinable public var maxY: CGFloat { CGRectGetMaxY(self) }
    @inlinable public var width: CGFloat { CGRectGetWidth(self) }
    @inlinable public var height: CGFloat { CGRectGetHeight(self) }

    @_alwaysEmitIntoClient public func equalTo(_ rect2: CGRect) -> Bool {
        CGRectEqualToRect(self, rect2)
    }

    @inlinable public var standardized: CGRect { CGRectStandardize(self) }
    @inlinable public var isEmpty: Bool { CGRectIsEmpty(self) }
    @inlinable public var isNull: Bool { CGRectIsNull(self) }
    @inlinable public var isInfinite: Bool { CGRectIsInfinite(self) }

    @_alwaysEmitIntoClient public func insetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        CGRectInset(self, dx, dy)
    }

    @inlinable public var integral: CGRect { CGRectIntegral(self) }

    @_alwaysEmitIntoClient public func union(_ r2: CGRect) -> CGRect {
        CGRectUnion(self, r2)
    }

    @_alwaysEmitIntoClient public func intersection(_ r2: CGRect) -> CGRect {
        CGRectIntersection(self, r2)
    }

    @_alwaysEmitIntoClient public func offsetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        CGRectOffset(self, dx, dy)
    }

    @_alwaysEmitIntoClient public func contains(_ point: CGPoint) -> Bool {
        CGRectContainsPoint(self, point)
    }

    @_alwaysEmitIntoClient public func contains(_ rect2: CGRect) -> Bool {
        CGRectContainsRect(self, rect2)
    }

    @_alwaysEmitIntoClient public func intersects(_ rect2: CGRect) -> Bool {
        CGRectIntersectsRect(self, rect2)
    }

    @inlinable public var dictionaryRepresentation: CFDictionary {
        CGRectCreateDictionaryRepresentation(self)
    }
}
