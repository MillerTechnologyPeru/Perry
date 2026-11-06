import CPerryGeometry
import Glibc
import PerryObjCInterop

// Storyboards: a compiled storyboard is a directory of nibs, one per view
// controller and one per controller's view, with an Info.plist naming the
// entry point and each controller's nib. A controller from a storyboard
// loads its view from its view nib when first asked, and performs the
// storyboard's segues: each a template naming the destination, made into
// a UIStoryboardSegue that the source prepares for and then performs.

final class StoryboardState: ObjectState {
    var path = ""
    var initialIdentifier: String?
    var nibNames: [String: String] = [:]
}

@ObjCClass("UIStoryboard")
open class UIStoryboard: NSObject {
    static let states = StateTable<StoryboardState>()
    var state: StoryboardState { UIStoryboard.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIStoryboard.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIStoryboard.objCClass.pointer)
    }

    /// The compiled storyboard `name` in the bundle, or in its Base
    /// localization.
    @ObjCClassMethod("storyboardWithName:bundle:")
    static func storyboard(name: String, bundle: NSObject?) -> UIStoryboard? {
        let root = (bundle?.as(NSBundle.self) ?? NSBundle.main()).bundlePath()
        for directory in [root, root + "/Base.lproj", root + "/en.lproj"] {
            let path = "\(directory)/\(name).storyboardc"
            guard let info = NSDictionary.contents(ofFile: path + "/Info.plist") else { continue }
            let storyboard = objCClass.object.allocated().unsafeCast(to: UIStoryboard.self)
            storyboard.state.path = path
            storyboard.state.initialIdentifier = info.object(forKey: "UIStoryboardDesignatedEntryPointIdentifier")?.stringValue
            storyboard.state.nibNames = Nibs.strings(info.object(forKey: "UIViewControllerIdentifiersToNibNames"))
                .mapValues(\.stringValue)
            return storyboard
        }
        uikitWarning("no storyboard named \(name)")
        return nil
    }

    @ObjCMethod("instantiateInitialViewController")
    func instantiateInitialViewController() -> UIViewController? {
        state.initialIdentifier.flatMap(instantiate(identifier:))
    }

    @ObjCMethod("instantiateViewControllerWithIdentifier:")
    func instantiateViewController(identifier: String) -> UIViewController {
        guard let controller = instantiate(identifier: identifier) else {
            uikitFatal("Storyboard (\(state.path)) doesn't contain a view controller with identifier '\(identifier)'")
        }
        return controller
    }

    @ObjCMethod("instantiateInitialViewControllerWithCreator:")
    func instantiateInitialViewController(creator: ObjCBlock?) -> UIViewController? { instantiateInitialViewController() }

    @ObjCMethod("instantiateViewControllerWithIdentifier:creator:")
    func instantiateViewController(identifier: String, creator: ObjCBlock?) -> UIViewController {
        instantiateViewController(identifier: identifier)
    }

    /// The controller in the identifier's nib, with the storyboard as its
    /// placeholder.
    private func instantiate(identifier: String) -> UIViewController? {
        let name = state.nibNames[identifier] ?? identifier
        guard let archive = Nibs.load(named: name, in: state.path) else { return nil }
        let objects = Nibs.instantiate(archive, owner: nil, external: ["UIStoryboardPlaceholder": self], bundlePath: state.path)
        guard let controller = objects.first(where: { $0.is(UIViewController.self) })?.unsafeCast(to: UIViewController.self) else {
            return nil
        }
        // Every controller the scene makes is the storyboard's, a navigation
        // controller's root as much as the navigation controller, so their
        // segues find their destinations.
        var pending = objects.filter { $0.is(UIViewController.self) }.map { $0.unsafeCast(to: UIViewController.self) }
        while let each = pending.popLast() {
            if each.state.storyboard == nil { each.state.storyboard = self }
            pending.append(contentsOf: each.state.children)
        }
        return controller
    }
}

extension NSDictionary {
    @ObjCClassMethod("dictionaryWithContentsOfFile:") static func contents(ofFile path: String) -> NSDictionary?
}

