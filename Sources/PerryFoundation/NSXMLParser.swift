import CLibXML2
import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

// NSXMLParser over Linux's libxml2, through its SAX2 callbacks, as Darwin's
// is built over Apple's libxml2: the delegate sees libxml2's own events,
// split where libxml2 splits text. The document, DTD and entity callbacks
// are libxml2's own, so declared entities resolve; they are not substituted
// into text, and the first error stops the parse.

/// The parser's delegate.
@ObjCProtocol("NSXMLParserDelegate")
protocol NSXMLParserDelegate {
    @ObjCOptional("parserDidStartDocument:")
    func parserDidStartDocument(_ parser: NSXMLParser)

    @ObjCOptional("parserDidEndDocument:")
    func parserDidEndDocument(_ parser: NSXMLParser)

    @ObjCOptional("parser:didStartElement:namespaceURI:qualifiedName:attributes:")
    func parser(_ parser: NSXMLParser, didStartElement name: String, namespaceURI uri: String?,
                qualifiedName: String?, attributes: ObjCObject)

    @ObjCOptional("parser:didEndElement:namespaceURI:qualifiedName:")
    func parser(_ parser: NSXMLParser, didEndElement name: String, namespaceURI uri: String?, qualifiedName: String?)

    @ObjCOptional("parser:didStartMappingPrefix:toURI:")
    func parser(_ parser: NSXMLParser, didStartMappingPrefix prefix: String, toURI uri: String)

    @ObjCOptional("parser:didEndMappingPrefix:")
    func parser(_ parser: NSXMLParser, didEndMappingPrefix prefix: String)

    @ObjCOptional("parser:foundCharacters:")
    func parser(_ parser: NSXMLParser, foundCharacters string: String)

    @ObjCOptional("parser:foundIgnorableWhitespace:")
    func parser(_ parser: NSXMLParser, foundIgnorableWhitespace whitespace: String)

    @ObjCOptional("parser:foundProcessingInstructionWithTarget:data:")
    func parser(_ parser: NSXMLParser, foundProcessingInstructionWithTarget target: String, data: String?)

    @ObjCOptional("parser:foundComment:")
    func parser(_ parser: NSXMLParser, foundComment comment: String)

    @ObjCOptional("parser:foundCDATA:")
    func parser(_ parser: NSXMLParser, foundCDATA block: ObjCObject)

    @ObjCOptional("parser:parseErrorOccurred:")
    func parser(_ parser: NSXMLParser, parseErrorOccurred error: ObjCObject)
}

/// Error domains and codes.
@ObjCConstants
enum XMLParserConstants {
    static let NSXMLParserErrorDomain = "NSXMLParserErrorDomain"
}

/// NSXMLParserDelegateAbortedParseError.
private let delegateAbortedParseError = 512

/// A parser's input, settings and the parse in progress.
final class XMLParserState {
    let input: Data
    /// The delegate; not retained.
    var delegate: UnsafeMutableRawPointer?
    var processNamespaces = false
    var reportNamespacePrefixes = false
    var resolveExternalEntities = false
    /// The parser, while it parses; not retained.
    var parser: UnsafeMutableRawPointer?
    var context: xmlParserCtxtPtr?
    var error: id?
    var aborted = false
    var line = 0
    var column = 0
    /// The prefixes each open element declared, to unmap when it ends.
    var declaredPrefixes: [[String]] = []

    init(_ input: Data) {
        self.input = input
    }

    deinit {
        ObjC.release(error)
    }

    var wrapper: NSXMLParser? { parser.map { NSXMLParser(objcObject: $0, ownership: .retain) } }
    var delegateObject: AnyNSXMLParserDelegate? { delegate.map { AnyNSXMLParserDelegate($0) } }

    func setError(code: Int) {
        ObjC.release(error)
        error = ObjC.retain(Errors.autoreleased(domain: XMLParserConstants.NSXMLParserErrorDomainObject,
                                                code: code, description: nil))
    }

    /// Records where the parse is, for lineNumber and columnNumber.
    func notePosition() {
        guard let context else { return }
        line = Int(xmlSAX2GetLineNumber(context))
        column = Int(xmlSAX2GetColumnNumber(context))
    }

