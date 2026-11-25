import FoundationEssentials
import Glibc
import PerryObjCInterop
import X509

// CMSDecoder: signed Cryptographic Message Syntax (PKCS #7) messages, which
// apps read their Mac App Store receipts with. A message is read as BER
// (receipts use indefinite lengths) for its content, certificates and
// signers. A signer's signature is checked with its certificate's key: over
// its signed attributes when it has them, whose message digest must be the
// content's, else over the content. Its certificate goes into a SecTrust with
// the message's others, which the caller evaluates or has evaluated here.
// Enveloped (encrypted) messages are not read.

extension TypeIDs {
    static let cmsDecoder: UInt = 0x5345_0007
}

// MARK: - BER

/// One BER element: its identifier octet, its contents (an indefinite-length
/// element's children, without the end-of-contents octets) and its whole
/// encoding.
struct BERElement {
    let tag: UInt8
    let content: ArraySlice<UInt8>
    let raw: ArraySlice<UInt8>

    var constructed: Bool { tag & 0x20 != 0 }

    /// The element at the start of `bytes`; nil when it is malformed or runs
    /// past them. Tags above 30 aren't used by CMS and aren't read.
    static func read(_ bytes: ArraySlice<UInt8>, depth: Int = 0) -> BERElement? {
        guard depth < 64 else { return nil }
        var at = bytes.startIndex
        guard at < bytes.endIndex else { return nil }
        let tag = bytes[at]
        at += 1
        guard tag & 0x1f != 0x1f, at < bytes.endIndex else { return nil }
        let first = bytes[at]
        at += 1
        if first == 0x80 {
            // Indefinite length: children until two zero octets.
            guard tag & 0x20 != 0 else { return nil }
            let start = at
            while true {
                guard bytes.endIndex - at >= 2 else { return nil }
                if bytes[at] == 0, bytes[at + 1] == 0 { break }
                guard let child = read(bytes[at...], depth: depth + 1) else { return nil }
                at = child.raw.endIndex
            }
            return BERElement(tag: tag, content: bytes[start..<at], raw: bytes[bytes.startIndex..<(at + 2)])
        }
        var length = 0
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            let count = Int(first & 0x7f)
            guard (1...4).contains(count), bytes.endIndex - at >= count else { return nil }
            for _ in 0..<count {
                length = length << 8 | Int(bytes[at])
                at += 1
            }
        }
        guard length <= bytes.endIndex - at else { return nil }
        return BERElement(tag: tag, content: bytes[at..<(at + length)], raw: bytes[bytes.startIndex..<(at + length)])
    }

    /// A constructed element's children, as far as they read.
    var children: [BERElement] {
        guard constructed else { return [] }
        var list: [BERElement] = []
        var rest = content
        while !rest.isEmpty, let child = BERElement.read(rest) {
            list.append(child)
            rest = rest[child.raw.endIndex...]
        }
        return list
    }

    /// An OCTET STRING's bytes, joined from its segments when it is
    /// constructed.
    var octets: [UInt8] { constructed ? children.flatMap(\.octets) : Array(content) }

    /// An OBJECT IDENTIFIER, dotted.
    var oid: String? {
        guard tag == 0x06, let first = content.first else { return nil }
        var arcs = [Int(first) / 40, Int(first) % 40]
        var value = 0
        for byte in content.dropFirst() {
            value = value << 7 | Int(byte & 0x7f)
            if byte & 0x80 == 0 {
                arcs.append(value)
                value = 0
            }
        }
        return arcs.map(String.init).joined(separator: ".")
    }
}

// MARK: - Signed messages

/// The parts of a SignedData message a decoder answers with.
final class SignedMessage {
    struct Signer {
        /// The issuer's Name (its whole encoding) and serial number, or the
        /// subject key identifier, that name the signer's certificate.
        var issuer: [UInt8]?
        var serial: [UInt8]?
        var keyIdentifier: [UInt8]?
        var digestAlgorithm = ""
        var signatureAlgorithm = ""
        var signature: [UInt8] = []
        /// The signed attributes' whole encoding ([0] IMPLICIT SET).
        var signedAttributes: [UInt8]?
        var messageDigest: [UInt8]?
        var signingTime: Date?
    }

    /// The encapsulated content type's OBJECT IDENTIFIER contents.
    var contentType: [UInt8] = []
    /// The encapsulated content; nil when it is detached.
    var content: [UInt8]?
    var certificates: [Data] = []
    var signers: [Signer] = []

    static let signedData = "1.2.840.113549.1.7.2"