// MARK: - Segues

final class SegueState: ObjectState {
    var identifier: String?
    var source: UIViewController?
    var destination: UIViewController?
    var handler: ObjCBlock?
    /// Where an embed segue puts the destination's view.
    var containerView: UIView?
}

@ObjCClass("UIStoryboardSegue")
open class UIStoryboardSegue: NSObject {
    static let states = StateTable<SegueState>()
    var state: SegueState { UIStoryboardSegue.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIStoryboardSegue.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIStoryboardSegue.objCClass.pointer)
    }

    @ObjCMethod("initWithIdentifier:source:destination:")
    func initialize(identifier: String?, source: UIViewController, destination: UIViewController) -> Self {
        (state.identifier, state.source, state.destination) = (identifier, source, destination)
        return self
    }

    @ObjCClassMethod("segueWithIdentifier:source:destination:performHandler:")
    static func segue(_ cls: ObjCClass, identifier: String?, source: UIViewController, destination: UIViewController,
                      performHandler: ObjCBlock) -> NSObject {
        let segue = cls.object.allocated().sendInitializeSegue(identifier: identifier, source: source, destination: destination)
        segue.unsafeCast(to: UIStoryboardSegue.self).state.handler = performHandler
        return segue
    }

    @ObjCMethod("identifier") func identifier() -> String? { state.identifier }
    @ObjCMethod("sourceViewController") func sourceViewController() -> UIViewController? { state.source }
    @ObjCMethod("destinationViewController") func destinationViewController() -> UIViewController? { state.destination }
    @ObjCMethod("source") func source() -> UIViewController? { state.source }
    @ObjCMethod("destination") func destination() -> UIViewController? { state.destination }

    /// A plain segue does what its handler says; subclasses show the
    /// destination their way.
    @ObjCMethod("perform")
    func perform() { state.handler.map(Blocks.call) }
}

/// Shows the destination as the source's container would: pushed in a
/// navigation controller, presented otherwise.
@ObjCClass("UIStoryboardShowSegue")
open class UIStoryboardShowSegue: UIStoryboardSegue {
    @ObjCMethod("perform")
    override func perform() {
        guard let source = state.source, let destination = state.destination else { return }
        source.sendShow(destination, sender: nil)
    }
}

@ObjCClass("UIStoryboardShowDetailSegue")
open class UIStoryboardShowDetailSegue: UIStoryboardShowSegue {}

/// Makes the destination a child of the source, its view filling the
/// container view, as a storyboard's container views do.
@ObjCClass("UIStoryboardEmbedSegue")
open class UIStoryboardEmbedSegue: UIStoryboardSegue {
    @ObjCMethod("perform")
    override func perform() {
        guard let source = state.source, let destination = state.destination else { return }
        let container = state.containerView ?? source.loadedView
        source.addChild(destination)
        let view = destination.loadedView
        view.setFrame(container.bounds())
        view.setAutoresizingMask(18)
        container.addSubview(view)
        destination.sendDidMove(toParent: source)
    }
}

@ObjCClass("UIStoryboardPushSegue")
open class UIStoryboardPushSegue: UIStoryboardShowSegue {}

@ObjCClass("UIStoryboardPresentationSegue")
open class UIStoryboardPresentationSegue: UIStoryboardSegue {
    @ObjCMethod("perform")
    override func perform() {
        guard let source = state.source, let destination = state.destination else { return }
        source.present(destination, animated: true, completion: nil)
    }
}

@ObjCClass("UIStoryboardModalSegue")
open class UIStoryboardModalSegue: UIStoryboardPresentationSegue {}

@ObjCClass("UIStoryboardPopoverSegue")
open class UIStoryboardPopoverSegue: UIStoryboardPresentationSegue {}

extension NSObject {
    @ObjCMethod("initWithIdentifier:source:destination:")
    func sendInitializeSegue(identifier: String?, source: UIViewController, destination: UIViewController) -> NSObject

