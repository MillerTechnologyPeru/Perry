//
//  ScrollPosition.swift
//  OpenSwiftUICore

package import Foundation

public struct ScrollPosition {
    /// Perry: the edge and the point last asked for. Nothing scrolls to
    /// them yet: they are kept so the position reads back what it was told.
    package var requestedEdge: Edge?
    package var requestedPoint: CGPoint?

    /// Perry: a position that asks for nothing.
    package init() {}
}
