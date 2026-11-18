//
//  KeyframeAnimation.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  Keyframes: tracks of keyframes for a value's properties, the builders
//  that collect them, and the animator view and modifier that would play
//  them. Perry keeps what an app declares and plays none of it: tracks
//  resolve to nothing, and an animator shows its content for the initial
//  value. Also the spring animations made from a `Spring`, which do animate.

#if os(iOS) || os(visionOS)
public import Foundation
public import OpenSwiftUICore

// MARK: - Keyframes

/// A description of how a value changes over time, made of keyframe tracks.
@available(OpenSwiftUI_v1_0, *)
public protocol Keyframes<Value> {
    /// The type of value the keyframes animate.
    associatedtype Value = Body.Value

    /// The type of the keyframes this type is made of.
    associatedtype Body: Keyframes

    /// The keyframes this type is made of.
    @KeyframesBuilder<Value>
    var body: Body { get }

    /// Adds the keyframes to what an animator plays.
    func _resolve(into resolved: inout _ResolvedKeyframes<Value>, initialValue: Value, initialVelocity: Value?)
}

@available(OpenSwiftUI_v1_0, *)
extension Keyframes where Value == Body.Value {
    /// Keyframes made of others resolve as their body does.
    public func _resolve(into resolved: inout _ResolvedKeyframes<Value>, initialValue: Value, initialVelocity: Value?) {
        body._resolve(into: &resolved, initialValue: initialValue, initialVelocity: initialVelocity)
    }
}

@available(OpenSwiftUI_v1_0, *)
extension Keyframes where Body == Never {
    /// Primitive keyframes have no body to ask for.
    public var body: Never {
        preconditionFailure("\(Self.self) is primitive keyframes")
    }
}

@available(OpenSwiftUI_v1_0, *)
extension Never: Keyframes {
    /// There is no value of `Never` to resolve.
    public func _resolve(into resolved: inout _ResolvedKeyframes<Never>, initialValue: Never, initialVelocity: Never?) {}
}

/// What keyframes resolve into. Nothing is recorded here, as nothing plays
/// keyframes.
@available(OpenSwiftUI_v1_0, *)
public struct _ResolvedKeyframes<Value> {}

@available(*, unavailable)
extension _ResolvedKeyframes: Sendable {}

// MARK: - Keyframe track content

/// The keyframes of one track: a sequence of values to reach, each in its
/// own way.
@available(OpenSwiftUI_v1_0, *)
public protocol KeyframeTrackContent<Value> {
    /// The type of value the track animates.
    associatedtype Value: Animatable = Body.Value

    /// The type of the content this type is made of.
    associatedtype Body: KeyframeTrackContent

    /// The content this type is made of.
    @KeyframeTrackContentBuilder<Value>
    var body: Body { get }

    /// Adds the keyframes to what a track plays.
    func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>)
}

@available(OpenSwiftUI_v1_0, *)
extension KeyframeTrackContent where Value == Body.Value {
    /// Content made of other content resolves as its body does.
    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {
        body._resolve(into: &resolved)
    }
}

/// What a track's content resolves into. Nothing is recorded here, as
/// nothing plays keyframes.
@available(OpenSwiftUI_v1_0, *)
public struct _ResolvedKeyframeTrackContent<Value> where Value: Animatable {}

@available(*, unavailable)
extension _ResolvedKeyframeTrackContent: Sendable {}

// MARK: - Keyframes

/// A keyframe that reaches its value along a cubic curve.
@available(OpenSwiftUI_v1_0, *)
public struct CubicKeyframe<Value>: KeyframeTrackContent where Value: Animatable {
    var to: Value
    var duration: TimeInterval
    var startVelocity: Value?
    var endVelocity: Value?

