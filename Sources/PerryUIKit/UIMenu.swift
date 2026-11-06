import CPerryGeometry
import PerryObjCInterop

// Menus: actions, the menus holding them, and elements made later. A bar
// button item's menu is shown as an action sheet, one button an action, a
// check mark on those that are on, submenus' actions inline; a deferred
// element shows nothing here.

final class MenuElementState: ObjectState {
    var title = ""
    var subtitle: String?
    var image: UIImage?
    var identifier: String?
    var discoverabilityTitle: String?
    /// UIMenuElementAttributes: disabled 1, destructive 2, hidden 4.
    var attributes: UInt = 0
    /// UIMenuElementState: off 0, on 1, mixed 2.
    var elementState = 0
    var handler: ObjCBlock?
    /// UIMenuOptions: display inline 1, destructive 2, single selection 32.
    var options: UInt = 0
    var children: [NSObject] = []
}

@ObjCClass("UIMenuElement")
open class UIMenuElement: NSObject {
    static let states = StateTable<MenuElementState>()
    var element: MenuElementState { UIMenuElement.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIMenuElement.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIMenuElement.objCClass.pointer)
    }

    static func make(_ cls: ObjCClass, _ body: (MenuElementState) -> Void) -> UIMenuElement {
        let made = cls.object.allocated().unsafeCast(to: UIMenuElement.self)
        body(made.element)
        return made
    }

    @ObjCMethod("title") func title() -> String { element.title }
    @ObjCMethod("setTitle:") func setTitle(_ title: String) { element.title = title }
    @ObjCMethod("subtitle") func subtitle() -> String? { element.subtitle }
    @ObjCMethod("setSubtitle:") func setSubtitle(_ subtitle: String?) { element.subtitle = subtitle }
    @ObjCMethod("image") func image() -> UIImage? { element.image }
    @ObjCMethod("setImage:") func setImage(_ image: UIImage?) { element.image = image }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjCRuntime.retain(objcObject)! }
}

@ObjCClass("UIAction")
open class UIAction: UIMenuElement {
    @ObjCClassMethod("actionWithHandler:")
    static func action(_ cls: ObjCClass, handler: ObjCBlock?) -> UIMenuElement {
        make(cls) { $0.handler = handler }
    }

    @ObjCClassMethod("actionWithTitle:image:identifier:handler:")
    static func action(_ cls: ObjCClass, title: String, image: UIImage?, identifier: String?, handler: ObjCBlock?) -> UIMenuElement {
        make(cls) { ($0.title, $0.image, $0.identifier, $0.handler) = (title, image, identifier, handler) }
    }

    @ObjCMethod("identifier") func identifier() -> String { element.identifier ?? "" }
    @ObjCMethod("discoverabilityTitle") func discoverabilityTitle() -> String? { element.discoverabilityTitle }
    @ObjCMethod("setDiscoverabilityTitle:") func setDiscoverabilityTitle(_ title: String?) { element.discoverabilityTitle = title }
    @ObjCMethod("attributes") func attributes() -> UInt { element.attributes }
    @ObjCMethod("setAttributes:") func setAttributes(_ attributes: UInt) { element.attributes = attributes }
    @ObjCMethod("state") func state() -> Int { element.elementState }
    @ObjCMethod("setState:") func setState(_ state: Int) { element.elementState = state }
    @ObjCMethod("sender") func sender() -> NSObject? { nil }

    /// Runs the action's handler, given the action.
    func perform() { element.handler.map { Blocks.call($0, self) } }
}

@ObjCClass("UIMenu")
open class UIMenu: UIMenuElement {
    @ObjCClassMethod("menuWithChildren:")
    static func menu(_ cls: ObjCClass, children: NSArray) -> UIMenuElement { make(cls) { $0.children = children.elements } }

    @ObjCClassMethod("menuWithTitle:children:")
    static func menu(_ cls: ObjCClass, title: String, children: NSArray) -> UIMenuElement {
        make(cls) { ($0.title, $0.children) = (title, children.elements) }
    }

    @ObjCClassMethod("menuWithTitle:image:identifier:options:children:")
    static func menu(_ cls: ObjCClass, title: String, image: UIImage?, identifier: String?, options: UInt, children: NSArray) -> UIMenuElement {
        make(cls) { ($0.title, $0.image, $0.identifier, $0.options, $0.children) = (title, image, identifier, options, children.elements) }
    }

    @ObjCMethod("identifier") func identifier() -> String { element.identifier ?? "" }
    @ObjCMethod("options") func options() -> UInt { element.options }
    @ObjCMethod("children") func children() -> NSObject { NSMutableArray.of(element.children) }

    @ObjCMethod("menuByReplacingChildren:")
    func replacingChildren(_ children: NSArray) -> UIMenuElement {
        let mine = element
        return UIMenuElement.make(UIMenu.objCClass) { state in
            (state.title, state.image, state.identifier, state.options) = (mine.title, mine.image, mine.identifier, mine.options)
            state.children = children.elements
        }
    }