    /// Stops the parse after an error, reporting it unless it is the stop.
    func fail(code: Int) {
        guard let context, context.pointee.disableSAX == 0 else { return }
        notePosition()
        setError(code: code)
        if let parser = wrapper, let error {
            delegateObject?.parser(parser, parseErrorOccurred: ObjCObject(error))
        }
        xmlStopParser(context)
    }

    /// The state of the parse `context` belongs to. libxml2 parses an
    /// entity's text once, on its first use, in a nested context sharing
    /// the callbacks and the state; its events are not the document's, and
    /// Darwin's parser does not report them, so they get no state.
    static func from(_ context: UnsafeMutableRawPointer?) -> XMLParserState? {
        guard let context, let pointer = context.assumingMemoryBound(to: xmlParserCtxt.self).pointee._private else {
            return nil
        }
        let state = Unmanaged<XMLParserState>.fromOpaque(pointer).takeUnretainedValue()
        return UnsafeMutableRawPointer(state.context) == context ? state : nil
    }
}

private func string(_ bytes: UnsafePointer<xmlChar>?) -> String? {
    bytes.map { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) }
}

private func string(_ bytes: UnsafePointer<xmlChar>?, count: Int32) -> String {
    guard let bytes else { return "" }
    return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(count)), as: UTF8.self)
}

private func qualified(_ prefix: String?, _ local: String) -> String {
    prefix.map { "\($0):\(local)" } ?? local
}