    /// Creates a keyframe that reaches `to` in `duration` seconds, with the
    /// given velocities at its ends.
    public init(_ to: Value, duration: TimeInterval, startVelocity: Value? = nil, endVelocity: Value? = nil) {
        self.to = to
        self.duration = duration
        self.startVelocity = startVelocity
        self.endVelocity = endVelocity
    }

    /// Nothing is recorded, as nothing plays keyframes.
    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {}

    public typealias Body = CubicKeyframe<Value>

    /// A keyframe is its own content.
    public var body: CubicKeyframe<Value> { return self }
}

/// A keyframe that reaches its value as a spring does.
@available(OpenSwiftUI_v1_0, *)
public struct SpringKeyframe<Value>: KeyframeTrackContent where Value: Animatable {
    var to: Value
    var duration: TimeInterval?
    var spring: Spring
    var startVelocity: Value?

    /// Creates a keyframe that springs to `to`, for `duration` seconds or
    /// for as long as the spring takes to settle.
    public init(_ to: Value, duration: TimeInterval? = nil, spring: Spring = Spring(), startVelocity: Value? = nil) {
        self.to = to
        self.duration = duration
        self.spring = spring
        self.startVelocity = startVelocity
    }

    /// Nothing is recorded, as nothing plays keyframes.
    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {}

    public typealias Body = SpringKeyframe<Value>

    /// A keyframe is its own content.
    public var body: SpringKeyframe<Value> { return self }
}

/// A keyframe that reaches its value in a straight line, paced by a timing
/// curve.
@available(OpenSwiftUI_v1_0, *)
public struct LinearKeyframe<Value>: KeyframeTrackContent where Value: Animatable {
    var to: Value
    var duration: TimeInterval
    var timingCurve: UnitCurve

    /// Creates a keyframe that reaches `to` in `duration` seconds.
    public init(_ to: Value, duration: TimeInterval, timingCurve: UnitCurve = .linear) {
        self.to = to
        self.duration = duration
        self.timingCurve = timingCurve
    }

    /// Nothing is recorded, as nothing plays keyframes.
    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {}

    public typealias Body = LinearKeyframe<Value>

    /// A keyframe is its own content.
    public var body: LinearKeyframe<Value> { return self }
}

/// A keyframe that jumps to its value at once.
@available(OpenSwiftUI_v1_0, *)
public struct MoveKeyframe<Value>: KeyframeTrackContent where Value: Animatable {
    var to: Value

    /// Creates a keyframe that sets the value to `to`.
    public init(_ to: Value) {
        self.to = to
    }

    /// Nothing is recorded, as nothing plays keyframes.
    public func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<Value>) {}

    public typealias Body = MoveKeyframe<Value>

    /// A keyframe is its own content.
    public var body: MoveKeyframe<Value> { return self }
}

/// Two pieces of a track's content, one after the other.
struct KeyframeTrackContentPair<First, Second>: KeyframeTrackContent where First: KeyframeTrackContent, Second: KeyframeTrackContent, First.Value == Second.Value {
    typealias Value = First.Value
    typealias Body = KeyframeTrackContentPair<First, Second>

    var first: First
    var second: Second

    var body: KeyframeTrackContentPair<First, Second> { return self }

    func _resolve(into resolved: inout _ResolvedKeyframeTrackContent<First.Value>) {
        first._resolve(into: &resolved)
        second._resolve(into: &resolved)
    }
}

// MARK: - KeyframeTrackContentBuilder

/// The builder that collects a track's keyframes.
@available(OpenSwiftUI_v1_0, *)
@resultBuilder
public struct KeyframeTrackContentBuilder<Value> where Value: Animatable {
    /// A keyframe written in the builder's closure.
    public static func buildExpression<K>(_ expression: K) -> K where Value == K.Value, K: KeyframeTrackContent {
        expression
    }

    /// The first keyframe of a track.
    public static func buildPartialBlock<K>(first: K) -> K where Value == K.Value, K: KeyframeTrackContent {
        first
    }