    init?(_ bytes: [UInt8]) {
        guard let info = BERElement.read(bytes[...]), info.tag == 0x30 else { return nil }
        let parts = info.children
        guard parts.count >= 2, parts[0].oid == SignedMessage.signedData, parts[1].tag == 0xA0,
              let body = parts[1].children.first, body.tag == 0x30 else { return nil }
        let fields = body.children
        // version, digestAlgorithms, encapContentInfo, [0] certificates,
        // [1] crls, signerInfos.
        guard fields.count >= 4, fields[2].tag == 0x30, let signerInfos = fields.last, signerInfos.tag == 0x31 else { return nil }
        let encapsulated = fields[2].children
        guard let type = encapsulated.first, type.tag == 0x06 else { return nil }
        contentType = Array(type.content)
        if encapsulated.count > 1, encapsulated[1].tag == 0xA0, let octets = encapsulated[1].children.first {
            content = octets.octets
        }
        for field in fields[3..<(fields.count - 1)] where field.tag == 0xA0 {
            certificates += field.children.filter { $0.tag == 0x30 }.map { Data($0.raw) }
        }
        signers = signerInfos.children.compactMap(SignedMessage.signer)
    }

    private static func signer(_ info: BERElement) -> Signer? {
        let fields = info.children
        guard info.tag == 0x30, fields.count >= 5 else { return nil }
        var signer = Signer()
        switch fields[1].tag {
        case 0x30:
            let parts = fields[1].children
            guard parts.count == 2 else { return nil }
            signer.issuer = Array(parts[0].raw)
            signer.serial = Array(parts[1].content)
        case 0x80:
            signer.keyIdentifier = Array(fields[1].content)
        default:
            return nil
        }
        guard let digest = fields[2].children.first?.oid else { return nil }
        signer.digestAlgorithm = digest
        var index = 3
        if fields[index].tag == 0xA0 {
            signer.signedAttributes = Array(fields[index].raw)
            for attribute in fields[index].children {
                let parts = attribute.children
                guard parts.count == 2, let value = parts[1].children.first else { continue }
                switch parts[0].oid {
                case "1.2.840.113549.1.9.4": signer.messageDigest = value.octets
                case "1.2.840.113549.1.9.5": signer.signingTime = utcTime(value)
                default: break
                }
            }
            index += 1
        }
        guard fields.count > index + 1, let algorithm = fields[index].children.first?.oid, fields[index + 1].tag == 0x04 else { return nil }
        signer.signatureAlgorithm = algorithm
        signer.signature = fields[index + 1].octets
        return signer
    }

    /// A UTCTime or GeneralizedTime, in UTC.
    private static func utcTime(_ element: BERElement) -> Date? {
        let text = String(decoding: element.content, as: UTF8.self)
        let digits = Array(text.prefix { $0.isNumber })
        let long = element.tag == 0x18
        guard element.tag == 0x17 || long, digits.count >= (long ? 14 : 12) else { return nil }
        func number(_ start: Int, _ count: Int) -> Int { Int(String(digits[start..<(start + count)])) ?? 0 }
        var year = long ? number(0, 4) : number(0, 2)
        if !long { year += year < 50 ? 2000 : 1900 }
        let offset = long ? 4 : 2
        var parts = tm()
        parts.tm_year = Int32(year - 1900)
        parts.tm_mon = Int32(number(offset, 2) - 1)
        parts.tm_mday = Int32(number(offset + 2, 2))
        parts.tm_hour = Int32(number(offset + 4, 2))
        parts.tm_min = Int32(number(offset + 6, 2))
        parts.tm_sec = Int32(number(offset + 8, 2))
        return Date(timeIntervalSince1970: Double(timegm(&parts)))
    }

    /// The message's certificate that names the signer, by issuer and serial
    /// number or by subject key identifier.
    func certificate(of signer: Signer) -> Data? {
        certificates.first { der in
            if let keyIdentifier = signer.keyIdentifier {
                guard let state = CertificateState(der: der),
                      let identifier = try? state.certificate.extensions.subjectKeyIdentifier else { return false }
                return Array(identifier.keyIdentifier) == keyIdentifier
            }
            // TBSCertificate: [0] version, serialNumber, signature, issuer, …
            guard let certificate = BERElement.read(Array(der)[...]), let tbs = certificate.children.first else { return false }
            var fields = tbs.children[...]
            if fields.first?.tag == 0xA0 { fields = fields.dropFirst() }
            guard fields.count >= 3 else { return false }
            let serial = fields[fields.startIndex], issuer = fields[fields.startIndex + 2]
            return Array(serial.content) == signer.serial && Array(issuer.raw) == signer.issuer
        }
    }

