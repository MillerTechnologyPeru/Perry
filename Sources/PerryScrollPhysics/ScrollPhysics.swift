// Scrolling with a finger, as UIScrollView and AppKit's touch scrolling do
// it, shared by Perry's UIKit and AppKit: when a drag becomes a pan, the
// finger's velocity from its last moments, and coasting on after it lifts,
// slowing by the deceleration rate each millisecond.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// The distance a finger moves before a touch becomes a pan, in points.
public let panThreshold = 10.0

/// UIScrollView.DecelerationRate.normal: the velocity kept each millisecond.
public let normalDecelerationRate = 0.998

/// A finger's recent positions, for its velocity when it lifts.
public struct VelocityTracker {
    /// How far back positions count, in seconds.
    public static let window = 0.1

    private var samples: [(x: Double, y: Double, time: Double)] = []

    public init() {}

    /// Starts over from a finger's first position.
    public mutating func reset(x: Double, y: Double, time: Double) { samples = [(x, y, time)] }

    public mutating func add(x: Double, y: Double, time: Double) {
        samples.append((x, y, time))
        samples.removeAll { time - $0.time > Self.window }
    }

    /// Points per second, along each axis, over the recent positions.
    public var velocity: (x: Double, y: Double) {
        guard let first = samples.first, let last = samples.last, last.time > first.time else { return (0, 0) }
        let time = last.time - first.time
        return ((last.x - first.x) / time, (last.y - first.y) / time)
    }
}

/// Coasting after a flick: the distance to move each step, slowing until
/// the speed falls below `stopSpeed`.
public struct Deceleration {
    /// Below this speed, in points a second, coasting stops.
    public static let stopSpeed = 10.0
    /// Flicks slower than this don't coast.
    public static let startSpeed = 50.0

    public private(set) var velocity: (x: Double, y: Double)
    public let rate: Double
    private var time: Double

    /// Coasting from `velocity` (points a second) at `time`, or nil when
    /// the flick is too slow to coast.
    public init?(velocity: (x: Double, y: Double), rate: Double = normalDecelerationRate, time: Double) {
        guard (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot() > Self.startSpeed else { return nil }
        (self.velocity, self.rate, self.time) = (velocity, rate, time)
    }

    /// Whether coasting has slowed to a stop: after the step that brought
    /// it below `stopSpeed`.
    public var isFinished: Bool { (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot() < Self.stopSpeed }

    /// The distance to move since the last step, at `now`, at the speed
    /// coasting had; then the speed slows for the time that passed.
    public mutating func step(at now: Double) -> (x: Double, y: Double) {
        let elapsed = now - time
        guard elapsed > 0 else { return (0, 0) }
        let distance = (velocity.x * elapsed, velocity.y * elapsed)
        let kept = pow(rate, elapsed * 1000)
        velocity = (velocity.x * kept, velocity.y * kept)
        time = now
        return distance
    }
}