    /// The keyframes so far, followed by the next one.
    public static func buildPartialBlock(accumulated: some KeyframeTrackContent<Value>, next: some KeyframeTrackContent<Value>) -> some KeyframeTrackContent<Value> {
        KeyframeTrackContentPair(first: accumulated, second: next)
    }
}

@available(*, unavailable)
extension KeyframeTrackContentBuilder: Sendable {}

// MARK: - KeyframeTrack

/// The keyframes for one property of a value, or for the value itself.
@available(OpenSwiftUI_v1_0, *)
public struct KeyframeTrack<Root, Value, Content>: Keyframes where Value == Content.Value, Content: KeyframeTrackContent {
    var keyPath: WritableKeyPath<Root, Value>
    var content: Content

    init(keyPath: WritableKeyPath<Root, Value>, content: Content) {
        self.keyPath = keyPath
        self.content = content
    }

    /// Creates a track that animates the whole value.
    public init(@KeyframeTrackContentBuilder<Root> content: () -> Content) where Root == Value {
        self.init(keyPath: \Root.self, content: content())
    }

    /// Creates a track that animates the property at `keyPath`.
    public init(_ keyPath: WritableKeyPath<Root, Value>, @KeyframeTrackContentBuilder<Value> content: () -> Content) {
        self.init(keyPath: keyPath, content: content())
    }

    /// A track is keyframes for its root value. Nothing is recorded.
    public func _resolve(into resolved: inout _ResolvedKeyframes<Root>, initialValue: Root, initialVelocity: Root?) {}

    public typealias Body = Never
}

@available(*, unavailable)
extension KeyframeTrack: Sendable {}

/// Two sets of keyframes for the same value, playing together.
struct KeyframesPair<First, Second>: Keyframes where First: Keyframes, Second: Keyframes, First.Value == Second.Value {
    typealias Value = First.Value
    typealias Body = Never

    var first: First
    var second: Second

    func _resolve(into resolved: inout _ResolvedKeyframes<First.Value>, initialValue: First.Value, initialVelocity: First.Value?) {
        first._resolve(into: &resolved, initialValue: initialValue, initialVelocity: initialVelocity)
        second._resolve(into: &resolved, initialValue: initialValue, initialVelocity: initialVelocity)
    }
}

// MARK: - KeyframesBuilder

/// The builder that collects keyframe tracks, or the keyframes of a single
/// track for the whole value.
@available(OpenSwiftUI_v1_0, *)
@resultBuilder
public struct KeyframesBuilder<Value> {
    /// A keyframe written in the builder's closure.
    public static func buildExpression<K>(_ expression: K) -> K where Value == K.Value, K: KeyframeTrackContent {
        expression
    }

    /// The first keyframe of a track.
    public static func buildPartialBlock<K>(first: K) -> K where Value == K.Value, K: KeyframeTrackContent {
        first
    }

    /// The keyframes so far, followed by the next one.
    public static func buildPartialBlock(accumulated: some KeyframeTrackContent<Value>, next: some KeyframeTrackContent<Value>) -> some KeyframeTrackContent<Value> {
        KeyframeTrackContentPair(first: accumulated, second: next)
    }

    /// Keyframes written without a track animate the whole value.
    public static func buildFinalResult<Content>(_ component: Content) -> KeyframeTrack<Value, Value, Content> where Value == Content.Value, Content: KeyframeTrackContent {
        KeyframeTrack(keyPath: \Value.self, content: component)
    }

    /// A track written in the builder's closure.
    public static func buildExpression<Content>(_ expression: Content) -> Content where Value == Content.Value, Content: Keyframes {
        expression
    }

    /// The first track.
    public static func buildPartialBlock<Content>(first: Content) -> Content where Value == Content.Value, Content: Keyframes {
        first
    }

    /// The tracks so far, together with the next one.
    public static func buildPartialBlock(accumulated: some Keyframes<Value>, next: some Keyframes<Value>) -> some Keyframes<Value> {
        KeyframesPair(first: accumulated, second: next)
    }

