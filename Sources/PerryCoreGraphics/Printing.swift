import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// PrintCore, the Printing Manager, which ApplicationServices re-exports and
// the loader maps here on Intel. There are no printers: a session's page
// formats and print settings answer as a fresh one would (US Letter, all
// pages, one-sided), and a document can't be begun, which sets the
// session's error to kPMNoDefaultPrinter, as AppKit's NSPrintOperation
// answers that nothing printed. NSPrintInfo's PMPrintSession, PMPageFormat
// and PMPrintSettings make these classes' objects with +new, so their state
// is made the first time a function is given one; a print info gives its
// page format its paper each time it hands it out.

private let noErr: Int32 = 0
/// kPMInvalidParameter.
private let paramErr: Int32 = -50
private let outOfScope: Int32 = -30871
private let noDefaultPrinter: Int32 = -30872
private let invalidPrintSettings: Int32 = -30875
private let invalidPageFormat: Int32 = -30876
private let invalidPrintSession: Int32 = -30879

/// The Printing Manager's CFTypeIDs.
let printSessionTypeID: UInt = 0x111, pageFormatTypeID: UInt = 0x112, printSettingsTypeID: UInt = 0x113

final class PrintSessionState: @unchecked Sendable {
    /// What PMSessionError reports: kPMNoDefaultPrinter once a document
    /// was asked for, or what PMSessionSetError set.
    var error: Int32 = 0
}

final class PageFormatState: @unchecked Sendable {
    /// The paper, in points, and the part of it a printer can print on, as
    /// NSPrintInfo's paperSize and imageablePageBounds give them (the
    /// origin at the paper's bottom left): Perry's print info's US Letter
    /// with a quarter inch all round, until one says otherwise.
    var paperWidth = 612.0, paperHeight = 792.0
    var imageableX = 18.0, imageableY = 18.0, imageableWidth = 576.0, imageableHeight = 756.0
}

final class PrintSettingsState: @unchecked Sendable {
    var firstPage: UInt32 = 1
    /// kPMPrintAllPages (-1).
    var lastPage = UInt32.max
    var jobName: String?
}

@ObjCClass("PMPrintSession")
public final class PMPrintSessionObject: NSObject {
    static let states = StateTable<PrintSessionState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        PMPrintSessionObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: PMPrintSessionObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { printSessionTypeID }
}

@ObjCClass("PMPageFormat")
public final class PMPageFormatObject: NSObject {
    static let states = StateTable<PageFormatState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        PMPageFormatObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: PMPageFormatObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { pageFormatTypeID }

    /// NSPrintInfo's paper, which AppKit's print info sends as it hands
    /// the page format out.
    @ObjCMethod("_perrySetPaperWidth:height:imageableX:imageableY:imageableWidth:imageableHeight:")
    func setPaper(width: Double, height: Double, imageableX: Double, imageableY: Double, imageableWidth: Double, imageableHeight: Double) {
        guard let state = Printing.pageFormat(objcObject), width > 0, height > 0, imageableWidth > 0, imageableHeight > 0 else { return }
        (state.paperWidth, state.paperHeight) = (width, height)
        (state.imageableX, state.imageableY, state.imageableWidth, state.imageableHeight) = (imageableX, imageableY, imageableWidth, imageableHeight)
    }
}

@ObjCClass("PMPrintSettings")
public final class PMPrintSettingsObject: NSObject {
    static let states = StateTable<PrintSettingsState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        PMPrintSettingsObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: PMPrintSettingsObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { printSettingsTypeID }
}

enum Printing {
    static func session(_ object: Ref?) -> PrintSessionState? {
        state(object, PMPrintSessionObject.objCClass, PMPrintSessionObject.states, PrintSessionState.init)
    }

    static func pageFormat(_ object: Ref?) -> PageFormatState? {
        state(object, PMPageFormatObject.objCClass, PMPageFormatObject.states, PageFormatState.init)
    }

    static func settings(_ object: Ref?) -> PrintSettingsState? {
        state(object, PMPrintSettingsObject.objCClass, PMPrintSettingsObject.states, PrintSettingsState.init)
    }

