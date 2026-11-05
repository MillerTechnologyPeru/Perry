//
//  NamedColor.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  Colors from asset catalogs, by name, through UIKit, since OpenSwiftUI's
//  own reads catalogs with CoreUI. A color UIKit doesn't find is the
//  accent color for the catalog's accent color, and gray otherwise.

#if (os(iOS) || os(visionOS)) && !OPENSWIFTUI_LINK_COREUI
public import Foundation
public import OpenSwiftUICore
import UIKit

@available(OpenSwiftUI_v1_0, *)
extension Color {
    /// Creates a color from a color set that you indicate by name.
    public init(_ name: String, bundle: Bundle? = nil) {
        if let color = UIColor(named: name, in: bundle ?? .main, compatibleWith: nil) {
            self.init(uiColor: color)
        } else {
            self = name == "AccentColor" ? .accentColor : .gray
        }
    }
}
#endif