    /// Tracks are the builder's result as they are.
    public static func buildFinalResult<Content>(_ component: Content) -> Content where Value == Content.Value, Content: Keyframes {
        component
    }
}

@available(*, unavailable)
extension KeyframesBuilder: Sendable {}

// MARK: - KeyframeAnimator

/// A view that would animate its content through keyframes: it shows the
/// content for the initial value and stays there.
@available(OpenSwiftUI_v1_0, *)
nonisolated public struct KeyframeAnimator<Value, KeyframePath, Content>: View where Value == KeyframePath.Value, KeyframePath: Keyframes, Content: View {
    var initialValue: Value
    var content: (Value) -> Content
    var keyframes: (Value) -> KeyframePath

    /// Creates an animator that plays its keyframes whenever `trigger`
    /// changes. The keyframes are kept and not played.
    nonisolated public init(initialValue: Value, trigger: some Equatable, @ViewBuilder content: @escaping (Value) -> Content, @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath) {
        self.initialValue = initialValue
        self.content = content
        self.keyframes = keyframes
    }

    /// The content for the initial value.
    public var body: Content {
        content(initialValue)
    }
}

@available(*, unavailable)
extension KeyframeAnimator: Sendable {}

/// Shows what a keyframe animator's content closure made of the view the
/// modifier is applied to, which the closure refers to through a
/// placeholder.
private struct KeyframeAnimatorContent<Source, Result>: MultiViewModifier, PrimitiveViewModifier where Source: View, Result: View {
    var result: Result

    init(_ source: Source.Type, result: Result) {
        self.result = result
    }

    nonisolated static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var inputs = inputs
        inputs.pushModifierBody(PlaceholderContentView<Source>.self, body: body)
        return Result._makeView(view: modifier[\.result], inputs: inputs)
    }
}

@available(OpenSwiftUI_v1_0, *)
extension View {
    /// Would animate this view through keyframes whenever `trigger`
    /// changes: the view shows as `content` makes it for the initial value.
    nonisolated public func keyframeAnimator<Value>(initialValue: Value, trigger: some Equatable, @ViewBuilder content: @escaping @Sendable (PlaceholderContentView<Self>, Value) -> some View, @KeyframesBuilder<Value> keyframes: @escaping (Value) -> some Keyframes<Value>) -> some View {
        modifier(KeyframeAnimatorContent(Self.self, result: content(PlaceholderContentView<Self>(), initialValue)))
    }

    /// Would animate this view through keyframes, over and over if
    /// `repeating`: the view shows as `content` makes it for the initial
    /// value.
    nonisolated public func keyframeAnimator<Value>(initialValue: Value, repeating: Bool = true, @ViewBuilder content: @escaping @Sendable (PlaceholderContentView<Self>, Value) -> some View, @KeyframesBuilder<Value> keyframes: @escaping (Value) -> some Keyframes<Value>) -> some View {
        modifier(KeyframeAnimatorContent(Self.self, result: content(PlaceholderContentView<Self>(), initialValue)))
    }
}

// MARK: - Spring animations

@available(OpenSwiftUI_v1_0, *)
extension Animation {
    /// A spring animation with the response and damping of `spring`.
    public static func spring(_ spring: Spring, blendDuration: TimeInterval = 0.0) -> Animation {
        Animation.spring(response: spring.response, dampingFraction: spring.dampingRatio, blendDuration: blendDuration)
    }

    /// An interpolating spring animation with the mass, stiffness and
    /// damping of `spring`.
    public static func interpolatingSpring(_ spring: Spring, initialVelocity: Double = 0.0) -> Animation {
        Animation.interpolatingSpring(mass: spring.mass, stiffness: spring.stiffness, damping: spring.damping, initialVelocity: initialVelocity)
    }
}
#endif