    /// The digest an algorithm identifier names.
    static func hash(_ oid: String) -> HashKind? {
        switch oid {
        case "1.3.14.3.2.26", "1.2.840.113549.1.1.5", "1.2.840.10045.4.1": return .sha1
        case "2.16.840.1.101.3.4.2.4", "1.2.840.113549.1.1.14", "1.2.840.10045.4.3.1": return .sha224
        case "2.16.840.1.101.3.4.2.1", "1.2.840.113549.1.1.11", "1.2.840.10045.4.3.2": return .sha256
        case "2.16.840.1.101.3.4.2.2", "1.2.840.113549.1.1.12", "1.2.840.10045.4.3.3": return .sha384
        case "2.16.840.1.101.3.4.2.3", "1.2.840.113549.1.1.13", "1.2.840.10045.4.3.4": return .sha512
        default: return nil
        }
    }

    /// Whether the signer's signature is good with its certificate's key, over
    /// `content`.
    func verify(_ signer: Signer, content: [UInt8], certificate: CertificateState) -> Bool {
        guard let digest = SignedMessage.hash(signer.digestAlgorithm) else { return false }
        let name: String
        switch signer.signatureAlgorithm {
        case "1.2.840.113549.1.1.1", "1.2.840.113549.1.1.5", "1.2.840.113549.1.1.11", "1.2.840.113549.1.1.12",
             "1.2.840.113549.1.1.13", "1.2.840.113549.1.1.14":
            name = "algid:sign:RSA:message-PKCS1v15:"
        // ecdsa-with-SHA*, and id-ecPublicKey, which some signers give
        // instead.
        case "1.2.840.10045.4.1", "1.2.840.10045.4.3.1", "1.2.840.10045.4.3.2", "1.2.840.10045.4.3.3",
             "1.2.840.10045.4.3.4", "1.2.840.10045.2.1":
            name = "algid:sign:ECDSA:message-X962:"
        default:
            return false
        }
        let hashNames: [HashKind: String] = [.sha1: "SHA1", .sha224: "SHA224", .sha256: "SHA256", .sha384: "SHA384", .sha512: "SHA512"]
        guard let hashName = hashNames[digest], let algorithm = Algorithm(name + hashName), let key = certificate.key else { return false }
        var signed = content
        if let attributes = signer.signedAttributes {
            // The digest must be the content's, and the signature is over the
            // attributes, encoded as a SET.
            guard let messageDigest = signer.messageDigest, let actual = try? digest.hash(Data(content)),
                  Array(actual) == messageDigest else { return false }
            signed = [0x31] + attributes.dropFirst()
        }
        return (try? key.verify(algorithm, Data(signed), signature: Data(signer.signature))) ?? false
    }
}

// MARK: - Decoders

final class DecoderState {
    var bytes: [UInt8] = []
    var message: SignedMessage?
    var finalized = false
    var detachedContent: Data?
    /// The bytes given don't start a CMS message, which -UpdateMessage
    /// reported; the decoder then answers as for a message with nothing in
    /// it, as Security's does.
    var unknownFormat = false
}

@ObjCClass("CMSDecoder")
final class CMSDecoderObject: NSObject {
    static let states = StateTable<DecoderState>()

    @ObjCMethod("dealloc")
    func dealloc() {
        CMSDecoderObject.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: CMSDecoderObject.objCClass.pointer)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { TypeIDs.cmsDecoder }
}

private func decoder(_ object: UnsafeMutableRawPointer?) -> DecoderState? { CMSDecoderObject.states[object] }

/// The decoded message, once finalized.
private func message(_ object: UnsafeMutableRawPointer?) -> SignedMessage? {
    guard let state = decoder(object), state.finalized else { return nil }
    return state.message
}

/// What a decoder of bytes that weren't CMS answers with: no signers, no
/// certificates.
private func isEmpty(_ object: UnsafeMutableRawPointer?) -> Bool {
    guard let state = decoder(object) else { return false }
    return state.finalized && state.unknownFormat
}

/// errSecUnknownFormat, errSecSigningTimeMissing.
private let unknownFormat: Int32 = -25257
private let signingTimeMissing: Int32 = -67894

