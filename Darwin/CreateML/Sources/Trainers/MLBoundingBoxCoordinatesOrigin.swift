// MLBoundingBoxCoordinatesOrigin: how an object detector's annotations give their boxes.

import CoreML
import Foundation

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
public enum MLBoundingBoxCoordinatesOrigin : Sendable {
    case topLeft
    case bottomLeft
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLBoundingBoxCoordinatesOrigin : Equatable {}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLBoundingBoxCoordinatesOrigin : Hashable {}
