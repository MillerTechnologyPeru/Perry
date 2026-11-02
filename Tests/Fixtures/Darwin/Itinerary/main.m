// View controllers in a navigation controller: loading, the appearance
// and containment callbacks in order, pushing, popping and replacing the
// stack, the navigation bar and items, modal presentation and dismissal,
// and child view controllers. Geometry is checked against the window, so
// the output does not depend on the device's screen. Steps run on timers,
// letting UIKit finish each transition first.

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <stdlib.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

@interface Screen : UIViewController
@property (nonatomic, copy) NSString *name;
- (instancetype)initWithName:(NSString *)name;
@end

static NSString *nameOf(UIViewController *controller) {
    if (controller == nil) return @"nil";
    if ([controller isKindOfClass:Screen.class]) return ((Screen *)controller).name;
    if ([controller isKindOfClass:UINavigationController.class]) return @"Navigation";
    return NSStringFromClass(controller.class);
}

static NSString *names(NSArray<UIViewController *> *controllers) {
    NSMutableArray *parts = [NSMutableArray array];
    for (UIViewController *controller in controllers) [parts addObject:nameOf(controller)];
    return [NSString stringWithFormat:@"[%@]", [parts componentsJoinedByString:@", "]];
}

@implementation Screen

- (instancetype)initWithName:(NSString *)name {
    self = [super initWithNibName:nil bundle:nil];
    _name = [name copy];
    self.title = name;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    say([NSString stringWithFormat:@"  %@ did load", self.name]);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    say([NSString stringWithFormat:@"  %@ will appear: moving to parent %d, being presented %d", self.name,
         self.isMovingToParentViewController, self.isBeingPresented]);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    say([NSString stringWithFormat:@"  %@ did appear: in window %d", self.name, self.view.window != nil]);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    say([NSString stringWithFormat:@"  %@ will disappear: moving from parent %d, being dismissed %d", self.name,
         self.isMovingFromParentViewController, self.isBeingDismissed]);
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    say([NSString stringWithFormat:@"  %@ did disappear: in window %d", self.name, self.view.window != nil]);
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    [super willMoveToParentViewController:parent];
    say([NSString stringWithFormat:@"  %@ will move to %@", self.name, nameOf(parent)]);
}

- (void)didMoveToParentViewController:(UIViewController *)parent {
    [super didMoveToParentViewController:parent];
    say([NSString stringWithFormat:@"  %@ did move to %@", self.name, nameOf(parent)]);
}

@end

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *navigation;
@property (nonatomic, strong) Screen *home;
@property (nonatomic, strong) NSMutableArray *steps;
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    Screen *home = [[Screen alloc] initWithName:@"Home"];
    self.home = home;
    say(@"init navigation");
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:home];
    self.navigation = navigation;
    say([NSString stringWithFormat:@"created: stack %@, home parent %@, home navigation %d, views loaded %d %d",
         names(navigation.viewControllers), nameOf(home.parentViewController), home.navigationController == navigation,
         navigation.isViewLoaded, home.isViewLoaded]);
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    say(@"set root");
    self.window.rootViewController = navigation;
    say(@"make key and visible");
    [self.window makeKeyAndVisible];
    say(@"visible");
}

// Whether the scene activates before or after the first appearance pass
// varies between runs on iOS, so it is not printed.
- (void)sceneDidBecomeActive:(UIScene *)scene {
    [self buildSteps];
    [self runNextStep];
}

- (void)runNextStep {
    if (self.steps.count == 0) {
        say(@"done");
        exit(0);
    }
    void (^step)(void) = self.steps.firstObject;
    [self.steps removeObjectAtIndex:0];
    [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:NO block:^(NSTimer *timer) {
        step();
        [self runNextStep];
    }];
}