/// A trust failure as CMSDecoderCopySignerStatus reports it: the CSSM code
/// Security's trust policies give.
private func cssmResult(_ status: Int32) -> Int32 {
    switch status {
    case 0: return 0
    case Status.certificateExpired: return Int32(bitPattern: 0x8001_210A)       // CSSMERR_TP_CERT_EXPIRED
    case Status.certificateNotValidYet: return Int32(bitPattern: 0x8001_210B)   // CSSMERR_TP_CERT_NOT_VALID_YET
    default: return Int32(bitPattern: 0x8001_212A)                              // CSSMERR_TP_NOT_TRUSTED
    }
}

/// CMSSignerStatus.
private enum SignerStatus {
    static let unsigned: UInt32 = 0, valid: UInt32 = 1, needsDetachedContent: UInt32 = 2
    static let invalidSignature: UInt32 = 3, invalidCert: UInt32 = 4, invalidIndex: UInt32 = 5
}

@c(_CMSDecoderGetTypeID) public func CMSDecoderGetTypeID() -> UInt { TypeIDs.cmsDecoder }

@c(_CMSDecoderCreate)
public func CMSDecoderCreate(_ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out else { return Status.param }
    let object = CMSDecoderObject.objCClass.ownedInstance()
    CMSDecoderObject.states.set(object, DecoderState())
    out.pointee = object
    return Status.success
}

@c(_CMSDecoderUpdateMessage)
public func CMSDecoderUpdateMessage(_ object: UnsafeMutableRawPointer?, _ bytes: UnsafeRawPointer?, _ length: Int) -> Int32 {
    guard let state = decoder(object), !state.finalized, length >= 0 else { return Status.param }
    if let bytes, length > 0 { state.bytes += UnsafeRawBufferPointer(start: bytes, count: length) }
    // A message is a SEQUENCE.
    if let first = state.bytes.first, first != 0x30 {
        state.unknownFormat = true
        return unknownFormat
    }
    return Status.success
}

/// Reads the message; a message that isn't signed CMS is a decoding error.
@c(_CMSDecoderFinalizeMessage)
public func CMSDecoderFinalizeMessage(_ object: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = decoder(object), !state.finalized else { return Status.param }
    state.finalized = true
    if state.unknownFormat { return Status.success }
    state.message = SignedMessage(state.bytes)
    return state.message == nil ? Status.decode : Status.success
}

@c(_CMSDecoderSetDetachedContent)
public func CMSDecoderSetDetachedContent(_ object: UnsafeMutableRawPointer?, _ content: UnsafeMutableRawPointer?) -> Int32 {
    guard let state = decoder(object), let data = Keys.data(content) else { return Status.param }
    state.detachedContent = data
    return Status.success
}

@c(_CMSDecoderCopyDetachedContent)
public func CMSDecoderCopyDetachedContent(_ object: UnsafeMutableRawPointer?, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let state = decoder(object), let out else { return Status.param }
    out.pointee = state.detachedContent.flatMap(Keys.returned)
    return Status.success
}

@c(_CMSDecoderGetNumSigners)
public func CMSDecoderGetNumSigners(_ object: UnsafeMutableRawPointer?, _ out: UnsafeMutablePointer<Int>?) -> Int32 {
    guard let out else { return Status.param }
    if isEmpty(object) {
        out.pointee = 0
        return Status.success
    }
    guard let message = message(object) else { return Status.param }
    out.pointee = message.signers.count
    return Status.success
}

/// The encapsulated content; NULL when it is detached.
@c(_CMSDecoderCopyContent)
public func CMSDecoderCopyContent(_ object: UnsafeMutableRawPointer?, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let message = message(object), let out else { return Status.param }
    out.pointee = message.content.flatMap { Keys.returned(Data($0)) }
    return Status.success
}

@c(_CMSDecoderCopyEncapsulatedContentType)
public func CMSDecoderCopyEncapsulatedContentType(_ object: UnsafeMutableRawPointer?,
                                                  _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out else { return Status.param }
    out.pointee = nil
    if isEmpty(object) { return Status.success }
    guard let message = message(object) else { return Status.param }
    out.pointee = Keys.returned(Data(message.contentType))
    return Status.success
}

@c(_CMSDecoderIsContentEncrypted)
public func CMSDecoderIsContentEncrypted(_ object: UnsafeMutableRawPointer?, _ out: UnsafeMutablePointer<UInt8>?) -> Int32 {
    guard message(object) != nil || isEmpty(object), let out else { return Status.param }
    out.pointee = 0
    return Status.success
}

