//
//  Search.swift
//  OpenSwiftUI
//
//  Status: Perry's implementation
//
//  searchable, as a search field above the view it modifies, wherever the
//  placement asks for it; the views under it are searching while the field
//  is being edited or has text.

#if os(iOS) || os(visionOS)
public import OpenSwiftUICore

// MARK: - SearchFieldPlacement

/// The placement of a search field in a view hierarchy.
@available(OpenSwiftUI_v3_0, *)
public struct SearchFieldPlacement: Sendable {
    enum Kind: Sendable { case automatic, toolbar, toolbarPrincipal, sidebar, navigationBarDrawer }
    var kind: Kind

    public static let automatic = SearchFieldPlacement(kind: .automatic)
    public static let toolbar = SearchFieldPlacement(kind: .toolbar)
    public static var toolbarPrincipal: SearchFieldPlacement { SearchFieldPlacement(kind: .toolbarPrincipal) }
    public static var sidebar: SearchFieldPlacement { SearchFieldPlacement(kind: .sidebar) }
    public static let navigationBarDrawer = SearchFieldPlacement(kind: .navigationBarDrawer)

    public static func navigationBarDrawer(displayMode: NavigationBarDrawerDisplayMode) -> SearchFieldPlacement {
        SearchFieldPlacement(kind: .navigationBarDrawer)
    }

    /// A mode that determines when to display a search field that appears
    /// in a navigation bar.
    public struct NavigationBarDrawerDisplayMode: Sendable {
        public static let automatic = NavigationBarDrawerDisplayMode()
        public static let always = NavigationBarDrawerDisplayMode()
    }
}

// MARK: - isSearching

struct IsSearchingKey: EnvironmentKey {
    static let defaultValue = false
}

@available(OpenSwiftUI_v3_0, *)
extension EnvironmentValues {
    /// A Boolean value that indicates when the user is searching.
    public var isSearching: Bool {
        get { self[IsSearchingKey.self] }
    }

    var isSearchingValue: Bool {
        get { self[IsSearchingKey.self] }
        set { self[IsSearchingKey.self] = newValue }
    }
}

// MARK: - searchable

@available(OpenSwiftUI_v3_0, *)
extension View {
    /// Marks this view as searchable, which configures the display of a
    /// search field.
    nonisolated public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: Text? = nil
    ) -> some View {
        modifier(SearchableModifier(text: text, isPresented: nil, prompt: prompt))
    }

    nonisolated public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: LocalizedStringKey
    ) -> some View {
        modifier(SearchableModifier(text: text, isPresented: nil, prompt: Text(prompt)))
    }

    @_disfavoredOverload
    nonisolated public func searchable<S>(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: S
    ) -> some View where S: StringProtocol {
        modifier(SearchableModifier(text: text, isPresented: nil, prompt: Text(prompt)))
    }

    /// Marks this view as searchable with programmatic presentation of the
    /// search field.
    nonisolated public func searchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: Text? = nil
    ) -> some View {
        modifier(SearchableModifier(text: text, isPresented: isPresented, prompt: prompt))
    }
}

/// A rounded search field above the content.
struct SearchableModifier: ViewModifier {
    var text: Binding<String>
    var isPresented: Binding<Bool>?
    var prompt: Text?
    @State private var isEditing = false

    func body(content: Content) -> some View {
        let searching = isEditing || !text.wrappedValue.isEmpty || isPresented?.wrappedValue == true
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                PlatformTextField(text: text, placeholder: prompt ?? Text("Search"), onEditingChanged: { editing in
                    isEditing = editing
                    isPresented?.wrappedValue = editing
                })
                if !text.wrappedValue.isEmpty {
                    Button {
                        text.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(Color(white: 0.46, opacity: 0.12))
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            content
                .environment(\.isSearchingValue, searching)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}
#endif
