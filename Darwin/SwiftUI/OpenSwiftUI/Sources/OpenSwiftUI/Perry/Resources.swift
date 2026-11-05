//
//  Resources.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  Images and colors from the resources asset catalogs generate symbols
//  for: by the name and bundle Perry's DeveloperToolsSupport keeps.

#if os(iOS) || os(visionOS)
@_spi(Perry) public import DeveloperToolsSupport
public import OpenSwiftUICore

@available(OpenSwiftUI_v5_0, *)
extension Image {
    /// Initialize an `Image` with an image resource.
    public init(_ resource: ImageResource) {
        self.init(resource.name, bundle: resource.bundle)
    }
}

@available(OpenSwiftUI_v5_0, *)
extension Color {
    /// Initialize a `Color` with a color resource.
    public init(_ resource: ColorResource) {
        self.init(resource.name, bundle: resource.bundle)
    }
}
#endif