    /// The object's state, made the first time for one of the class that
    /// was made with +new rather than a Create function.
    private static func state<State: AnyObject>(_ object: Ref?, _ cls: ObjCClass, _ table: StateTable<State>, _ make: () -> State) -> State? {
        guard let object else { return nil }
        if let state = table[object] { return state }
        guard NSObject(objCArgument: object).isKind(of: cls) else { return nil }
        let state = make()
        table.set(object, state)
        return state
    }

    nonisolated(unsafe) static var warned = false

    /// Says once that nothing prints here.
    static func warnNoPrinter() {
        guard !warned else { return }
        warned = true
        let line = "perry: CoreGraphics: no printer here; nothing printed\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
    }
}

/// Writes a PMRect: top, left, bottom and right, doubles.
private func store(_ rect: UnsafeMutableRawPointer, top: Double, left: Double, bottom: Double, right: Double) {
    rect.storeBytes(of: top, as: Double.self)
    rect.storeBytes(of: left, toByteOffset: 8, as: Double.self)
    rect.storeBytes(of: bottom, toByteOffset: 16, as: Double.self)
    rect.storeBytes(of: right, toByteOffset: 24, as: Double.self)
}

// MARK: Objects

@c(_PMRetain)
public func PMRetain(_ object: Ref?) -> Int32 {
    _ = ObjCRuntime.retain(object)
    return noErr
}

@c(_PMRelease)
public func PMRelease(_ object: Ref?) -> Int32 {
    ObjCRuntime.release(object)
    return noErr
}

@c(_PMCreateSession)
public func PMCreateSession(_ session: UnsafeMutablePointer<Ref?>?) -> Int32 {
    guard let session else { return paramErr }
    session.pointee = makeObject(PMPrintSessionObject.objCClass, PMPrintSessionObject.states, PrintSessionState())
    return noErr
}

@c(_PMCreatePageFormat)
public func PMCreatePageFormat(_ format: UnsafeMutablePointer<Ref?>?) -> Int32 {
    guard let format else { return paramErr }
    format.pointee = makeObject(PMPageFormatObject.objCClass, PMPageFormatObject.states, PageFormatState())
    return noErr
}

@c(_PMCreatePrintSettings)
public func PMCreatePrintSettings(_ settings: UnsafeMutablePointer<Ref?>?) -> Int32 {
    guard let settings else { return paramErr }
    settings.pointee = makeObject(PMPrintSettingsObject.objCClass, PMPrintSettingsObject.states, PrintSettingsState())
    return noErr
}

// MARK: Sessions

@c(_PMSessionError) public func PMSessionError(_ session: Ref?) -> Int32 { Printing.session(session)?.error ?? invalidPrintSession }

@c(_PMSessionSetError)
public func PMSessionSetError(_ session: Ref?, _ error: Int32) -> Int32 {
    guard let state = Printing.session(session) else { return invalidPrintSession }
    state.error = error
    return noErr
}

/// Valid as they are: `changed` is false.
@c(_PMSessionValidatePageFormat)
public func PMSessionValidatePageFormat(_ session: Ref?, _ format: Ref?, _ changed: UnsafeMutablePointer<UInt8>?) -> Int32 {
    changed?.pointee = 0
    guard Printing.session(session) != nil else { return invalidPrintSession }
    return Printing.pageFormat(format) == nil ? invalidPageFormat : noErr
}

@c(_PMSessionValidatePrintSettings)
public func PMSessionValidatePrintSettings(_ session: Ref?, _ settings: Ref?, _ changed: UnsafeMutablePointer<UInt8>?) -> Int32 {
    changed?.pointee = 0
    guard Printing.session(session) != nil else { return invalidPrintSession }
    return Printing.settings(settings) == nil ? invalidPrintSettings : noErr
}

