import PerryObjCInterop

// UTType and MobileCoreServices' UTType functions over the type database.
// Each UTType object stands for one identifier; the system types' constants
// are made at startup.

final class TypeState: @unchecked Sendable {
    let record: TypeRecord

    init(_ record: TypeRecord) {
        self.record = record
    }
}

/// UTType.
@ObjCClass("UTType")
public final class UTType: NSObject {
    static let states = StateTable<TypeState>()

    /// A new type (+0, autoreleased).
    static func object(_ record: TypeRecord) -> NSObject {
        let object = NSObject(objCOwned: objCClass.ownedInstance())
        states.set(object.objcObject, TypeState(record))
        _ = ObjCRuntime.autorelease(ObjCRuntime.retain(object.objcObject))
        return object
    }

    static func object(identifier: String) -> NSObject? { Database.record(identifier).map(object) }

    static func record(_ object: NSObject?) -> TypeRecord? { states[object?.objcObject]?.record }

    var record: TypeRecord { UTType.states[objcObject]?.record ?? TypeRecord(identifier: "", conformsTo: [], extensions: [], mimeTypes: []) }

    @ObjCMethod("dealloc")
    func dealloc() {
        UTType.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UTType.objCClass.pointer)
    }

    @ObjCClassMethod("typeWithIdentifier:")
    static func type(identifier: String) -> NSObject? { object(identifier: identifier) }

    @ObjCClassMethod("typeWithFilenameExtension:")
    static func type(filenameExtension: String) -> NSObject {
        object(Database.preferred(tag: filenameExtension, tagClass: TagClass.filenameExtension, conformingTo: nil))
    }

    @ObjCClassMethod("typeWithFilenameExtension:conformingToType:")
    static func type(filenameExtension: String, conformingTo supertype: NSObject?) -> NSObject {
        object(Database.preferred(tag: filenameExtension, tagClass: TagClass.filenameExtension,
                                  conformingTo: record(supertype)?.identifier))
    }

    @ObjCClassMethod("typeWithMIMEType:")
    static func type(mimeType: String) -> NSObject {
        object(Database.preferred(tag: mimeType, tagClass: TagClass.mimeType, conformingTo: nil))
    }

    @ObjCClassMethod("typeWithMIMEType:conformingToType:")
    static func type(mimeType: String, conformingTo supertype: NSObject?) -> NSObject {
        object(Database.preferred(tag: mimeType, tagClass: TagClass.mimeType, conformingTo: record(supertype)?.identifier))
    }

    @ObjCClassMethod("typeWithTag:tagClass:conformingToType:")
    static func type(tag: String, tagClass: String, conformingTo supertype: NSObject?) -> NSObject? {
        object(Database.preferred(tag: tag, tagClass: tagClass, conformingTo: record(supertype)?.identifier))
    }

    @ObjCClassMethod("typesWithTag:tagClass:conformingToType:")
    static func types(tag: String, tagClass: String, conformingTo supertype: NSObject?) -> NSObject {
        NSMutableArray.of(Database.types(tag: tag, tagClass: tagClass, conformingTo: record(supertype)?.identifier).map(object))
    }

    /// The app's declared type, or one standing for the identifier until
    /// the app declares it.
    @ObjCClassMethod("exportedTypeWithIdentifier:")
    static func exportedType(identifier: String) -> NSObject {
        object(identifier: identifier) ?? object(TypeRecord(identifier: identifier, conformsTo: ["public.data"], extensions: [], mimeTypes: []))
    }

    @ObjCClassMethod("exportedTypeWithIdentifier:conformingToType:")
    static func exportedType(identifier: String, conformingTo supertype: NSObject?) -> NSObject {
        object(identifier: identifier) ?? object(TypeRecord(identifier: identifier, conformsTo: [record(supertype)?.identifier ?? "public.data"],
                                                            extensions: [], mimeTypes: []))
    }

    @ObjCClassMethod("importedTypeWithIdentifier:")
    static func importedType(identifier: String) -> NSObject { exportedType(identifier: identifier) }

    @ObjCClassMethod("importedTypeWithIdentifier:conformingToType:")
    static func importedType(identifier: String, conformingTo supertype: NSObject?) -> NSObject {
        exportedType(identifier: identifier, conformingTo: supertype)
    }

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }

    @ObjCMethod("identifier") func identifier() -> String { record.identifier }
    @ObjCMethod("preferredFilenameExtension") func preferredFilenameExtension() -> String? { record.extensions.first }
    @ObjCMethod("preferredMIMEType") func preferredMIMEType() -> String? { record.mimeTypes.first }
    @ObjCMethod("localizedDescription") func localizedDescription() -> String? { record.description }
    @ObjCMethod("version") func version() -> NSObject? { nil }
    @ObjCMethod("referenceURL") func referenceURL() -> NSObject? { nil }
    @ObjCMethod("isDynamic") func isDynamic() -> Bool { record.dynamic }
    @ObjCMethod("isDeclared") func isDeclared() -> Bool { !record.dynamic && Database.isDeclared(record.identifier) }
    @ObjCMethod("isPublicType") func isPublicType() -> Bool { record.identifier.hasPrefix("public.") }

    @ObjCMethod("tags")
    func tags() -> NSObject {
        var entries: [(String, NSObject)] = []
        if !record.extensions.isEmpty { entries.append((TagClass.filenameExtension, NSMutableArray.of(record.extensions.map(NSObject.string)))) }
        if !record.mimeTypes.isEmpty { entries.append((TagClass.mimeType, NSMutableArray.of(record.mimeTypes.map(NSObject.string)))) }
        return NSMutableDictionary.of(entries)
    }

    /// Every type it conforms to, but itself.
    @ObjCMethod("supertypes")
    func supertypes() -> NSObject {
        NSMutableSet.of(Database.ancestors(record.identifier).dropFirst().compactMap(UTType.object(identifier:)))
    }

    @ObjCMethod("conformsToType:")
    func conforms(to other: NSObject?) -> Bool {
        guard let other = UTType.record(other) else { return false }
        return Database.conforms(record.identifier, to: other.identifier)
    }

    @ObjCMethod("isSubtypeOfType:")
    func isSubtype(of other: NSObject?) -> Bool {
        guard let other = UTType.record(other), other.identifier.lowercased() != record.identifier.lowercased() else { return false }
        return Database.conforms(record.identifier, to: other.identifier)
    }

    @ObjCMethod("isSupertypeOfType:")
    func isSupertype(of other: NSObject?) -> Bool {
        guard let other = UTType.record(other), other.identifier.lowercased() != record.identifier.lowercased() else { return false }
        return Database.conforms(other.identifier, to: record.identifier)
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: NSObject?) -> Bool { UTType.record(other)?.identifier.lowercased() == record.identifier.lowercased() }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: record.identifier.lowercased().hashValue) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }

    @ObjCMethod("description") func description() -> String { record.identifier }
    @ObjCMethod("debugDescription") func debugDescription() -> String { "<_UTCoreType \(objcObject)> \(record.identifier)" }
}