/// libxml2's SAX2 callbacks. The context they receive is the parser
/// context, so libxml2's own xmlSAX2 functions can run; the state is its
/// _private. Those that call the delegate keep libxml2's registers around it.
private func makeHandler() -> xmlSAXHandler {
    var handler = xmlSAXHandler()
    handler.initialized = XML_SAX2_MAGIC
    // The document, its DTD and entities, as libxml2 keeps them.
    handler.internalSubset = xmlSAX2InternalSubset
    handler.externalSubset = xmlSAX2ExternalSubset
    handler.isStandalone = xmlSAX2IsStandalone
    handler.hasInternalSubset = xmlSAX2HasInternalSubset
    handler.hasExternalSubset = xmlSAX2HasExternalSubset
    handler.getEntity = xmlSAX2GetEntity
    handler.getParameterEntity = xmlSAX2GetParameterEntity
    handler.entityDecl = xmlSAX2EntityDecl
    handler.setDocumentLocator = xmlSAX2SetDocumentLocator
    handler.resolveEntity = { context, publicID, systemID in
        guard let state = XMLParserState.from(context), state.resolveExternalEntities else { return nil }
        return xmlSAX2ResolveEntity(context, publicID, systemID)
    }

    handler.startDocument = { context in
        keepingLinuxRegisters {
            xmlSAX2StartDocument(context)
            guard let state = XMLParserState.from(context), let parser = state.wrapper else { return }
            state.delegateObject?.parserDidStartDocument(parser)
        }
    }
    handler.endDocument = { context in
        keepingLinuxRegisters {
            guard let state = XMLParserState.from(context), let parser = state.wrapper else { return }
            state.delegateObject?.parserDidEndDocument(parser)
        }
    }
    handler.startElementNs = { context, localName, prefix, uri, namespaceCount, namespaces, attributeCount, _, attributes in
        keepingLinuxRegisters {
            guard let state = XMLParserState.from(context), let parser = state.wrapper,
                  let local = string(localName) else { return }
            state.notePosition()
            let prefix = string(prefix)
            var entries: [(key: id, value: id)] = []
            var declared: [(prefix: String, uri: String)] = []
            for index in 0..<Int(namespaceCount) {
                let declaredPrefix = string(namespaces?[2 * index])
                let declaredURI = string(namespaces?[2 * index + 1]) ?? ""
                declared.append((declaredPrefix ?? "", declaredURI))
                if !state.processNamespaces {
                    // Namespace declarations stay attributes: xmlns, xmlns:p.
                    let name = declaredPrefix.map { "xmlns:\($0)" } ?? "xmlns"
                    entries.append((Strings.autoreleased(name), Strings.autoreleased(declaredURI)))
                }
            }
            for index in 0..<Int(attributeCount) {
                guard let attribute = attributes?.advanced(by: 5 * index), let name = string(attribute[0]) else { continue }
                let value: String
                if let start = attribute[3], let end = attribute[4] {
                    value = string(start, count: Int32(end - start))
                } else {
                    value = ""
                }
                entries.append((Strings.autoreleased(qualified(string(attribute[1]), name)), Strings.autoreleased(value)))
            }
            if state.reportNamespacePrefixes {
                for (declaredPrefix, declaredURI) in declared {
                    state.delegateObject?.parser(parser, didStartMappingPrefix: declaredPrefix, toURI: declaredURI)
                }
            }
            state.declaredPrefixes.append(declared.map(\.prefix))
            let attributesObject = ObjCObject(Dictionaries.autoreleased(entries))
            if state.processNamespaces {
                state.delegateObject?.parser(parser, didStartElement: local, namespaceURI: string(uri),
                                             qualifiedName: qualified(prefix, local), attributes: attributesObject)
            } else {
                state.delegateObject?.parser(parser, didStartElement: qualified(prefix, local), namespaceURI: nil,
                                             qualifiedName: nil, attributes: attributesObject)
            }
        }
    }
    handler.endElementNs = { context, localName, prefix, uri in
        keepingLinuxRegisters {
            guard let state = XMLParserState.from(context), let parser = state.wrapper,
                  let local = string(localName) else { return }
            let prefix = string(prefix)
            if state.processNamespaces {
                state.delegateObject?.parser(parser, didEndElement: local, namespaceURI: string(uri),
                                             qualifiedName: qualified(prefix, local))
            } else {
                state.delegateObject?.parser(parser, didEndElement: qualified(prefix, local), namespaceURI: nil,
                                             qualifiedName: nil)
            }
            let declared = state.declaredPrefixes.popLast() ?? []
            if state.reportNamespacePrefixes {
                for declaredPrefix in declared {
                    state.delegateObject?.parser(parser, didEndMappingPrefix: declaredPrefix)
                }
            }
        }
    }
    handler.characters = { context, characters, length in
        keepingLinuxRegisters {
            guard let state = XMLParserState.from(context), let parser = state.wrapper else { return }
            state.delegateObject?.parser(parser, foundCharacters: string(characters, count: length))
        }
    }
    handler.ignorableWhitespace = { context, characters, length in
        keepingLinuxRegisters {
            guard let state = XMLParserState.from(context), let parser = state.wrapper else { return }
            state.delegateObject?.parser(parser, foundIgnorableWhitespace: string(characters, count: length))
        }
    }
    handler.cdataBlock = { context, bytes, length in
        keepingLinuxRegisters {
            guard let state = XMLParserState.from(context), let parser = state.wrapper else { return }
            let data = bytes.map { Data(UnsafeBufferPointer(start: $0, count: Int(length))) } ?? Data()
            guard let block = DataObjects.autoreleased(data) else { return }
            state.delegateObject?.parser(parser, foundCDATA: ObjCObject(block))
        }
    }
    handler.comment = { context, text in
        keepingLinuxRegisters {
            guard let state = XMLParserState.from(context), let parser = state.wrapper else { return }
            state.delegateObject?.parser(parser, foundComment: string(text) ?? "")
        }
    }
    handler.processingInstruction = { context, target, data in
        keepingLinuxRegisters {
            guard let state = XMLParserState.from(context), let parser = state.wrapper else { return }
            state.delegateObject?.parser(parser, foundProcessingInstructionWithTarget: string(target) ?? "",
                                         data: string(data))
        }
    }
    // Errors, but not warnings, stop the parse.
    handler.serror = { context, error in
        keepingLinuxRegisters {
            guard let error, error.pointee.level.rawValue >= XML_ERR_ERROR.rawValue,
                  let state = XMLParserState.from(error.pointee.ctxt ?? context) else { return }
            state.fail(code: Int(error.pointee.code))
        }
    }
    return handler
}

enum XMLParsers {
    nonisolated(unsafe) static var parserClass: Class!

    static func storage(_ object: id?) -> XMLParserState? {
        Storage.get(object, as: XMLParserState.self)
    }
}

