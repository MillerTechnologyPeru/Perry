import CPerryFoundation
import PerryObjCInterop

/// A service a File Provider extension offers for an item, which an app
/// reaches over XPC. No File Provider extension runs here, so
/// NSFileManager's -getFileProviderServicesForItemAtURL:completionHandler:
/// finds none, and a service made otherwise has no connection to give: the
/// handler gets NSXPCConnectionInvalid, as Darwin's does when the service
/// can't be reached.
final class FileProviderServiceStorage {
    let name: String?

    init(name: String?) { self.name = name }
}

@ObjCClass("NSFileProviderService")
public class NSFileProviderService: NSObject {
    nonisolated(unsafe) static var serviceClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        serviceClass = cls.storage
    }

    @ObjCMethod("name")
    func name() -> String? { Storage.get(objcObject, as: FileProviderServiceStorage.self)?.name }

    @ObjCMethod("getFileProviderConnectionWithCompletionHandler:")
    func getFileProviderConnection(completionHandler: UnsafeMutableRawPointer?) {
        guard let handler = completionHandler.flatMap({ ObjC.retainBlock($0) }).map({ ObjCObject(objCOwned: $0) }) else { return }
        let error = Errors.autoreleased(domain: Errors.cocoaDomain, code: 4099,
                                        description: "Couldn’t communicate with a helper application.")
            .map { ObjCObject($0) }
        ItemProviderQueue.background {
            Blocks.invoke(handler.id, as: (@convention(c) (id, id?, id?) -> Void).self)(handler.id, nil, error?.id)
        }
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSFileProviderService.serviceClass)
    }
}