/// The message's certificates, as a CFArray of SecCertificates; NULL when
/// there are none.
@c(_CMSDecoderCopyAllCerts)
public func CMSDecoderCopyAllCerts(_ object: UnsafeMutableRawPointer?, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let out else { return Status.param }
    out.pointee = nil
    if isEmpty(object) { return Status.success }
    guard let message = message(object) else { return Status.param }
    let objects = message.certificates.compactMap(CertificateState.init(der:)).map(Certificates.object)
    defer { objects.forEach { ObjCRuntime.release($0) } }
    out.pointee = objects.isEmpty ? nil : ObjCRuntime.retain(NSMutableArray.of(objects.map(NSObject.init)).objcObject)
    return Status.success
}

@c(_CMSDecoderCopySignerCert)
public func CMSDecoderCopySignerCert(_ object: UnsafeMutableRawPointer?, _ index: Int,
                                     _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    guard let message = message(object), let out, message.signers.indices.contains(index) else { return Status.param }
    guard let der = message.certificate(of: message.signers[index]), let state = CertificateState(der: der) else {
        return Status.itemNotFound
    }
    out.pointee = Certificates.object(state)
    return Status.success
}

/// The signing time attribute, as a CFAbsoluteTime.
@c(_CMSDecoderCopySignerSigningTime)
public func CMSDecoderCopySignerSigningTime(_ object: UnsafeMutableRawPointer?, _ index: Int, _ out: UnsafeMutablePointer<Double>?) -> Int32 {
    guard let message = message(object), let out, message.signers.indices.contains(index) else { return Status.param }
    guard let time = message.signers[index].signingTime else { return signingTimeMissing }
    out.pointee = time.timeIntervalSinceReferenceDate
    return Status.success
}

/// A signer's status: its signature checked against the content, then, when
/// `evaluate` is set, its certificate's trust under the policies, which are
/// required. The SecTrust holds the signer's certificate and the message's
/// others, to evaluate when not evaluated here; when evaluated here, the
/// trust's failure is the certificate result, as a CSSM code. A signer
/// that isn't there is reported in the status, not as an error.
@c(_CMSDecoderCopySignerStatus)
public func CMSDecoderCopySignerStatus(_ object: UnsafeMutableRawPointer?, _ index: Int, _ policies: UnsafeMutableRawPointer?,
                                       _ evaluate: UInt8, _ statusOut: UnsafeMutablePointer<UInt32>?,
                                       _ trustOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                       _ resultOut: UnsafeMutablePointer<Int32>?) -> Int32 {
    guard let state = decoder(object), state.finalized, policies != nil else { return Status.param }
    trustOut?.pointee = nil
    resultOut?.pointee = 0
    guard let message = state.message, !message.signers.isEmpty else {
        statusOut?.pointee = SignerStatus.unsigned
        return state.message != nil || state.unknownFormat ? Status.success : Status.param
    }
    guard message.signers.indices.contains(index) else {
        statusOut?.pointee = SignerStatus.invalidIndex
        return Status.success
    }
    let signer = message.signers[index]
    guard let der = message.certificate(of: signer), let certificate = CertificateState(der: der) else {
        statusOut?.pointee = SignerStatus.invalidCert
        resultOut?.pointee = Status.itemNotFound
        return Status.success
    }
    guard let content = message.content ?? state.detachedContent.map({ [UInt8]($0) }) else {
        statusOut?.pointee = SignerStatus.needsDetachedContent
        return Status.success
    }
    var status = message.verify(signer, content: content, certificate: certificate) ? SignerStatus.valid : SignerStatus.invalidSignature

    // The signer first, then the message's other certificates.
    let signerObject = Certificates.object(certificate)
    let others = message.certificates.filter { $0 != der }.compactMap(CertificateState.init(der:)).map(Certificates.object)
    let list = [signerObject] + others
    defer { list.forEach { ObjCRuntime.release($0) } }
    let policyList = Policies.list(policies)
    let trust = TrustState(certificates: list, policies: policyList.isEmpty
        ? [PolicyState(oid: ItemKeys.kSecPolicyAppleX509Basic, ssl: false, server: false, hostname: nil)] : policyList)
    if evaluate != 0 {
        trust.evaluate()
        resultOut?.pointee = cssmResult(trust.status)
        if trust.status != 0, status == SignerStatus.valid { status = SignerStatus.invalidCert }
    }
    statusOut?.pointee = status
    if let trustOut {
        let trustObject = SecTrustObject.objCClass.ownedInstance()
        SecTrustObject.states.set(trustObject, trust)
        trustOut.pointee = trustObject
    }
    return Status.success
}