    @ObjCMethod("perform") func sendPerform()
    @ObjCMethod("showViewController:sender:") func sendShow(_ controller: UIViewController, sender: NSObject?)
    @ObjCMethod("prepareForSegue:sender:") func sendPrepare(for segue: NSObject, sender: NSObject?)
    @ObjCMethod("shouldPerformSegueWithIdentifier:sender:") func sendShouldPerformSegue(identifier: String, sender: NSObject?) -> Bool
}

final class SegueTemplateState: ObjectState {
    var identifier: String?
    var destinationIdentifier: String?
    var segueClassName: String?
    var actionName: String?
    var performOnViewLoad = false
    /// An embed segue's container view, connected by the source's view nib.
    var containerView: UIView?
    /// The controller the segue starts from; not retained.
    var viewController: UnsafeMutableRawPointer?
}

/// A segue as a storyboard describes it, made into a UIStoryboardSegue
/// when performed.
@ObjCClass("UIStoryboardSegueTemplate")
open class UIStoryboardSegueTemplate: NSObject {
    static let states = StateTable<SegueTemplateState>()
    var state: SegueTemplateState { UIStoryboardSegueTemplate.states[objcObject] }

    @ObjCMethod("dealloc")
    func dealloc() {
        UIStoryboardSegueTemplate.states.remove(objcObject)
        ObjCRuntime.superDealloc(objcObject, definedOn: UIStoryboardSegueTemplate.objCClass.pointer)
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: NSObject) -> Self {
        let decoded = Coder(coder: coder)
        state.identifier = decoded.string("UIIdentifier")
        state.destinationIdentifier = decoded.string("UIDestinationViewControllerIdentifier")
        state.segueClassName = decoded.string("UISegueClassName")
        state.actionName = decoded.string("UIActionName")
        state.performOnViewLoad = decoded.bool("UIPerformOnViewLoad")
        return self
    }

    @ObjCMethod("identifier") func identifier() -> String? { state.identifier }
    @ObjCMethod("viewController") func viewController() -> UIViewController? { state.viewController.map(UIViewController.wrap) }
    @ObjCMethod("setViewController:") func setViewController(_ controller: UIViewController?) { state.viewController = controller?.objcObject }

    /// The segue's class when the storyboard names none.
    var defaultSegueClass: ObjCClass {
        if self.is(UIStoryboardPresentationSegueTemplate.self) { return UIStoryboardPresentationSegue.objCClass }
        if self.is(UIStoryboardShowSegueTemplate.self) { return UIStoryboardShowSegue.objCClass }
        if self.is(UIStoryboardEmbedSegueTemplate.self) { return UIStoryboardEmbedSegue.objCClass }
        return UIStoryboardSegue.objCClass
    }

    /// Performed from a control or bar item: the controller performs it.
    @ObjCMethod("perform:")
    func perform(_ sender: NSObject?) {
        guard let controller = viewController(), let identifier = state.identifier else { return }
        controller.sendPerformSegue(identifier: identifier, sender: sender)
    }

    /// The segue to the destination, made from the storyboard.
    func segue(from source: UIViewController) -> UIStoryboardSegue? {
        guard let destinationIdentifier = state.destinationIdentifier, let storyboard = source.state.storyboard else { return nil }
        let destination = storyboard.instantiateViewController(identifier: destinationIdentifier)
        let cls = state.segueClassName.flatMap(Classes.named) ?? defaultSegueClass
        return cls.object.allocated().sendInitializeSegue(identifier: state.identifier, source: source, destination: destination)
            .unsafeCast(to: UIStoryboardSegue.self)
    }
}

@ObjCClass("UIStoryboardShowSegueTemplate")
open class UIStoryboardShowSegueTemplate: UIStoryboardSegueTemplate {}

@ObjCClass("UIStoryboardShowDetailSegueTemplate")
open class UIStoryboardShowDetailSegueTemplate: UIStoryboardShowSegueTemplate {}

@ObjCClass("UIStoryboardPushSegueTemplate")
open class UIStoryboardPushSegueTemplate: UIStoryboardShowSegueTemplate {}