    /// The menu's actions in order, its submenus' among them, leaving out
    /// hidden ones and deferred elements.
    var actions: [UIAction] {
        element.children.flatMap { child -> [UIAction] in
            if let menu = child.as(UIMenu.self) { return menu.actions }
            guard let action = child.as(UIAction.self), action.element.attributes & 4 == 0 else { return [] }
            return [action]
        }
    }
}

/// An element whose items a provider gives later. Its provider is never
/// asked here, so it shows nothing.
@ObjCClass("UIDeferredMenuElement")
open class UIDeferredMenuElement: UIMenuElement {
    @ObjCClassMethod("elementWithProvider:")
    static func element(_ cls: ObjCClass, provider: ObjCBlock?) -> UIMenuElement { make(cls) { $0.handler = provider } }

    @ObjCClassMethod("elementWithUncachedProvider:")
    static func uncachedElement(_ cls: ObjCClass, provider: ObjCBlock?) -> UIMenuElement { make(cls) { $0.handler = provider } }
}

// MARK: - Showing menus

/// What a menu sheet's button does: performs an action, or opens a
/// submenu's own sheet.
enum MenuEntry {
    case action(UIAction)
    case submenu(UIMenu)
}

extension UIMenu {
    /// The menu's entries in order: its actions, its inline submenus'
    /// entries among them, and its other submenus as entries of their own,
    /// leaving out hidden actions and deferred elements.
    var entries: [MenuEntry] {
        element.children.flatMap { child -> [MenuEntry] in
            if let menu = child.as(UIMenu.self) {
                return menu.element.options & 1 != 0 || menu.element.title.isEmpty ? menu.entries : [.submenu(menu)]
            }
            guard let action = child.as(UIAction.self), action.element.attributes & 4 == 0 else { return [] }
            return [.action(action)]
        }
    }
}

/// An action sheet of a menu's entries. Choosing an action dismisses the
/// sheet, and any it was opened from, and performs it; choosing a submenu
/// opens its sheet over this one, whose Cancel goes back.
@ObjCClass("_PerryMenuSheetController")
open class PerryMenuSheetController: UIAlertController {
    static func sheet(for menu: UIMenu, root: UnsafeMutableRawPointer? = nil) -> PerryMenuSheetController {
        let title = menu.element.title
        let sheet = UIAlertController.alert(objCClass, title: title.isEmpty ? nil : title, message: nil, preferredStyle: 0)
            .unsafeCast(to: PerryMenuSheetController.self)
        let entries = menu.entries
        for entry in entries {
            let button: UIAlertAction
            switch entry {
            case .action(let action):
                let check = action.element.elementState == 1 ? "\u{2713} " : ""
                let style = action.element.attributes & 2 != 0 ? 2 : 0
                button = UIAlertAction.action(UIAlertAction.objCClass, title: check + action.element.title, style: style, handler: nil)
                    .unsafeCast(to: UIAlertAction.self)
                button.state.enabled = action.element.attributes & 1 == 0
            case .submenu(let submenu):
                button = UIAlertAction.action(UIAlertAction.objCClass, title: submenu.element.title + " \u{203A}", style: 0, handler: nil)
                    .unsafeCast(to: UIAlertAction.self)
            }
            sheet.addAction(button)
        }
        sheet.addAction(UIAlertAction.action(UIAlertAction.objCClass, title: "Cancel", style: 1, handler: nil).unsafeCast(to: UIAlertAction.self))
        let state = PerryMenuSheetController.menus[sheet.objcObject]
        state.entries = entries
        state.root = root
        return sheet
    }

    static let menus = StateTable<MenuSheetState>()

    @ObjCMethod("dealloc")
    override func dealloc() {
        PerryMenuSheetController.menus.remove(objcObject)
        super.dealloc()
    }

    @ObjCMethod("_perryChoose:")
    override func choose(_ sender: UIButton) {
        let index = sender.state.tag
        let state = PerryMenuSheetController.menus[objcObject]
        guard state.entries.indices.contains(index) else {
            // Cancel: this sheet closes, back to the one it opened from.
            dismiss(animated: true, completion: nil)
            return
        }
        switch state.entries[index] {
        case .action(let action):
            (state.root.map(UIViewController.wrap) ?? self).dismiss(animated: true, completion: nil)
            action.perform()
        case .submenu(let submenu):
            present(PerryMenuSheetController.sheet(for: submenu, root: state.root ?? objcObject), animated: true, completion: nil)
        }
    }
}

final class MenuSheetState: ObjectState {
    var entries: [MenuEntry] = []
    /// The sheet the first of these was opened as; not retained, as it
    /// outlives the sheets it opens.
    var root: UnsafeMutableRawPointer?
}
