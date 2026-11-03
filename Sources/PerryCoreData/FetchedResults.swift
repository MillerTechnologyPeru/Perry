import PerryObjCInterop

// NSFetchedResultsController: a fetch request's results, in sections by
// the section name key path, addressed by index path as a table view wants
// them; and NSExpressionDescription, a fetched expression's description.

final class FetchedResultsState: ObjectState {
    var request: NSFetchRequest?
    var context: NSObject?
    var sectionNameKeyPath: String?
    var cacheName: String?
    var delegate: UnsafeMutableRawPointer?
    var objects: [NSObject] = []
    var sections: [(name: String, objects: [NSObject])] = []
    var fetched = false
}

@ObjCClass("NSFetchedResultsController")
open class NSFetchedResultsController: NSObject {
    static let states = StateTable<FetchedResultsState>()
    var state: FetchedResultsState { NSFetchedResultsController.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        NSFetchedResultsController.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: NSFetchedResultsController.objCClass.pointer)
    }

    @ObjCMethod("initWithFetchRequest:managedObjectContext:sectionNameKeyPath:cacheName:")
    func initialize(fetchRequest: NSFetchRequest, managedObjectContext context: NSObject, sectionNameKeyPath: String?,
                    cacheName: String?) -> Self {
        (state.request, state.context, state.sectionNameKeyPath, state.cacheName) = (fetchRequest, context, sectionNameKeyPath, cacheName)
        return self
    }

    @ObjCClassMethod("deleteCacheWithName:") static func deleteCache(name: String?) {}

    @ObjCMethod("fetchRequest") func fetchRequest() -> NSFetchRequest? { state.request }
    @ObjCMethod("managedObjectContext") func managedObjectContext() -> NSObject? { state.context }
    @ObjCMethod("sectionNameKeyPath") func sectionNameKeyPath() -> String? { state.sectionNameKeyPath }
    @ObjCMethod("cacheName") func cacheName() -> String? { state.cacheName }
    @ObjCMethod("delegate") func delegate() -> NSObject? { state.delegate.map { NSObject($0) } }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: NSObject?) { state.delegate = delegate?.objcObject }

    /// Fetches, then groups consecutive objects with the same section name,
    /// as the request's sort puts them together.
    @ObjCMethod("performFetch:")
    func performFetch(_ error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        guard let request = state.request, let context = state.context?.as(NSManagedObjectContext.self),
              let results = context.execute(request, error: error)?.as(NSArray.self) else { return false }
        let objects = results.elements
        state.objects = objects
        state.fetched = true
        guard let keyPath = state.sectionNameKeyPath else {
            state.sections = [("", objects)]
            return true
        }
        var sections: [(name: String, objects: [NSObject])] = []
        for object in objects {
            let name = object.sendValue(forKeyPath: keyPath).map(sectionName) ?? ""
            if let last = sections.indices.last, sections[last].name == name {
                sections[last].objects.append(object)
            } else {
                sections.append((name, [object]))
            }
        }
        state.sections = sections
        return true
    }

    private func sectionName(_ value: NSObject) -> String {
        value.isKind(of: ObjCClass(named: "NSString")) ? value.stringValue : (value.describedByObject() ?? "")
    }

    @ObjCMethod("fetchedObjects")
    func fetchedObjects() -> NSObject? { state.fetched ? NSMutableArray.of(state.objects) : nil }

    @ObjCMethod("sections")
    func sections() -> NSObject? {
        guard state.fetched else { return nil }
        return NSMutableArray.of(state.sections.map { SectionInfo.make(name: $0.name, indexTitle: indexTitle($0.name), objects: $0.objects) })
    }

    @ObjCMethod("objectAtIndexPath:")
    func object(at indexPath: NSObject) -> NSObject? {
        let section = Int(indexPath.sendIndex(atPosition: 0)), row = Int(indexPath.sendIndex(atPosition: 1))
        guard state.sections.indices.contains(section), state.sections[section].objects.indices.contains(row) else {
            coreDataFatal("no object at index \(row) in section at index \(section)")
        }
        return state.sections[section].objects[row]
    }

    @ObjCMethod("indexPathForObject:")
    func indexPath(for object: NSObject) -> NSObject? {
        for (section, entry) in state.sections.enumerated() {
            if let row = entry.objects.firstIndex(where: { $0.objcObject == object.objcObject }) {
                var indexes = [UInt(section), UInt(row)]
                return ObjCClass(named: "NSIndexPath").object.sendIndexPath(withIndexes: &indexes, length: 2)
            }
        }
        return nil
    }

    /// A section's index title: its name's first letter, capitalized.
    private func indexTitle(_ name: String) -> String { name.first.map { String($0).uppercased() } ?? "" }

    @ObjCMethod("sectionIndexTitleForSectionName:")
    func sectionIndexTitle(forSectionName name: String) -> String? { indexTitle(name) }

    @ObjCMethod("sectionIndexTitles")
    func sectionIndexTitles() -> NSObject {
        var titles: [String] = []
        for section in state.sections where !titles.contains(indexTitle(section.name)) { titles.append(indexTitle(section.name)) }
        return NSMutableArray.of(titles.map { NSObject(objCReturnValue: $0.objCReturnValue()) })
    }

    @ObjCMethod("sectionForSectionIndexTitle:atIndex:")
    func section(forSectionIndexTitle title: String, at index: Int) -> Int {
        state.sections.firstIndex { indexTitle($0.name) == title } ?? index
    }
}