/// A container view's segue, performed as the source's view loads.
@ObjCClass("UIStoryboardEmbedSegueTemplate")
open class UIStoryboardEmbedSegueTemplate: UIStoryboardSegueTemplate {
    @ObjCMethod("containerView") func containerView() -> UIView? { state.containerView }
    @ObjCMethod("setContainerView:") func setContainerView(_ view: UIView?) { state.containerView = view }
}

@ObjCClass("UIStoryboardPresentationSegueTemplate")
open class UIStoryboardPresentationSegueTemplate: UIStoryboardSegueTemplate {}

@ObjCClass("UIStoryboardModalSegueTemplate")
open class UIStoryboardModalSegueTemplate: UIStoryboardPresentationSegueTemplate {}

@ObjCClass("UIStoryboardPopoverSegueTemplate")
open class UIStoryboardPopoverSegueTemplate: UIStoryboardPresentationSegueTemplate {}

extension NSObject {
    @ObjCMethod("performSegueWithIdentifier:sender:") func sendPerformSegue(identifier: String, sender: NSObject?)
}

// MARK: - View controllers from storyboards

@ObjCCategory("UIStoryboardAdditions")
extension UIViewController {
    @ObjCMethod("storyboard") func storyboardObject() -> UIStoryboard? { state.storyboard }
    @ObjCMethod("setStoryboard:") func setStoryboardObject(_ storyboard: UIStoryboard?) { state.storyboard = storyboard }

    @ObjCMethod("performSegueWithIdentifier:sender:")
    func performSegue(identifier: String, sender: NSObject?) {
        guard let template = state.segueTemplates.first(where: { $0.state.identifier == identifier }) else {
            uikitFatal("Receiver (\(objcObject)) has no segue with identifier '\(identifier)'")
        }
        guard let segue = template.segue(from: self) else { return }
        sendPrepare(for: segue, sender: sender)
        segue.sendPerform()
    }

    @ObjCMethod("shouldPerformSegueWithIdentifier:sender:")
    func shouldPerformSegue(identifier: String, sender: NSObject?) -> Bool { true }

    /// Embeds container views' controllers once the view has loaded,
    /// before -viewDidLoad, as UIKit does: -prepareForSegue:sender: first.
    func performSeguesOnViewLoad() {
        for template in state.segueTemplates where template.state.performOnViewLoad {
            guard let segue = template.segue(from: self) else { continue }
            segue.state.containerView = template.state.containerView
            sendPrepare(for: segue, sender: nil)
            segue.sendPerform()
        }
    }

    @ObjCMethod("prepareForSegue:sender:")
    func prepare(for segue: NSObject, sender: NSObject?) {}

    @ObjCMethod("canPerformUnwindSegueAction:fromViewController:withSender:")
    func canPerformUnwindSegueAction(_ action: ObjCSelector?, from controller: UIViewController?, sender: NSObject?) -> Bool {
        action.map { responds(to: $0.name) } ?? false
    }
}

extension UIViewController {
    /// Loads the view from the controller's nib, in its storyboard or
    /// bundle; false when it has none.
    func loadViewFromNib() -> Bool {
        guard let name = state.nibName else { return false }
        let directory = state.storyboard?.state.path ?? state.nibBundlePath ?? NSBundle.main().bundlePath()
        // The bundle's own directory, its preferred localizations' and then
        // Base.lproj, as Darwin looks for a nib.
        var archive = Nibs.load(named: name, in: directory)
        var path = directory
        if archive == nil, state.storyboard == nil, let bundle = NSBundle.bundle(path: directory) {
            for localization in bundle.preferredLocalizations().elements {
                let candidate = directory + "/" + String(objCArgument: localization.objcObject) + ".lproj"
                if let found = Nibs.load(named: name, in: candidate) {
                    (archive, path) = (found, candidate)
                    break
                }
            }
        }
        if archive == nil {
            path = directory + "/Base.lproj"
            archive = Nibs.load(named: name, in: path)
        }
        guard let archive else { return false }
        var external = state.externalObjects
        if let storyboard = state.storyboard { external["UIStoryboardPlaceholder"] = storyboard }
        _ = Nibs.instantiate(archive, owner: self, external: external, bundlePath: path)
        return state.view != nil
    }
}