/// The system types' constants, made at startup.
private func typeConstant(_ identifier: String) -> UnsafeMutableRawPointer {
    let object = UTType.object(identifier: identifier)!
    return ObjCRuntime.retain(object.objcObject)!
}

/// UTType's tag classes, and the system types.
@ObjCConstants
enum TypeConstants {
    static let UTTagClassFilenameExtension = "public.filename-extension"
    static let UTTagClassMIMEType = "public.mime-type"
    nonisolated(unsafe) static let UTTypeItem = typeConstant("public.item")
    nonisolated(unsafe) static let UTTypeContent = typeConstant("public.content")
    nonisolated(unsafe) static let UTTypeCompositeContent = typeConstant("public.composite-content")
    nonisolated(unsafe) static let UTTypeDiskImage = typeConstant("com.apple.disk-image")
    nonisolated(unsafe) static let UTTypeData = typeConstant("public.data")
    nonisolated(unsafe) static let UTTypeDirectory = typeConstant("public.directory")
    nonisolated(unsafe) static let UTTypeSymbolicLink = typeConstant("public.symlink")
    nonisolated(unsafe) static let UTTypeAliasFile = typeConstant("com.apple.alias-file")
    nonisolated(unsafe) static let UTTypeURL = typeConstant("public.url")
    nonisolated(unsafe) static let UTTypeFileURL = typeConstant("public.file-url")
    nonisolated(unsafe) static let UTTypeText = typeConstant("public.text")
    nonisolated(unsafe) static let UTTypePlainText = typeConstant("public.plain-text")
    nonisolated(unsafe) static let UTTypeUTF8PlainText = typeConstant("public.utf8-plain-text")
    nonisolated(unsafe) static let UTTypeUTF16ExternalPlainText = typeConstant("public.utf16-external-plain-text")
    nonisolated(unsafe) static let UTTypeUTF16PlainText = typeConstant("public.utf16-plain-text")
    nonisolated(unsafe) static let UTTypeDelimitedText = typeConstant("public.delimited-values-text")
    nonisolated(unsafe) static let UTTypeCommaSeparatedText = typeConstant("public.comma-separated-values-text")
    nonisolated(unsafe) static let UTTypeTabSeparatedText = typeConstant("public.tab-separated-values-text")
    nonisolated(unsafe) static let UTTypeUTF8TabSeparatedText = typeConstant("public.utf8-tab-separated-values-text")
    nonisolated(unsafe) static let UTTypeRTF = typeConstant("public.rtf")
    nonisolated(unsafe) static let UTTypeHTML = typeConstant("public.html")
    nonisolated(unsafe) static let UTTypeXML = typeConstant("public.xml")
    nonisolated(unsafe) static let UTTypeYAML = typeConstant("public.yaml")
    nonisolated(unsafe) static let UTTypeSourceCode = typeConstant("public.source-code")
    nonisolated(unsafe) static let UTTypeAssemblyLanguageSource = typeConstant("public.assembly-source")
    nonisolated(unsafe) static let UTTypeCSource = typeConstant("public.c-source")
    nonisolated(unsafe) static let UTTypeObjectiveCSource = typeConstant("public.objective-c-source")
    nonisolated(unsafe) static let UTTypeSwiftSource = typeConstant("public.swift-source")
    nonisolated(unsafe) static let UTTypeCPlusPlusSource = typeConstant("public.c-plus-plus-source")
    nonisolated(unsafe) static let UTTypeCHeader = typeConstant("public.c-header")
    nonisolated(unsafe) static let UTTypeScript = typeConstant("public.script")
    nonisolated(unsafe) static let UTTypeJavaScript = typeConstant("com.netscape.javascript-source")
    nonisolated(unsafe) static let UTTypeShellScript = typeConstant("public.shell-script")
    nonisolated(unsafe) static let UTTypePythonScript = typeConstant("public.python-script")
    nonisolated(unsafe) static let UTTypeRubyScript = typeConstant("public.ruby-script")
    nonisolated(unsafe) static let UTTypePropertyList = typeConstant("com.apple.property-list")
    nonisolated(unsafe) static let UTTypeXMLPropertyList = typeConstant("com.apple.xml-property-list")
    nonisolated(unsafe) static let UTTypeBinaryPropertyList = typeConstant("com.apple.binary-property-list")
    nonisolated(unsafe) static let UTTypePDF = typeConstant("com.adobe.pdf")
    nonisolated(unsafe) static let UTTypeRTFD = typeConstant("com.apple.rtfd")
    nonisolated(unsafe) static let UTTypeFlatRTFD = typeConstant("com.apple.flat-rtfd")
    nonisolated(unsafe) static let UTTypeWebArchive = typeConstant("com.apple.webarchive")
    nonisolated(unsafe) static let UTTypeImage = typeConstant("public.image")
    nonisolated(unsafe) static let UTTypeJPEG = typeConstant("public.jpeg")
    nonisolated(unsafe) static let UTTypeTIFF = typeConstant("public.tiff")
    nonisolated(unsafe) static let UTTypeGIF = typeConstant("com.compuserve.gif")
    nonisolated(unsafe) static let UTTypePNG = typeConstant("public.png")
    nonisolated(unsafe) static let UTTypeICNS = typeConstant("com.apple.icns")
    nonisolated(unsafe) static let UTTypeBMP = typeConstant("com.microsoft.bmp")
    nonisolated(unsafe) static let UTTypeICO = typeConstant("com.microsoft.ico")
    nonisolated(unsafe) static let UTTypeRAWImage = typeConstant("public.camera-raw-image")
    nonisolated(unsafe) static let UTTypeSVG = typeConstant("public.svg-image")
    nonisolated(unsafe) static let UTTypeLivePhoto = typeConstant("com.apple.live-photo")
    nonisolated(unsafe) static let UTTypeHEIF = typeConstant("public.heif")
    nonisolated(unsafe) static let UTTypeHEIC = typeConstant("public.heic")
    nonisolated(unsafe) static let UTTypeWebP = typeConstant("org.webmproject.webp")
    nonisolated(unsafe) static let UTTypeThreeDContent = typeConstant("public.3d-content")
    nonisolated(unsafe) static let UTTypeUSDZ = typeConstant("com.pixar.universal-scene-description-mobile")
    nonisolated(unsafe) static let UTTypeRealityFile = typeConstant("com.apple.reality")
    nonisolated(unsafe) static let UTTypeAudiovisualContent = typeConstant("public.audiovisual-content")
    nonisolated(unsafe) static let UTTypeMovie = typeConstant("public.movie")
    nonisolated(unsafe) static let UTTypeVideo = typeConstant("public.video")
    nonisolated(unsafe) static let UTTypeAudio = typeConstant("public.audio")
    nonisolated(unsafe) static let UTTypeQuickTimeMovie = typeConstant("com.apple.quicktime-movie")
    nonisolated(unsafe) static let UTTypeMPEG = typeConstant("public.mpeg")
    nonisolated(unsafe) static let UTTypeMPEG2Video = typeConstant("public.mpeg-2-video")
    nonisolated(unsafe) static let UTTypeMPEG2TransportStream = typeConstant("public.mpeg-2-transport-stream")
    nonisolated(unsafe) static let UTTypeMP3 = typeConstant("public.mp3")
    nonisolated(unsafe) static let UTTypeMPEG4Movie = typeConstant("public.mpeg-4")
    nonisolated(unsafe) static let UTTypeMPEG4Audio = typeConstant("public.mpeg-4-audio")
    nonisolated(unsafe) static let UTTypeAppleProtectedMPEG4Audio = typeConstant("com.apple.protected-mpeg-4-audio")
    nonisolated(unsafe) static let UTTypeAVI = typeConstant("public.avi")
    nonisolated(unsafe) static let UTTypeAIFF = typeConstant("public.aiff-audio")
    nonisolated(unsafe) static let UTTypeWAV = typeConstant("com.microsoft.waveform-audio")
    nonisolated(unsafe) static let UTTypeMIDI = typeConstant("public.midi-audio")
    nonisolated(unsafe) static let UTTypeFolder = typeConstant("public.folder")
    nonisolated(unsafe) static let UTTypeVolume = typeConstant("public.volume")
    nonisolated(unsafe) static let UTTypePackage = typeConstant("com.apple.package")
    nonisolated(unsafe) static let UTTypeBundle = typeConstant("com.apple.bundle")
    nonisolated(unsafe) static let UTTypePluginBundle = typeConstant("com.apple.plugin")
    nonisolated(unsafe) static let UTTypeFramework = typeConstant("com.apple.framework")
    nonisolated(unsafe) static let UTTypeApplication = typeConstant("com.apple.application")
    nonisolated(unsafe) static let UTTypeApplicationBundle = typeConstant("com.apple.application-bundle")
    nonisolated(unsafe) static let UTTypeApplicationExtension = typeConstant("com.apple.application-and-system-extension")
    nonisolated(unsafe) static let UTTypeUnixExecutable = typeConstant("public.unix-executable")
    nonisolated(unsafe) static let UTTypeExecutable = typeConstant("public.executable")
    nonisolated(unsafe) static let UTTypeArchive = typeConstant("public.archive")
    nonisolated(unsafe) static let UTTypeGZIP = typeConstant("org.gnu.gnu-zip-archive")
    nonisolated(unsafe) static let UTTypeBZ2 = typeConstant("public.bzip2-archive")
    nonisolated(unsafe) static let UTTypeZIP = typeConstant("public.zip-archive")
    nonisolated(unsafe) static let UTTypeSpreadsheet = typeConstant("public.spreadsheet")
    nonisolated(unsafe) static let UTTypePresentation = typeConstant("public.presentation")
    nonisolated(unsafe) static let UTTypeDatabase = typeConstant("public.database")
    nonisolated(unsafe) static let UTTypeMessage = typeConstant("public.message")
    nonisolated(unsafe) static let UTTypeContact = typeConstant("public.contact")
    nonisolated(unsafe) static let UTTypeVCard = typeConstant("public.vcard")
    nonisolated(unsafe) static let UTTypeToDoItem = typeConstant("public.to-do-item")
    nonisolated(unsafe) static let UTTypeCalendarEvent = typeConstant("public.calendar-event")
    nonisolated(unsafe) static let UTTypeEmailMessage = typeConstant("public.email-message")
    nonisolated(unsafe) static let UTTypeInternetLocation = typeConstant("public.internet-location")
    nonisolated(unsafe) static let UTTypeLog = typeConstant("public.log")
    nonisolated(unsafe) static let UTTypeFont = typeConstant("public.font")
    nonisolated(unsafe) static let UTTypeBookmark = typeConstant("public.bookmark")
    nonisolated(unsafe) static let UTTypePKCS12 = typeConstant("com.rsa.pkcs-12")
    nonisolated(unsafe) static let UTTypeX509Certificate = typeConstant("public.x509-certificate")
    nonisolated(unsafe) static let UTTypeEPUB = typeConstant("org.idpf.epub-container")
    nonisolated(unsafe) static let UTTypeJSON = typeConstant("public.json")
    nonisolated(unsafe) static let UTTypeObjectCode = typeConstant("public.object-code")
}

