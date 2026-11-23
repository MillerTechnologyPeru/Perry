// Contacts' Swift API: the user info of a CNError read as typed values, and
// CNContact as Identifiable with its descriptions.

import Foundation

@available(macOS 10.11, iOS 9.0, *)
extension CNError {
    /// The contacts, groups, containers, save or fetch requests the error is about.
    public var affectedRecords: [AnyObject]? {
        userInfo[CNErrorUserInfoAffectedRecordsKey] as? [AnyObject]
    }

    /// The identifiers of the records the error is about.
    public var affectedRecordIdentifiers: [String]? {
        userInfo[CNErrorUserInfoAffectedRecordIdentifiersKey] as? [String]
    }

    /// The key paths of the properties the error is about.
    public var keyPaths: [String]? {
        userInfo[CNErrorUserInfoKeyPathsKey] as? [String]
    }
}

@available(macOS 14, iOS 17, *)
extension CNContact: Identifiable {
    /// The contact's identity as a UUID: the UUID its identifier starts
    /// with (a store's identifiers are a UUID and a suffix after a colon),
    /// or for any other identifier one made from its bytes, the same for
    /// the same identifier.
    @objc dynamic open var id: UUID {
        let identifier = self.identifier
        let head = identifier.split(separator: ":", maxSplits: 1).first.map(String.init) ?? identifier
        if let uuid = UUID(uuidString: head) {
            return uuid
        }
        return contactUUID(hashing: identifier)
    }

    @available(macOS 14, iOS 17, *)
    public typealias ID = UUID
}

/// A name-based UUID (marked version 5) from two FNV-1a style hashes of a string's bytes.
private func contactUUID(hashing string: String) -> UUID {
    var low: UInt64 = 0xcbf2_9ce4_8422_2325
    var high: UInt64 = 0x8422_2325_cbf2_9ce4
    for byte in string.utf8 {
        low = (low ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        high = (high ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 ^ (high >> 29)
    }
    var bytes = [UInt8](repeating: 0, count: 16)
    for index in 0..<8 {
        bytes[index] = UInt8(truncatingIfNeeded: high >> (UInt64(index) * 8))
        bytes[index + 8] = UInt8(truncatingIfNeeded: low >> (UInt64(index) * 8))
    }
    bytes[6] = bytes[6] & 0x0f | 0x50
    bytes[8] = bytes[8] & 0x3f | 0x80
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                       bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
}

@available(macOS 10.11, iOS 9, *)
extension CNContact {
    /// The contact's class, address, identifier and the names fetched.
    @objc override dynamic public var description: String {
        "<\(type(of: self)): \(addressText) \(fieldsText)>"
    }

    /// The contact's class, address and identifier.
    @objc dynamic public var shortDebugDescription: String {
        "<\(type(of: self)): \(addressText) identifier=\(identifier)>"
    }

    /// The same as description.
    @objc override dynamic public var debugDescription: String {
        description
    }

    private var addressText: String {
        "0x" + String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16)
    }

    /// The identifier, then each name key that was fetched with its value.
    private var fieldsText: String {
        var fields = ["identifier=\(identifier)"]
        let names: [(String, (CNContact) -> String)] = [
            (CNContactGivenNameKey, { $0.givenName }),
            (CNContactFamilyNameKey, { $0.familyName }),
            (CNContactOrganizationNameKey, { $0.organizationName }),
        ]
        for (key, value) in names where isKeyAvailable(key) {
            fields.append("\(key)=\(value(self))")
        }
        return fields.joined(separator: ", ")
    }
}
