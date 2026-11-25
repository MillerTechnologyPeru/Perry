// AssetsLibrary's Swift API: group enumeration taking the group types as the
// 32-bit value Swift 1 programs passed, before ALAssetsGroupType was
// imported as a full-width integer.

extension ALAssetsLibrary {
    @available(iOS, introduced: 9.0, deprecated: 9.0, obsoleted: 26.0)
    @nonobjc
    public func enumerateGroupsWithTypes(_ types: UInt32, usingBlock enumerationBlock: ALAssetsLibraryGroupsEnumerationResultsBlock!,
                                         failureBlock: ALAssetsLibraryAccessFailureBlock!) {
        enumerateGroups(withTypes: ALAssetsGroupType(types), using: enumerationBlock, failureBlock: failureBlock)
    }
}