/// MobileCoreServices' type identifiers and keys, as CFStrings.
@ObjCConstants
enum LegacyTypeConstants {
    static let kUTTagClassFilenameExtension = "public.filename-extension"
    static let kUTTagClassMIMEType = "public.mime-type"
    static let kUTTagClassNSPboardType = "com.apple.nspboard-type"
    static let kUTTagClassOSType = "com.apple.ostype"
    static let kUTExportedTypeDeclarationsKey = "UTExportedTypeDeclarations"
    static let kUTImportedTypeDeclarationsKey = "UTImportedTypeDeclarations"
    static let kUTTypeIdentifierKey = "UTTypeIdentifier"
    static let kUTTypeTagSpecificationKey = "UTTypeTagSpecification"
    static let kUTTypeConformsToKey = "UTTypeConformsTo"
    static let kUTTypeDescriptionKey = "UTTypeDescription"
    static let kUTTypeIconFileKey = "UTTypeIconFile"
    static let kUTTypeReferenceURLKey = "UTTypeReferenceURL"
    static let kUTTypeVersionKey = "UTTypeVersion"
    static let kUTTypeItem = "public.item"
    static let kUTTypeContent = "public.content"
    static let kUTTypeCompositeContent = "public.composite-content"
    static let kUTTypeMessage = "public.message"
    static let kUTTypeContact = "public.contact"
    static let kUTTypeArchive = "public.archive"
    static let kUTTypeDiskImage = "com.apple.disk-image"
    static let kUTTypeData = "public.data"
    static let kUTTypeDirectory = "public.directory"
    static let kUTTypeResolvable = "com.apple.resolvable"
    static let kUTTypeSymLink = "public.symlink"
    static let kUTTypeExecutable = "public.executable"
    static let kUTTypeMountPoint = "com.apple.mount-point"
    static let kUTTypeAliasFile = "com.apple.alias-file"
    static let kUTTypeAliasRecord = "com.apple.alias-record"
    static let kUTTypeURLBookmarkData = "com.apple.bookmark"
    static let kUTTypeURL = "public.url"
    static let kUTTypeFileURL = "public.file-url"
    static let kUTTypeText = "public.text"
    static let kUTTypePlainText = "public.plain-text"
    static let kUTTypeUTF8PlainText = "public.utf8-plain-text"
    static let kUTTypeUTF16ExternalPlainText = "public.utf16-external-plain-text"
    static let kUTTypeUTF16PlainText = "public.utf16-plain-text"
    static let kUTTypeDelimitedText = "public.delimited-values-text"
    static let kUTTypeCommaSeparatedText = "public.comma-separated-values-text"
    static let kUTTypeTabSeparatedText = "public.tab-separated-values-text"
    static let kUTTypeUTF8TabSeparatedText = "public.utf8-tab-separated-values-text"
    static let kUTTypeRTF = "public.rtf"
    static let kUTTypeHTML = "public.html"
    static let kUTTypeXML = "public.xml"
    static let kUTTypeSourceCode = "public.source-code"
    static let kUTTypeAssemblyLanguageSource = "public.assembly-source"
    static let kUTTypeCSource = "public.c-source"
    static let kUTTypeObjectiveCSource = "public.objective-c-source"
    static let kUTTypeSwiftSource = "public.swift-source"
    static let kUTTypeCPlusPlusSource = "public.c-plus-plus-source"
    static let kUTTypeObjectiveCPlusPlusSource = "public.objective-c-plus-plus-source"
    static let kUTTypeCHeader = "public.c-header"
    static let kUTTypeCPlusPlusHeader = "public.c-plus-plus-header"
    static let kUTTypeJavaSource = "com.sun.java-source"
    static let kUTTypeScript = "public.script"
    static let kUTTypeAppleScript = "com.apple.applescript.text"
    static let kUTTypeOSAScript = "com.apple.applescript.script"
    static let kUTTypeOSAScriptBundle = "com.apple.applescript.script-bundle"
    static let kUTTypeJavaScript = "com.netscape.javascript-source"
    static let kUTTypeShellScript = "public.shell-script"
    static let kUTTypePerlScript = "public.perl-script"
    static let kUTTypePythonScript = "public.python-script"
    static let kUTTypeRubyScript = "public.ruby-script"
    static let kUTTypePHPScript = "public.php-script"
    static let kUTTypeJSON = "public.json"
    static let kUTTypePropertyList = "com.apple.property-list"
    static let kUTTypeXMLPropertyList = "com.apple.xml-property-list"
    static let kUTTypeBinaryPropertyList = "com.apple.binary-property-list"
    static let kUTTypePDF = "com.adobe.pdf"
    static let kUTTypeRTFD = "com.apple.rtfd"
    static let kUTTypeFlatRTFD = "com.apple.flat-rtfd"
    static let kUTTypeTXNTextAndMultimediaData = "com.apple.txn.text-multimedia-data"
    static let kUTTypeWebArchive = "com.apple.webarchive"
    static let kUTTypeImage = "public.image"
    static let kUTTypeJPEG = "public.jpeg"
    static let kUTTypeJPEG2000 = "public.jpeg-2000"
    static let kUTTypeTIFF = "public.tiff"
    static let kUTTypePICT = "com.apple.pict"
    static let kUTTypeGIF = "com.compuserve.gif"
    static let kUTTypePNG = "public.png"
    static let kUTTypeQuickTimeImage = "com.apple.quicktime-image"
    static let kUTTypeAppleICNS = "com.apple.icns"
    static let kUTTypeBMP = "com.microsoft.bmp"
    static let kUTTypeICO = "com.microsoft.ico"
    static let kUTTypeRawImage = "public.camera-raw-image"
    static let kUTTypeScalableVectorGraphics = "public.svg-image"
    static let kUTTypeLivePhoto = "com.apple.live-photo"
    static let kUTTypeAudiovisualContent = "public.audiovisual-content"
    static let kUTTypeMovie = "public.movie"
    static let kUTTypeVideo = "public.video"
    static let kUTTypeAudio = "public.audio"
    static let kUTTypeQuickTimeMovie = "com.apple.quicktime-movie"
    static let kUTTypeMPEG = "public.mpeg"
    static let kUTTypeMPEG2Video = "public.mpeg-2-video"
    static let kUTTypeMPEG2TransportStream = "public.mpeg-2-transport-stream"
    static let kUTTypeMP3 = "public.mp3"
    static let kUTTypeMPEG4 = "public.mpeg-4"
    static let kUTTypeMPEG4Audio = "public.mpeg-4-audio"
    static let kUTTypeAppleProtectedMPEG4Audio = "com.apple.protected-mpeg-4-audio"
    static let kUTTypeAppleProtectedMPEG4Video = "com.apple.protected-mpeg-4-video"
    static let kUTTypeAVIMovie = "public.avi"
    static let kUTTypeAudioInterchangeFileFormat = "public.aiff-audio"
    static let kUTTypeWaveformAudio = "com.microsoft.waveform-audio"
    static let kUTTypeMIDIAudio = "public.midi-audio"
    static let kUTTypePlaylist = "public.playlist"
    static let kUTTypeM3UPlaylist = "public.m3u-playlist"
    static let kUTTypeFolder = "public.folder"
    static let kUTTypeVolume = "public.volume"
    static let kUTTypePackage = "com.apple.package"
    static let kUTTypeBundle = "com.apple.bundle"
    static let kUTTypePluginBundle = "com.apple.plugin"
    static let kUTTypeSpotlightImporter = "com.apple.metadata-importer"
    static let kUTTypeQuickLookGenerator = "com.apple.quicklook-generator"
    static let kUTTypeXPCService = "com.apple.xpc-service"
    static let kUTTypeFramework = "com.apple.framework"
    static let kUTTypeApplication = "com.apple.application"
    static let kUTTypeApplicationBundle = "com.apple.application-bundle"
    static let kUTTypeApplicationFile = "com.apple.application-file"
    static let kUTTypeUnixExecutable = "public.unix-executable"
    static let kUTTypeWindowsExecutable = "com.microsoft.windows-executable"
    static let kUTTypeJavaClass = "com.sun.java-class"
    static let kUTTypeJavaArchive = "com.sun.java-archive"
    static let kUTTypeSystemPreferencesPane = "com.apple.systempreference.prefpane"
    static let kUTTypeGNUZipArchive = "org.gnu.gnu-zip-archive"
    static let kUTTypeBzip2Archive = "public.bzip2-archive"
    static let kUTTypeZipArchive = "public.zip-archive"
    static let kUTTypeSpreadsheet = "public.spreadsheet"
    static let kUTTypePresentation = "public.presentation"
    static let kUTTypeDatabase = "public.database"
    static let kUTTypeVCard = "public.vcard"
    static let kUTTypeToDoItem = "public.to-do-item"
    static let kUTTypeCalendarEvent = "public.calendar-event"
    static let kUTTypeEmailMessage = "public.email-message"
    static let kUTTypeInternetLocation = "public.internet-location"
    static let kUTTypeInkText = "com.apple.ink.inktext"
    static let kUTTypeFont = "public.font"
    static let kUTTypeBookmark = "public.bookmark"
    static let kUTType3DContent = "public.3d-content"
    static let kUTTypePKCS12 = "com.rsa.pkcs-12"
    static let kUTTypeX509Certificate = "public.x509-certificate"
    static let kUTTypeElectronicPublication = "org.idpf.epub-container"
    static let kUTTypeLog = "public.log"
}

