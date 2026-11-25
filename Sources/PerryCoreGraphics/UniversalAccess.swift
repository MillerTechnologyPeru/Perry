// HIServices' Universal Access, which ApplicationServices re-exports and the
// loader maps here on Intel: screen zoom is never on.

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
/// Boolean UAZoomEnabled(void).
@c(_UAZoomEnabled)
public func UAZoomEnabled() -> UInt8 { 0 }
#endif