/// NSXMLParser.
@ObjCClass("NSXMLParser")
public class NSXMLParser: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        XMLParsers.parserClass = cls.storage
    }

    private var state: XMLParserState? { XMLParsers.storage(objcObject) }

    @ObjCMethod("initWithData:")
    func initialize(data: ObjCObject?) -> Self? {
        guard let data else { return nil }
        Storage.set(objcObject, XMLParserState(DataObjects.data(data.objcObject)))
        return self
    }

    /// File URLs only, read whole.
    @ObjCMethod("initWithContentsOfURL:")
    func initialize(contentsOf url: ObjCObject?) -> Self? {
        guard let url = URLs.url(url?.objcObject), url.isFileURL,
              let contents = try? Data(contentsOf: url) else { return nil }
        Storage.set(objcObject, XMLParserState(contents))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: XMLParsers.parserClass)
    }

    @ObjCMethod("delegate") func delegate() -> UnsafeMutableRawPointer? { state?.delegate }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: UnsafeMutableRawPointer?) { state?.delegate = delegate }

    @ObjCMethod("shouldProcessNamespaces") func shouldProcessNamespaces() -> Bool { state?.processNamespaces ?? false }
    @ObjCMethod("setShouldProcessNamespaces:")
    func setShouldProcessNamespaces(_ value: Bool) { state?.processNamespaces = value }

    @ObjCMethod("shouldReportNamespacePrefixes")
    func shouldReportNamespacePrefixes() -> Bool { state?.reportNamespacePrefixes ?? false }
    @ObjCMethod("setShouldReportNamespacePrefixes:")
    func setShouldReportNamespacePrefixes(_ value: Bool) { state?.reportNamespacePrefixes = value }

    @ObjCMethod("shouldResolveExternalEntities")
    func shouldResolveExternalEntities() -> Bool { state?.resolveExternalEntities ?? false }
    @ObjCMethod("setShouldResolveExternalEntities:")
    func setShouldResolveExternalEntities(_ value: Bool) { state?.resolveExternalEntities = value }

    @ObjCMethod("parserError") func parserError() -> ObjCObject? { state?.error.map(ObjCObject.init) }

    /// Where the parse is: as of the latest element start or error.
    @ObjCMethod("lineNumber")
    func lineNumber() -> Int {
        guard let state else { return 0 }
        state.notePosition()
        return state.line
    }

    @ObjCMethod("columnNumber")
    func columnNumber() -> Int {
        guard let state else { return 0 }
        state.notePosition()
        return state.column
    }

    @ObjCMethod("publicID") func publicID() -> String? { nil }
    @ObjCMethod("systemID") func systemID() -> String? { nil }

    /// Parses the whole input, sending the delegate its events. NO after an
    /// error or abortParsing.
    @ObjCMethod("parse")
    func parse() -> Bool {
        guard let state, state.context == nil else { return false }
        var handler = makeHandler()
        guard let context = xmlCreatePushParserCtxt(&handler, nil, nil, 0, nil) else { return false }
        context.pointee._private = Unmanaged.passUnretained(state).toOpaque()
        state.context = context
        state.parser = objcObject
        state.aborted = false
        state.declaredPrefixes = []
        ObjC.release(state.error)
        state.error = nil
        defer {
            if let document = context.pointee.myDoc { xmlFreeDoc(document) }
            context.pointee.myDoc = nil
            xmlFreeParserCtxt(context)
            state.context = nil
            state.parser = nil
        }
        state.input.withUnsafeBytes { bytes in
            let chunk = bytes.bindMemory(to: CChar.self)
            _ = xmlParseChunk(context, chunk.baseAddress, Int32(chunk.count), 0)
        }
        _ = xmlParseChunk(context, nil, 0, 1)
        if state.aborted { return false }
        if context.pointee.wellFormed == 0 || context.pointee.errNo != 0 {
            if state.error == nil || context.pointee.errNo != 0 { state.setError(code: Int(context.pointee.errNo)) }
            return false
        }
        return true
    }

    /// Stops the parse, reporting NSXMLParserDelegateAbortedParseError.
    @ObjCMethod("abortParsing")
    func abortParsing() {
        guard let state, let context = state.context, !state.aborted else { return }
        state.aborted = true
        state.notePosition()
        state.setError(code: delegateAbortedParseError)
        if let error = state.error {
            state.delegateObject?.parser(self, parseErrorOccurred: ObjCObject(error))
        }
        xmlStopParser(context)
    }
}