// MARK: - MobileCoreServices

private func text(_ string: UnsafeMutableRawPointer?) -> String? { string.map { String(objCArgument: $0) } }
private func owned(_ string: String?) -> UnsafeMutableRawPointer? { string.map { ObjCRuntime.retain($0.objCArgument())! } }

@c(_UTTypeCreatePreferredIdentifierForTag)
public func UTTypeCreatePreferredIdentifierForTag(_ tagClass: UnsafeMutableRawPointer?, _ tag: UnsafeMutableRawPointer?,
                                                  _ conformingTo: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let tagClass = text(tagClass), let tag = text(tag) else { return nil }
    return owned(Database.preferred(tag: tag, tagClass: tagClass, conformingTo: text(conformingTo)).identifier)
}

@c(_UTTypeCreateAllIdentifiersForTag)
public func UTTypeCreateAllIdentifiersForTag(_ tagClass: UnsafeMutableRawPointer?, _ tag: UnsafeMutableRawPointer?,
                                             _ conformingTo: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let tagClass = text(tagClass), let tag = text(tag) else { return nil }
    var identifiers = Database.types(tag: tag, tagClass: tagClass, conformingTo: text(conformingTo)).map(\.identifier)
    if identifiers.isEmpty {
        identifiers = [Database.preferred(tag: tag, tagClass: tagClass, conformingTo: text(conformingTo)).identifier]
    }
    return ObjCRuntime.retain(NSMutableArray.of(identifiers.map(NSObject.string)).objcObject)
}