/// No printer to send it to: kPMNoDefaultPrinter, which the session keeps
/// as its error.
@c(_PMSessionBeginCGDocumentNoDialog)
public func PMSessionBeginCGDocumentNoDialog(_ session: Ref?, _ settings: Ref?, _ format: Ref?) -> Int32 {
    guard let state = Printing.session(session) else { return invalidPrintSession }
    guard Printing.settings(settings) != nil else { return invalidPrintSettings }
    guard Printing.pageFormat(format) != nil else { return invalidPageFormat }
    Printing.warnNoPrinter()
    state.error = noDefaultPrinter
    return noDefaultPrinter
}

/// No document is ever begun, so pages and its end are out of scope.
@c(_PMSessionEndDocumentNoDialog)
public func PMSessionEndDocumentNoDialog(_ session: Ref?) -> Int32 { Printing.session(session) == nil ? invalidPrintSession : outOfScope }

@c(_PMSessionBeginPageNoDialog)
public func PMSessionBeginPageNoDialog(_ session: Ref?, _ format: Ref?, _ pageFrame: UnsafeRawPointer?) -> Int32 {
    Printing.session(session) == nil ? invalidPrintSession : outOfScope
}

@c(_PMSessionEndPageNoDialog)
public func PMSessionEndPageNoDialog(_ session: Ref?) -> Int32 { Printing.session(session) == nil ? invalidPrintSession : outOfScope }

/// No page to draw into: NULL.
@c(_PMSessionGetCGGraphicsContext)
public func PMSessionGetCGGraphicsContext(_ session: Ref?, _ context: UnsafeMutablePointer<Ref?>?) -> Int32 {
    guard let context else { return paramErr }
    context.pointee = nil
    return Printing.session(session) == nil ? invalidPrintSession : outOfScope
}

// MARK: Page formats

/// The printable part of the page, its top left at the origin, y down.
@c(_PMGetAdjustedPageRect)
public func PMGetAdjustedPageRect(_ format: Ref?, _ pageRect: UnsafeMutableRawPointer?) -> Int32 {
    guard let pageRect else { return paramErr }
    guard let state = Printing.pageFormat(format) else { return invalidPageFormat }
    store(pageRect, top: 0, left: 0, bottom: state.imageableHeight, right: state.imageableWidth)
    return noErr
}

/// The paper, from the same origin: the margins above and to the left of
/// the printable part are negative.
@c(_PMGetAdjustedPaperRect)
public func PMGetAdjustedPaperRect(_ format: Ref?, _ paperRect: UnsafeMutableRawPointer?) -> Int32 {
    guard let paperRect else { return paramErr }
    guard let state = Printing.pageFormat(format) else { return invalidPageFormat }
    let top = -(state.paperHeight - state.imageableY - state.imageableHeight), left = -state.imageableX
    store(paperRect, top: top, left: left, bottom: top + state.paperHeight, right: left + state.paperWidth)
    return noErr
}

// MARK: Print settings

/// kPMDuplexNone (1).
@c(_PMGetDuplex)
public func PMGetDuplex(_ settings: Ref?, _ duplex: UnsafeMutablePointer<UInt32>?) -> Int32 {
    guard let duplex else { return paramErr }
    guard Printing.settings(settings) != nil else { return invalidPrintSettings }
    duplex.pointee = 1
    return noErr
}

@c(_PMGetFirstPage)
public func PMGetFirstPage(_ settings: Ref?, _ first: UnsafeMutablePointer<UInt32>?) -> Int32 {
    guard let first else { return paramErr }
    guard let state = Printing.settings(settings) else { return invalidPrintSettings }
    first.pointee = state.firstPage
    return noErr
}

@c(_PMGetLastPage)
public func PMGetLastPage(_ settings: Ref?, _ last: UnsafeMutablePointer<UInt32>?) -> Int32 {
    guard let last else { return paramErr }
    guard let state = Printing.settings(settings) else { return invalidPrintSettings }
    last.pointee = state.lastPage
    return noErr
}

@c(_PMPrintSettingsSetJobName)
public func PMPrintSettingsSetJobName(_ settings: Ref?, _ name: Ref?) -> Int32 {
    guard let name else { return paramErr }
    guard let state = Printing.settings(settings) else { return invalidPrintSettings }
    state.jobName = String(objCArgument: name)
    return noErr
}
#endif