- (void)buildSteps {
    UINavigationController *navigation = self.navigation;
    UIWindow *window = self.window;
    Screen *home = self.home;
    Screen *detail = [[Screen alloc] initWithName:@"Detail"];
    Screen *first = [[Screen alloc] initWithName:@"First"];
    Screen *second = [[Screen alloc] initWithName:@"Second"];
    Screen *modal = [[Screen alloc] initWithName:@"Modal"];
    Screen *child = [[Screen alloc] initWithName:@"Child"];
    __block UIViewController *popped;
    __block NSArray *poppedAll;
    self.steps = [NSMutableArray arrayWithArray:@[
        ^{
            UINavigationBar *bar = navigation.navigationBar;
            say([NSString stringWithFormat:@"initial: stack %@, top %@, visible %@, bar items %lu, top item %@, back item %@",
                 names(navigation.viewControllers), nameOf(navigation.topViewController), nameOf(navigation.visibleViewController),
                 (unsigned long)bar.items.count, bar.topItem.title, bar.backItem.title]);
            say([NSString stringWithFormat:@"  bar: height %.0f, at safe area top %d, full width %d, hidden %d, in navigation view %d",
                 bar.frame.size.height, bar.frame.origin.y == window.safeAreaInsets.top, bar.frame.size.width == window.bounds.size.width,
                 navigation.navigationBarHidden, [bar isDescendantOfView:navigation.view]]);
            say([NSString stringWithFormat:@"  home view: fills window %d, in window %d, under navigation view %d, safe top below bar %d",
                 CGRectEqualToRect([home.view convertRect:home.view.bounds toView:nil], window.bounds), home.view.window == window,
                 [home.view isDescendantOfView:navigation.view], home.view.safeAreaInsets.top == CGRectGetMaxY(bar.frame)]);
            say([NSString stringWithFormat:@"  navigation item: title %@, item is home's %d, root parent %@, navigation in window %d",
                 home.navigationItem.title, bar.topItem == home.navigationItem, nameOf(navigation.parentViewController),
                 navigation.view.window == window]);
        },
        ^{
            say(@"push Detail");
            [navigation pushViewController:detail animated:NO];
            say([NSString stringWithFormat:@"pushed: stack %@, top %@, detail parent %@, detail navigation %d, detail loaded %d",
                 names(navigation.viewControllers), nameOf(navigation.topViewController), nameOf(detail.parentViewController),
                 detail.navigationController == navigation, detail.isViewLoaded]);
        },
        ^{
            UINavigationBar *bar = navigation.navigationBar;
            say([NSString stringWithFormat:@"after push: top item %@, back item %@, bar items %lu, home in window %d, detail in window %d",
                 bar.topItem.title, bar.backItem.title, (unsigned long)bar.items.count, home.view.window != nil,
                 detail.view.window != nil]);
            say(@"pop");
            popped = [navigation popViewControllerAnimated:NO];
            say([NSString stringWithFormat:@"popped %@: stack %@, detail parent %@, detail navigation %d", nameOf(popped),
                 names(navigation.viewControllers), nameOf(detail.parentViewController), detail.navigationController != nil]);
        },
        ^{
            say([NSString stringWithFormat:@"after pop: top item %@, bar items %lu, home in window %d, detail in window %d, pop root %@",
                 navigation.navigationBar.topItem.title, (unsigned long)navigation.navigationBar.items.count,
                 home.view.window != nil, detail.view.window != nil, nameOf([navigation popViewControllerAnimated:NO])]);
            say(@"set stack");
            [navigation setViewControllers:@[home, first, second] animated:NO];
            say([NSString stringWithFormat:@"set: stack %@, top %@", names(navigation.viewControllers), nameOf(navigation.topViewController)]);
        },
        ^{
            say([NSString stringWithFormat:@"after set: top item %@, back item %@, first loaded %d, second in window %d",
                 navigation.navigationBar.topItem.title, navigation.navigationBar.backItem.title, first.isViewLoaded,
                 second.view.window != nil]);
            say(@"pop to root");
            poppedAll = [navigation popToRootViewControllerAnimated:NO];
            say([NSString stringWithFormat:@"popped to root %@: stack %@", names(poppedAll), names(navigation.viewControllers)]);
        },
        ^{
            say(@"present Modal");
            modal.modalPresentationStyle = UIModalPresentationFullScreen;
            [navigation presentViewController:modal animated:NO completion:^{
                say(@"  present completion");
            }];
            say([NSString stringWithFormat:@"presented: presented %@, presenting %@, home presenting %@, modal parent %@",
                 nameOf(navigation.presentedViewController), nameOf(modal.presentingViewController),
                 nameOf(home.presentedViewController), nameOf(modal.parentViewController)]);
        },
        ^{
            say([NSString stringWithFormat:@"after present: modal in window %d, modal fills window %d, home in window %d",
                 modal.view.window == window, CGRectEqualToRect([modal.view convertRect:modal.view.bounds toView:nil], window.bounds),
                 home.view.window != nil]);
            say(@"dismiss");
            [modal dismissViewControllerAnimated:NO completion:^{
                say(@"  dismiss completion");
            }];
            say([NSString stringWithFormat:@"dismissed: presented %@", nameOf(navigation.presentedViewController)]);
        },
        ^{
            say([NSString stringWithFormat:@"after dismiss: modal presenting %@, modal in window %d, home in window %d",
                 nameOf(modal.presentingViewController), modal.view.window != nil, home.view.window != nil]);
            say(@"add child");
            [home addChildViewController:child];
            say([NSString stringWithFormat:@"added: children %@, child parent %@, child navigation %d", names(home.childViewControllers),
                 nameOf(child.parentViewController), child.navigationController == navigation]);
            child.view.frame = CGRectMake(0, 0, 100, 100);
            say(@"add child view");
            [home.view addSubview:child.view];
            [child didMoveToParentViewController:home];
        },
        ^{
            say(@"remove child");
            [child willMoveToParentViewController:nil];
            [child.view removeFromSuperview];
            [child removeFromParentViewController];
            say([NSString stringWithFormat:@"removed: children %@, child parent %@", names(home.childViewControllers),
                 nameOf(child.parentViewController)]);
        },
        ^{
            UIBarButtonItem *edit = [[UIBarButtonItem alloc] initWithTitle:@"Edit" style:UIBarButtonItemStylePlain target:nil action:nil];
            UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:nil action:nil];
            home.navigationItem.rightBarButtonItem = edit;
            home.navigationItem.leftBarButtonItem = done;
            home.title = @"Start";
            UINavigationItem *top = navigation.navigationBar.topItem;
            say([NSString stringWithFormat:@"items: title %@, right %@ style %ld, left title %@ style %ld, right items %lu",
                 top.title, top.rightBarButtonItem.title, (long)top.rightBarButtonItem.style, top.leftBarButtonItem.title,
                 (long)top.leftBarButtonItem.style, (unsigned long)top.rightBarButtonItems.count]);
            say(@"hide bar");
            [navigation setNavigationBarHidden:YES animated:NO];
        },
        ^{
            say([NSString stringWithFormat:@"bar hidden: hidden %d, bar view hidden %d, safe top is window's %d",
                 navigation.navigationBarHidden, navigation.navigationBar.hidden,
                 home.view.safeAreaInsets.top == window.safeAreaInsets.top]);
        },
    ]];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, nil);
    }
}
