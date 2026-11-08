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

extension Deceleration {
    /// Coasting from `velocity` (points a second, along one axis) in one go,
    /// for animations that carry content to where it comes to rest: the
    /// distance covered and the seconds it takes, or nil when the flick is
    /// too slow to coast. The speed decays by `rate` each millisecond, so
    /// the distance is the sum of that series and it stops once the speed
    /// is below `stopSpeed`.
    public static func glide(velocity: Double, rate: Double = normalDecelerationRate) -> (distance: Double, duration: Double)? {
        let speed = abs(velocity)
        guard speed > startSpeed, rate > 0, rate < 1 else { return nil }
        let perSecond = -1000 * log(rate)
        let duration = log(speed / stopSpeed) / perSecond
        let distance = speed * (1 - exp(-perSecond * duration)) / perSecond
        return (velocity < 0 ? -distance : distance, duration)
    }
}

/// Where content dragged past its edge shows: the overshoot shrinks the
/// further it goes, never reaching `dimension` (the view's length), as
/// UIScrollView's rubber band does. Within `low` to `high`, `offset`.
public func rubberBand(_ offset: Double, low: Double, high: Double, dimension: Double) -> Double {
    guard dimension > 0 else { return min(max(offset, low), high) }
    func stretch(_ overshoot: Double) -> Double { (1 - 1 / (overshoot * 0.55 / dimension + 1)) * dimension }
    if offset < low { return low - stretch(low - offset) }
    if offset > high { return high + stretch(offset - high) }
    return offset
}

/// Content let go past its edge, going back to `target` on a critically
/// damped spring, settling in about a third of a second.
public struct SpringBack {
    /// The spring's angular frequency, per second.
    public static let stiffness = 15.0
    /// A spring animation's response (its period, in seconds) for the same
    /// spring, critically damped.
    public static var response: Double { 2 * Double.pi / stiffness }
    let start: Double
    let target: Double
    let time: Double
    public private(set) var isFinished = false

    public init(from start: Double, to target: Double, time: Double) {
        (self.start, self.target, self.time) = (start, target, time)
        isFinished = abs(start - target) < 0.5
    }

    /// The position at `now`; finished once within half a point.
    public mutating func step(at now: Double) -> Double {
        let t = max(0, now - time), x0 = start - target
        let x = x0 * (1 + Self.stiffness * t) * exp(-Self.stiffness * t)
        if abs(x) < 0.5 { isFinished = true; return target }
        return target + x
    }
}
