// MLBoundingBoxAnchor: how an object detector's annotations give their boxes.

import CoreML
import Foundation

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
public enum MLBoundingBoxAnchor : Sendable {
    case center
    case topLeft
    case bottomLeft
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLBoundingBoxAnchor : Equatable {}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLBoundingBoxAnchor : Hashable {}
