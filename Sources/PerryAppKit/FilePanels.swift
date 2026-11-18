import CPerryGeometry
import CSDL3
import Glibc
import PerryObjCInterop
import SDL3Swift

// NSSavePanel and NSOpenPanel, as the desktop's own file chooser: SDL's
// file dialogs (the XDG desktop portal, or zenity). The panel itself is
// never shown; it keeps what the program set and what was chosen. A modal
// panel runs the event loop until the chooser answers; a sheet answers its
// completion handler, or its modal delegate's did-end selector, when it
// does. Accessory views have nowhere to go, and are kept unshown.

/// One question to the desktop's file chooser.
enum FileDialogs {
    enum Kind {
        case save, openFiles, openFolders
    }

    final class Request {
        let finish: ([String]?) -> Void
        /// C strings SDL reads until it answers.
        var strings: [UnsafeMutablePointer<CChar>] = []
        var filters: UnsafeMutablePointer<SDL_DialogFileFilter>?

        init(finish: @escaping ([String]?) -> Void) { self.finish = finish }

        func keep(_ string: String) -> UnsafeMutablePointer<CChar> {
            let copy = strdup(string)!
            strings.append(copy)
            return copy
        }

        deinit {
            strings.forEach { free($0) }
            filters?.deallocate()
        }
    }

    /// The chooser's answer, on whatever thread SDL gives it: the paths,
    /// or nil when it was cancelled or failed. `finish` runs on the main
    /// thread.
    static let callback: SDL_DialogFileCallback = { userdata, list, _ in
        guard let userdata else { return }
        let request = Unmanaged<Request>.fromOpaque(userdata).takeRetainedValue()
        var paths: [String]?
        if let list {
            if list.pointee == nil {
                paths = nil
            } else {
                var chosen: [String] = []
                var index = 0
                while let path = list[index] {
                    chosen.append(String(cString: path))
                    index += 1
                }
                paths = chosen
            }
        } else {
            appKitWarning("file panel: \(String(cString: SDL_GetError()))")
        }
        Dispatch.onMain { request.finish(paths) }
    }

    /// Asks the chooser. `types` are file extensions to offer; `location`
    /// is the folder, or file, it starts at.
    static func show(_ kind: Kind, over window: NSWindow?, location: String?, types: [String], multiple: Bool,
                     finish: @escaping ([String]?) -> Void) {
        let request = Request(finish: finish)
        let parent = window?.sdlWindow?.unsafePointer
        let start = location.map { request.keep($0) }
        var count: Int32 = 0
        if !types.isEmpty {
            let filters = UnsafeMutablePointer<SDL_DialogFileFilter>.allocate(capacity: 1)
            let pattern = types.map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }.joined(separator: ";")
            filters.initialize(to: SDL_DialogFileFilter(name: request.keep(types.joined(separator: ", ")), pattern: request.keep(pattern)))
            request.filters = filters
            count = 1
        }
        let userdata = Unmanaged.passRetained(request).toOpaque()
        switch kind {
        case .save:
            SDL_ShowSaveFileDialog(callback, userdata, parent, request.filters, count, start)
        case .openFiles:
            SDL_ShowOpenFileDialog(callback, userdata, parent, request.filters, count, start, multiple)
        case .openFolders:
            SDL_ShowOpenFolderDialog(callback, userdata, parent, start, multiple)
        }
    }
}

@ObjCClass("NSSavePanel")
open class NSSavePanel: NSPanel {
    var directoryPath: String?
    var nameFieldStringValue = ""
    var message = ""
    var prompt = ""
    var accessory: NSObject?
    var allowedFileTypes: [String] = []
    var allowsOtherFileTypes = false
    /// What was chosen: one path for a save panel, any number for an open
    /// panel.
    var chosen: [String] = []
    /// The answer of a modal run, while it waits.
    var modalResponse: Int?
    /// Extensions of folders that are chosen as files: a file chosen in one
    /// chooses the folder.
    var packageExtensions: Set<String> = []

    /// The package a path is in, or the path.
    func package(of path: String) -> String {
        guard !packageExtensions.isEmpty else { return path }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        for (index, part) in parts.enumerated() {
            guard let dot = part.lastIndex(of: "."), packageExtensions.contains(String(part[part.index(after: dot)...])) else { continue }
            return parts[...index].joined(separator: "/")
        }
        return path
    }

    @ObjCClassMethod("savePanel")
    static func savePanel() -> NSSavePanel { NSSavePanel(contentRect: CGRect(x: 0, y: 0, width: 480, height: 320), styleMask: 3, backing: 2, defer: true) }

    var dialogKind: FileDialogs.Kind { .save }
    var allowsMultiple: Bool { false }

    /// Where the chooser starts: the directory, with the name in it for a
    /// save panel.
    var startLocation: String? {
        let directory = directoryPath ?? defaultDirectory
        guard dialogKind == .save, !nameFieldStringValue.isEmpty else { return directory.map { $0.hasSuffix("/") ? $0 : $0 + "/" } }
        return (directory ?? ".") + "/" + nameFieldStringValue
    }

    var defaultDirectory: String? {
        typealias Home = @convention(c) () -> UnsafeMutableRawPointer?
        guard let symbol = Symbols.symbol("/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation", "_NSHomeDirectory"),
              let home = unsafeBitCast(symbol, to: Home.self)() else { return nil }
        return String(objCArgument: home) + "/Documents"
    }

    /// The path a save panel saves at: with the required extension when
    /// the name has none of the allowed ones.
    func savePath(_ path: String) -> String {
        guard let required = allowedFileTypes.first, !required.isEmpty else { return path }
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let ext = name.contains(".") ? String(name.split(separator: ".").last!) : ""
        if allowedFileTypes.contains(ext) || (allowsOtherFileTypes && !ext.isEmpty) { return path }
        return path + "." + required
    }

    /// Asks the chooser, then answers `done` with NSModalResponseOK (1) or
    /// NSModalResponseCancel (0).
    func present(over window: NSWindow?, done: @escaping (Int) -> Void) {
        let types = dialogKind == .openFolders ? [] : allowedFileTypes
        FileDialogs.show(dialogKind, over: window ?? Windows.key, location: startLocation, types: types, multiple: allowsMultiple) { [self] paths in
            guard let paths, !paths.isEmpty else {
                done(0)
                return
            }
            chosen = dialogKind == .save ? [savePath(paths[0])] : paths.map(package(of:))
            if let first = chosen.first {
                let parts = first.split(separator: "/", omittingEmptySubsequences: false)
                directoryPath = parts.dropLast().joined(separator: "/")
                if dialogKind == .save { nameFieldStringValue = String(parts.last ?? "") }
            }
            done(1)
        }
    }

    /// Runs the event loop until the chooser answers.
    func runChooser(over window: NSWindow? = nil) -> Int {
        guard let app = App.shared else { return 0 }
        modalResponse = nil
        present(over: window) { [self] response in modalResponse = response }
        let mode = Constants.NSModalPanelRunLoopMode.objCArgument()
        let future = NSDate.distantFuture()
        while modalResponse == nil {
            ObjCRuntime.autoreleasepool {
                if let event = Send.nextEvent(app.objcObject, mask: UInt64.max, until: future.objcObject, mode: mode, dequeue: true) {
                    Send.void(app.objcObject, "sendEvent:", event)
                }
            }
        }
        return modalResponse ?? 0
    }

    // MARK: Running

    @ObjCMethod("runModal") func runModal() -> Int { runChooser() }

    @ObjCMethod("runModalForDirectory:file:")
    func runModal(forDirectory directory: String?, file: String?) -> Int {
        if let directory { directoryPath = directory }
        if let file { nameFieldStringValue = file }
        return runChooser()
    }

    @ObjCMethod("beginSheetModalForWindow:completionHandler:")
    func beginSheetModal(for window: NSWindow?, completionHandler: ObjCBlock?) {
        present(over: window) { response in
            if let completionHandler { Blocks.call(completionHandler, response) }
        }
    }

    @ObjCMethod("beginWithCompletionHandler:")
    func begin(completionHandler: ObjCBlock?) { beginSheetModal(for: nil, completionHandler: completionHandler) }

    /// The sheet of Mac OS X 10.5 and before: the delegate is sent
    /// -savePanelDidEnd:returnCode:contextInfo: (or the selector given).
    @ObjCMethod("beginSheetForDirectory:file:modalForWindow:modalDelegate:didEndSelector:contextInfo:")
    func beginSheet(forDirectory directory: String?, file: String?, modalFor window: NSWindow?, modalDelegate: NSObject?,
                    didEndSelector: ObjCSelector?, contextInfo: UnsafeMutableRawPointer?) {
        if let directory { directoryPath = directory }
        if let file { nameFieldStringValue = file }
        presentSheet(over: window, modalDelegate: modalDelegate, didEndSelector: didEndSelector, contextInfo: contextInfo)
    }

    func presentSheet(over window: NSWindow?, modalDelegate: NSObject?, didEndSelector: ObjCSelector?, contextInfo: UnsafeMutableRawPointer?) {
        let delegate = modalDelegate.map { ObjCRuntime.retain($0.objcObject) } ?? nil
        present(over: window) { [self] response in
            if let delegate, let didEndSelector {
                typealias F = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeMutableRawPointer, Int, UnsafeMutableRawPointer?) -> Void
                unsafeBitCast(ObjCRuntime.msgSend, to: F.self)(delegate, didEndSelector.pointer, objcObject, response, contextInfo)
            }
            ObjCRuntime.release(delegate)
        }
    }

    @ObjCMethod("ok:") func ok(_ sender: NSObject?) {}
    @ObjCMethod("cancel:") func cancel(_ sender: NSObject?) {}

    // MARK: What was chosen

    @ObjCMethod("URL") func url() -> NSObject? { chosen.first.flatMap { NSURL.make(fileURLWithPath: $0) } }
    @ObjCMethod("filename") func filename() -> String? { chosen.first }
    /// Every path chosen, which AppKit's save panels answer too (one, or
    /// none): Xcode 3 asks any panel for these before -filename.
    @ObjCMethod("filenames") func filenames() -> NSObject { NSMutableArray.of(chosen.map { NSObject(objCReturnValue: $0.objCReturnValue()) }) }
    @ObjCMethod("directory") func directory() -> String? { directoryPath ?? defaultDirectory }
    @ObjCMethod("setDirectory:") func setDirectory(_ path: String?) { directoryPath = path }
    @ObjCMethod("directoryURL") func panelDirectoryURL() -> NSObject? { directory().flatMap { NSURL.make(fileURLWithPath: $0) } }
    @ObjCMethod("setDirectoryURL:")
    func setDirectoryURL(_ url: NSObject?) { directoryPath = url.flatMap { Send.object($0.objcObject, "path") }.map { String(objCArgument: $0) } }

    // MARK: Settings

    @ObjCMethod("nameFieldStringValue") func panelNameFieldStringValue() -> String { nameFieldStringValue }
    @ObjCMethod("setNameFieldStringValue:") func setNameFieldStringValue(_ value: String?) { nameFieldStringValue = value ?? "" }
    @ObjCMethod("message") func panelMessage() -> String { message }
    @ObjCMethod("setMessage:") func setMessage(_ message: String?) { self.message = message ?? "" }
    @ObjCMethod("prompt") func panelPrompt() -> String { prompt }
    @ObjCMethod("setPrompt:") func setPrompt(_ prompt: String?) { self.prompt = prompt ?? "" }
    @ObjCMethod("setNameFieldLabel:") func setNameFieldLabel(_ label: String?) {}

    /// File types by extension (UTIs are kept as they are).
    @ObjCMethod("allowedFileTypes") func panelAllowedFileTypes() -> NSObject? {
        allowedFileTypes.isEmpty ? nil : NSMutableArray.of(allowedFileTypes.map { NSObject(objCReturnValue: $0.objCReturnValue()) })
    }
    @ObjCMethod("setAllowedFileTypes:")
    func setAllowedFileTypes(_ types: NSObject?) {
        allowedFileTypes = types?.as(NSArray.self)?.elements.map(\.stringValue) ?? []
    }
    @ObjCMethod("setAllowedContentTypes:") func setAllowedContentTypes(_ types: NSObject?) {}
    @ObjCMethod("requiredFileType") func requiredFileType() -> String? { allowedFileTypes.first }
    @ObjCMethod("setRequiredFileType:")
    func setRequiredFileType(_ type: String?) { allowedFileTypes = type.map { $0.isEmpty ? [] : [$0] } ?? [] }
    @ObjCMethod("allowsOtherFileTypes") func panelAllowsOtherFileTypes() -> Bool { allowsOtherFileTypes }
    @ObjCMethod("setAllowsOtherFileTypes:") func setAllowsOtherFileTypes(_ value: Bool) { allowsOtherFileTypes = value }
    @ObjCMethod("setCanCreateDirectories:") func setCanCreateDirectories(_ value: Bool) {}
    @ObjCMethod("setCanSelectHiddenExtension:") func setCanSelectHiddenExtension(_ value: Bool) {}
    @ObjCMethod("setShowsHiddenFiles:") func setShowsHiddenFiles(_ value: Bool) {}
    @ObjCMethod("setExtensionHidden:") func setExtensionHidden(_ value: Bool) {}
    @ObjCMethod("isExtensionHidden") func isExtensionHidden() -> Bool { false }
    @ObjCMethod("setTreatsFilePackagesAsDirectories:") func setTreatsFilePackagesAsDirectories(_ value: Bool) {}
    @ObjCMethod("setShowsTagField:") func setShowsTagField(_ value: Bool) {}
    @ObjCMethod("isExpanded") func isExpanded() -> Bool { true }
    @ObjCMethod("accessoryView") func panelAccessoryView() -> NSObject? { accessory }
    @ObjCMethod("setAccessoryView:") func setAccessoryView(_ view: NSObject?) { accessory = view }
    @ObjCMethod("validateVisibleColumns") func validateVisibleColumns() {}
}

@ObjCClass("NSOpenPanel")
open class NSOpenPanel: NSSavePanel {
    var canChooseFiles = true
    var canChooseDirectories = false
    var allowsMultipleSelection = false

    @ObjCClassMethod("openPanel")
    static func openPanel() -> NSOpenPanel { NSOpenPanel(contentRect: CGRect(x: 0, y: 0, width: 480, height: 320), styleMask: 3, backing: 2, defer: true) }

    /// Folders for a panel that chooses folders, or packages (folders the
    /// app treats as files, as Xcode's projects): the desktop's choosers
    /// choose one or the other, and a file chooser goes into a package
    /// rather than choosing it. Files otherwise.
    override var dialogKind: FileDialogs.Kind { (canChooseDirectories && !canChooseFiles) || choosesPackages ? .openFolders : .openFiles }

    /// Whether the panel is for packages: some of its types are, or, with
    /// any type allowed, the document controller's packages are.
    var choosesPackages: Bool {
        let packages = packageExtensions.union(Documents.declared.filter(\.isPackage).flatMap(\.extensions))
        guard !allowedFileTypes.isEmpty else { return !packageExtensions.isEmpty }
        return !packages.isDisjoint(with: allowedFileTypes)
    }
    override var allowsMultiple: Bool { allowsMultipleSelection }

    @ObjCMethod("URLs") func urls() -> NSObject { NSMutableArray.of(chosen.compactMap { NSURL.make(fileURLWithPath: $0) }) }
    @ObjCMethod("canChooseFiles") func panelCanChooseFiles() -> Bool { canChooseFiles }
    @ObjCMethod("setCanChooseFiles:") func setCanChooseFiles(_ value: Bool) { canChooseFiles = value }
    @ObjCMethod("canChooseDirectories") func panelCanChooseDirectories() -> Bool { canChooseDirectories }
    @ObjCMethod("setCanChooseDirectories:") func setCanChooseDirectories(_ value: Bool) { canChooseDirectories = value }
    @ObjCMethod("allowsMultipleSelection") func panelAllowsMultipleSelection() -> Bool { allowsMultipleSelection }
    @ObjCMethod("setAllowsMultipleSelection:") func setAllowsMultipleSelection(_ value: Bool) { allowsMultipleSelection = value }
    @ObjCMethod("setResolvesAliases:") func setResolvesAliases(_ value: Bool) {}

    func setTypes(_ types: NSObject?) {
        if let types { setAllowedFileTypes(types) }
    }

    @ObjCMethod("runModalForTypes:")
    func runModal(forTypes types: NSObject?) -> Int {
        setTypes(types)
        return runChooser()
    }

    @ObjCMethod("runModalForDirectory:file:types:")
    func runModal(forDirectory directory: String?, file: String?, types: NSObject?) -> Int {
        setTypes(types)
        return runModal(forDirectory: directory, file: file)
    }

    /// The sheet of Mac OS X 10.5 and before: the delegate is sent
    /// -openPanelDidEnd:returnCode:contextInfo: (or the selector given).
    @ObjCMethod("beginSheetForDirectory:file:types:modalForWindow:modalDelegate:didEndSelector:contextInfo:")
    func beginSheet(forDirectory directory: String?, file: String?, types: NSObject?, modalFor window: NSWindow?, modalDelegate: NSObject?,
                    didEndSelector: ObjCSelector?, contextInfo: UnsafeMutableRawPointer?) {
        setTypes(types)
        if let directory { directoryPath = directory }
        presentSheet(over: window, modalDelegate: modalDelegate, didEndSelector: didEndSelector, contextInfo: contextInfo)
    }

    @ObjCMethod("beginForDirectory:file:types:modelessDelegate:didEndSelector:contextInfo:")
    func begin(forDirectory directory: String?, file: String?, types: NSObject?, modelessDelegate: NSObject?, didEndSelector: ObjCSelector?,
               contextInfo: UnsafeMutableRawPointer?) {
        beginSheet(forDirectory: directory, file: file, types: types, modalFor: nil, modalDelegate: modelessDelegate,
                   didEndSelector: didEndSelector, contextInfo: contextInfo)
    }
}