@c(_UTTypeCopyPreferredTagWithClass)
public func UTTypeCopyPreferredTagWithClass(_ identifier: UnsafeMutableRawPointer?, _ tagClass: UnsafeMutableRawPointer?)
    -> UnsafeMutableRawPointer? {
    guard let identifier = text(identifier), let tagClass = text(tagClass), let record = Database.record(identifier) else { return nil }
    return owned(Database.tags(record, tagClass).first)
}

@c(_UTTypeCopyAllTagsWithClass)
public func UTTypeCopyAllTagsWithClass(_ identifier: UnsafeMutableRawPointer?, _ tagClass: UnsafeMutableRawPointer?)
    -> UnsafeMutableRawPointer? {
    guard let identifier = text(identifier), let tagClass = text(tagClass), let record = Database.record(identifier) else { return nil }
    let tags = Database.tags(record, tagClass)
    return tags.isEmpty ? nil : ObjCRuntime.retain(NSMutableArray.of(tags.map(NSObject.string)).objcObject)
}

@c(_UTTypeConformsTo)
public func UTTypeConformsTo(_ identifier: UnsafeMutableRawPointer?, _ other: UnsafeMutableRawPointer?) -> Bool {
    guard let identifier = text(identifier), let other = text(other) else { return false }
    return Database.conforms(identifier, to: other)
}