final class SectionInfoState: ObjectState {
    var name = ""
    var indexTitle = ""
    var objects: [NSObject] = []
}

/// A section of fetched results (NSFetchedResultsSectionInfo).
@ObjCClass("_NSDefaultSectionInfo")
open class SectionInfo: NSObject {
    static let states = StateTable<SectionInfoState>()
    var state: SectionInfoState { SectionInfo.states[objcObject] }

    static func make(name: String, indexTitle: String, objects: [NSObject]) -> SectionInfo {
        let info = objCClass.object.allocated().unsafeCast(to: SectionInfo.self)
        (info.state.name, info.state.indexTitle, info.state.objects) = (name, indexTitle, objects)
        return info
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        SectionInfo.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: SectionInfo.objCClass.pointer)
    }

    @ObjCMethod("name") func name() -> String { state.name }
    @ObjCMethod("indexTitle") func indexTitle() -> String? { state.indexTitle }
    @ObjCMethod("numberOfObjects") func numberOfObjects() -> UInt { UInt(state.objects.count) }
    @ObjCMethod("objects") func objects() -> NSObject { NSMutableArray.of(state.objects) }
}

/// A fetched expression's name, expression and result type.
@ObjCClass("NSExpressionDescription")
open class NSExpressionDescription: NSPropertyDescription {
    static let expressionStates = StateTable<ExpressionDescriptionState>()
    var expression: ExpressionDescriptionState { NSExpressionDescription.expressionStates[objcObject] }

    @ObjCMethod("dealloc")
    override func dealloc() {
        NSExpressionDescription.expressionStates.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("expression") func expressionObject() -> NSObject? { expression.expression }
    @ObjCMethod("setExpression:") func setExpression(_ value: NSObject?) { expression.expression = value }
    @ObjCMethod("expressionResultType") func expressionResultType() -> UInt { expression.resultType }
    @ObjCMethod("setExpressionResultType:") func setExpressionResultType(_ type: UInt) { expression.resultType = type }
}

final class ExpressionDescriptionState: ObjectState {
    var expression: NSObject?
    var resultType: UInt = 0
}

extension NSObject {
    @ObjCMethod("valueForKeyPath:") func sendValue(forKeyPath keyPath: String) -> NSObject?
    @ObjCMethod("indexAtPosition:") func sendIndex(atPosition position: UInt) -> UInt
    @ObjCMethod("indexPathWithIndexes:length:") func sendIndexPath(withIndexes indexes: UnsafePointer<UInt>, length: UInt) -> NSObject
}
