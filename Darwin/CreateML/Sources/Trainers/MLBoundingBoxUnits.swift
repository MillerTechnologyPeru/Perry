// MLBoundingBoxUnits: how an object detector's annotations give their boxes.

import CoreML
import Foundation

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
public enum MLBoundingBoxUnits : Sendable {
    case pixel
    case normalized
}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLBoundingBoxUnits : Equatable {}

@available(macOS 10.15, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
extension MLBoundingBoxUnits : Hashable {}