@c(_UTTypeEqual)
public func UTTypeEqual(_ identifier: UnsafeMutableRawPointer?, _ other: UnsafeMutableRawPointer?) -> Bool {
    guard let identifier = text(identifier), let other = text(other) else { return false }
    return identifier.lowercased() == other.lowercased()
}

@c(_UTTypeCopyDescription)
public func UTTypeCopyDescription(_ identifier: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    owned(text(identifier).flatMap(Database.record)?.description)
}

@c(_UTTypeIsDeclared)
public func UTTypeIsDeclared(_ identifier: UnsafeMutableRawPointer?) -> Bool { text(identifier).map(Database.isDeclared) ?? false }

@c(_UTTypeIsDynamic)
public func UTTypeIsDynamic(_ identifier: UnsafeMutableRawPointer?) -> Bool { text(identifier)?.hasPrefix("dyn.") ?? false }

@c(_UTTypeCopyDeclaration)
public func UTTypeCopyDeclaration(_ identifier: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let record = text(identifier).flatMap(Database.record), !record.dynamic else { return nil }
    var tags: [(String, NSObject)] = []
    if !record.extensions.isEmpty { tags.append((TagClass.filenameExtension, NSMutableArray.of(record.extensions.map(NSObject.string)))) }
    if !record.mimeTypes.isEmpty { tags.append((TagClass.mimeType, NSMutableArray.of(record.mimeTypes.map(NSObject.string)))) }
    var entries: [(String, NSObject)] = [("UTTypeIdentifier", NSObject.string(record.identifier)),
                                         ("UTTypeConformsTo", NSMutableArray.of(record.conformsTo.map(NSObject.string))),
                                         ("UTTypeTagSpecification", NSMutableDictionary.of(tags))]
    if let description = record.description { entries.append(("UTTypeDescription", NSObject.string(description))) }
    return ObjCRuntime.retain(NSMutableDictionary.of(entries).objcObject)
}

@c(_UTTypeCopyDeclaringBundleURL)
public func UTTypeCopyDeclaringBundleURL(_ identifier: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { nil }
