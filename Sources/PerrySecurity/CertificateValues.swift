import FoundationEssentials
import Glibc
import PerryObjCInterop

// SecCertificateCopyValues: a certificate's fields as Darwin's dictionary of
// them, keyed by OID, each a property: a dictionary of its type
// (kSecPropertyTypeString, Section, Data, Number or Array), its label (also
// as the localized label) and its value. The certificate is read from its
// DER here: its version, serial number, issuer and subject names, validity,
// public key and signature with their algorithms, the key usage, subject
// key identifier and basic constraints extensions, its common names and its
// SHA-256 and SHA-1 fingerprints, labelled as Darwin labels them in
// English. Other extensions are left out.

/// The OIDs that key SecCertificateCopyValues' dictionary, with Darwin's
/// values: the X.509 fields' are Intel's CDSA field OIDs.
@ObjCConstants
enum CertificateOIDs {
    static let kSecOIDX509V1Version = "2.16.840.1.113741.2.1.1.1.2"
    static let kSecOIDX509V1SerialNumber = "2.16.840.1.113741.2.1.1.1.3"
    static let kSecOIDX509V1IssuerName = "2.16.840.1.113741.2.1.1.1.5"
    static let kSecOIDX509V1ValidityNotBefore = "2.16.840.1.113741.2.1.1.1.6"
    static let kSecOIDX509V1ValidityNotAfter = "2.16.840.1.113741.2.1.1.1.7"
    static let kSecOIDX509V1SubjectName = "2.16.840.1.113741.2.1.1.1.8"
    static let kSecOIDX509V1SubjectPublicKeyAlgorithm = "2.16.840.1.113741.2.1.1.1.9"
    static let kSecOIDX509V1SubjectPublicKey = "2.16.840.1.113741.2.1.1.1.10"
    static let kSecOIDX509V1SignatureAlgorithm = "2.16.840.1.113741.2.1.3.2.1"
    static let kSecOIDCommonName = "2.5.4.3"
    static let kSecOIDCountryName = "2.5.4.6"
    static let kSecOIDLocalityName = "2.5.4.7"
    static let kSecOIDStateProvinceName = "2.5.4.8"
    static let kSecOIDOrganizationName = "2.5.4.10"
    static let kSecOIDOrganizationalUnitName = "2.5.4.11"
    static let kSecOIDEmailAddress = "1.2.840.113549.1.9.1"
    static let kSecOIDSubjectKeyIdentifier = "2.5.29.14"
    static let kSecOIDKeyUsage = "2.5.29.15"
    static let kSecOIDSubjectAltName = "2.5.29.17"
    static let kSecOIDBasicConstraints = "2.5.29.19"
    static let kSecOIDAuthorityKeyIdentifier = "2.5.29.35"
    static let kSecOIDExtendedKeyUsage = "2.5.29.37"
}

/// A property's keys, and the types beside those ItemKeys has.
@ObjCConstants
enum PropertyKeys {
    static let kSecPropertyKeyType = "type"
    static let kSecPropertyKeyLabel = "label"
    static let kSecPropertyKeyLocalizedLabel = "localized label"
    static let kSecPropertyKeyValue = "value"
    static let kSecPropertyTypeNumber = "number"
    static let kSecPropertyTypeArray = "array"
}

/// A certificate's fields, as SecCertificateCopyValues lists them.
enum CertificateValues {
    /// The signature's value, which has no constant of its own.
    static let signatureOID = "2.16.840.1.113741.2.1.3.2.2"

    static func property(_ label: String, _ type: String, _ value: NSObject) -> NSObject {
        NSMutableDictionary.of([(PropertyKeys.kSecPropertyKeyType, NSObject.string(type)),
                                (PropertyKeys.kSecPropertyKeyLabel, NSObject.string(label)),
                                (PropertyKeys.kSecPropertyKeyLocalizedLabel, NSObject.string(label)),
                                (PropertyKeys.kSecPropertyKeyValue, value)])
    }

    static func section(_ label: String, _ entries: [NSObject]) -> NSObject {
        property(label, ItemKeys.kSecPropertyTypeSection, NSMutableArray.of(entries))
    }

    static func string(_ label: String, _ value: String) -> NSObject {
        property(label, ItemKeys.kSecPropertyTypeString, NSObject.string(value))
    }

