import CoreGraphics
import Foundation
import simd

// GameplayKit's Swift API: paths and obstacles from arrays of points, and
// the generic component and state lookups, over the Objective-C methods
// the headers refine for Swift.

@available(macOS 10.11, *)
extension GKPath {
    public convenience init(points: [SIMD2<Float>], radius: Float, cyclical: Bool) {
        var points = points
        let count = points.count
        self.init(__points: &points, count: count, radius: radius, cyclical: cyclical)
    }
}

@available(macOS 10.12, *)
extension GKPath {
    public convenience init(points: [SIMD3<Float>], radius: Float, cyclical: Bool) {
        var points = points
        let count = points.count
        self.init(__float3Points: &points, count: count, radius: radius, cyclical: cyclical)
    }
}

@available(macOS 10.11, *)
extension GKPolygonObstacle {
    public convenience init(points: [SIMD2<Float>]) {
        var points = points
        let count = points.count
        self.init(__points: &points, count: count)
    }
}

@available(macOS 10.11, *)
extension GKEntity {
    public func component<ComponentType>(ofType componentClass: ComponentType.Type) -> ComponentType? where ComponentType: GKComponent {
        __component(for: componentClass) as? ComponentType
    }

    public func removeComponent<ComponentType>(ofType componentClass: ComponentType.Type) where ComponentType: GKComponent {
        __removeComponent(for: componentClass)
    }
}

/// -[GKStateMachine stateForClass:], which the header keeps out of Swift.
@objc private protocol StateLookup {
    @objc(stateForClass:) func state(forClass stateClass: AnyClass) -> GKState?
}

@available(macOS 10.11, *)
extension GKStateMachine {
    public func state<StateType>(forClass stateClass: StateType.Type) -> StateType? where StateType: GKState {
        unsafeBitCast(self, to: StateLookup.self).state(forClass: stateClass) as? StateType
    }
}