    static func data(_ label: String, _ value: [UInt8]) -> NSObject {
        property(label, ItemKeys.kSecPropertyTypeData, NSData.of(Data(value)))
    }

    /// A directory string's text: UTF-8, printable, IA5, numeric, T.61
    /// (as Latin-1), BMP (UTF-16) or universal (UTF-32) strings.
    static func text(_ element: BERElement) -> String? {
        let bytes = Array(element.content)
        switch element.tag {
        case 0x0C, 0x12, 0x13, 0x16, 0x1A: return String(decoding: bytes, as: UTF8.self)
        case 0x14: return String(bytes.map { Character(Unicode.Scalar($0)) })
        case 0x1E:
            let units = stride(from: 0, to: bytes.count - 1, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
            return String(decoding: units, as: UTF16.self)
        case 0x1C:
            let scalars = stride(from: 0, to: bytes.count - 3, by: 4).compactMap { index -> Unicode.Scalar? in
                Unicode.Scalar(UInt32(bytes[index]) << 24 | UInt32(bytes[index + 1]) << 16 | UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 3]))
            }
            return String(String.UnicodeScalarView(scalars))
        default: return nil
        }
    }

    /// A Name's attributes in order, each labelled by its type's OID.
    static func name(_ element: BERElement) -> [NSObject] {
        element.children.flatMap(\.children).compactMap { attribute -> NSObject? in
            let parts = attribute.children
            guard parts.count >= 2, let oid = parts[0].oid else { return nil }
            if let value = text(parts[1]) { return string(oid, value) }
            return data(oid, Array(parts[1].raw))
        }
    }

    /// The common names in a Name.
    static func commonNames(_ element: BERElement) -> [String] {
        element.children.flatMap(\.children).compactMap { attribute in
            let parts = attribute.children
            guard parts.count >= 2, parts[0].oid == CertificateOIDs.kSecOIDCommonName else { return nil }
            return text(parts[1])
        }
    }

    /// An AlgorithmIdentifier: its algorithm and parameters, "none" when
    /// absent or NULL.
    static func algorithm(_ label: String, _ element: BERElement) -> NSObject {
        let parts = element.children
        var entries = [string("Algorithm", parts.first?.oid ?? "")]
        if parts.count < 2 || parts[1].tag == 0x05 {
            entries.append(string("Parameters", "none"))
        } else if let oid = parts[1].oid {
            entries.append(string("Parameters", oid))
        } else {
            entries.append(data("Parameters", Array(parts[1].raw)))
        }
        return section(label, entries)
    }

    /// A BIT STRING's bytes, without its count of unused bits.
    static func bits(_ element: BERElement) -> [UInt8] { Array(element.content.dropFirst()) }

    /// Bytes as Darwin shows a serial number: "04 00 15 4B".
    static func hex(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789ABCDEF")
        return bytes.map { String([digits[Int($0 >> 4)], digits[Int($0 & 0xf)]]) }.joined(separator: " ")
    }

    static func critical(_ flag: Bool) -> NSObject { string("Critical", flag ? "Yes" : "No") }

    /// The extensions read here, by OID.
    static func extensions(_ element: BERElement) -> [(String, NSObject)] {
        guard let list = element.children.first else { return [] }
        var values: [(String, NSObject)] = []
        for extensionElement in list.children {
            let parts = extensionElement.children
            guard let oid = parts.first?.oid, let octets = parts.last, octets.tag == 0x04 else { continue }
            let isCritical = parts.count > 2 && parts[1].tag == 0x01 && parts[1].content.first.map { $0 != 0 } == true
            guard let inner = BERElement.read(octets.content) else { continue }
            switch oid {
            case CertificateOIDs.kSecOIDSubjectKeyIdentifier where inner.tag == 0x04:
                values.append((oid, section(oid, [critical(isCritical), data("Key Identifier", Array(inner.content))])))
            case CertificateOIDs.kSecOIDBasicConstraints where inner.tag == 0x30:
                let authority = inner.children.first { $0.tag == 0x01 }?.content.first.map { $0 != 0 } ?? false
                values.append((oid, section(oid, [critical(isCritical), string("Certificate Authority", authority ? "Yes" : "No")])))
            case CertificateOIDs.kSecOIDKeyUsage where inner.tag == 0x03:
                // Bit n of the BIT STRING is 1 << n, and criticality the top bit.
                var usage: UInt32 = isCritical ? 1 << 31 : 0
                for (index, byte) in bits(inner).prefix(2).enumerated() {
                    for bit in 0..<8 where byte & (0x80 >> bit) != 0 { usage |= 1 << (index * 8 + bit) }
                }
                values.append((oid, property("Key Usage", PropertyKeys.kSecPropertyTypeNumber,
                                             NSNumber.make(int64: Int64(Int32(bitPattern: usage))))))
            default:
                continue
            }
        }
        return values
    }

    /// Every field, by OID.
    static func all(_ state: CertificateState) -> [(String, NSObject)]? {
        let der = Array(state.der)
        guard let certificate = BERElement.read(der[...]), certificate.tag == 0x30 else { return nil }
        let outer = certificate.children
        guard outer.count >= 3, outer[0].tag == 0x30 else { return nil }
        var fields = outer[0].children
        var version = 1
        if let first = fields.first, first.tag == 0xA0 {
            version = Int(first.children.first?.content.last ?? 0) + 1
            fields.removeFirst()
        }
        guard fields.count >= 6 else { return nil }
        let (serial, issuer, subject, publicKey) = (fields[0], fields[2], fields[4], fields[5])
        var values: [(String, NSObject)] = [
            (CertificateOIDs.kSecOIDX509V1Version, string("Version", String(version))),
            (CertificateOIDs.kSecOIDX509V1SerialNumber, string("Serial Number", hex(Array(serial.content)))),
            (CertificateOIDs.kSecOIDX509V1IssuerName, section("Issuer Name", name(issuer))),
            (CertificateOIDs.kSecOIDX509V1ValidityNotBefore, property("Not Valid Before", PropertyKeys.kSecPropertyTypeNumber,
                NSNumber.make(double: state.certificate.notValidBefore.timeIntervalSinceReferenceDate))),
            (CertificateOIDs.kSecOIDX509V1ValidityNotAfter, property("Not Valid After", PropertyKeys.kSecPropertyTypeNumber,
                NSNumber.make(double: state.certificate.notValidAfter.timeIntervalSinceReferenceDate))),
            (CertificateOIDs.kSecOIDX509V1SubjectName, section("Subject Name", name(subject))),
        ]
        let keyParts = publicKey.children
        if keyParts.count >= 2 {
            values.append((CertificateOIDs.kSecOIDX509V1SubjectPublicKeyAlgorithm, algorithm("Public Key Algorithm", keyParts[0])))
            values.append((CertificateOIDs.kSecOIDX509V1SubjectPublicKey, data("Public Key Data", bits(keyParts[1]))))
        }
        values.append((CertificateOIDs.kSecOIDX509V1SignatureAlgorithm, algorithm("Signature Algorithm", outer[1])))
        values.append((signatureOID, data("Signature", bits(outer[2]))))
        if let extensions = fields.first(where: { $0.tag == 0xA3 }) { values += self.extensions(extensions) }
        let names = commonNames(subject)
        if !names.isEmpty {
            values.append((CertificateOIDs.kSecOIDCommonName,
                           property("CN", PropertyKeys.kSecPropertyTypeArray, NSMutableArray.of(names.map(NSObject.string)))))
        }
        var fingerprints: [NSObject] = []
        if let sha256 = try? HashKind.sha256.hash(state.der) { fingerprints.append(data("SHA-256", Array(sha256))) }
        if let sha1 = try? HashKind.sha1.hash(state.der) { fingerprints.append(data("SHA-1", Array(sha1))) }
        values.append(("Fingerprints", section("Fingerprints", fingerprints)))
        return values
    }
}

/// CFDictionaryRef SecCertificateCopyValues(SecCertificateRef, CFArrayRef
/// keys, CFErrorRef *): every field, or those whose OIDs `keys` lists.
@c(_SecCertificateCopyValues)
public func SecCertificateCopyValues(_ certificate: UnsafeMutableRawPointer?, _ keys: UnsafeMutableRawPointer?,
                                     _ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UnsafeMutableRawPointer? {
    guard let state = Certificates.state(certificate), var values = CertificateValues.all(state) else {
        Status.report(error, Status.param)
        return nil
    }
    if let keys, NSObject(keys).isArray {
        let wanted = Set(NSArray(keys).elements.filter(\.isString).map(\.stringValue))
        values = values.filter { wanted.contains($0.0) }
    }
    return ObjCRuntime.retain(NSMutableDictionary.of(values).objcObject)
}
