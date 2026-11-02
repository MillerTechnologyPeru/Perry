// Launching a UIKit app: UIApplicationMain, the delegate's launch callbacks,
// the scene lifecycle from the Info.plist's scene manifest, application
// and scene state, launch notifications and the responder chain.

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <stdlib.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *stateName(UIApplicationState state) {
    switch (state) {
        case UIApplicationStateActive: return @"active";
        case UIApplicationStateInactive: return @"inactive";
        case UIApplicationStateBackground: return @"background";
    }
    return @"unknown";
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate

- (instancetype)init {
    self = [super init];
    say([NSString stringWithFormat:@"delegate init, application exists %d", UIApplication.sharedApplication != nil]);
    return self;
}

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)options {
    say([NSString stringWithFormat:@"will finish launching: shared %d, delegate set %d, state %@",
         application == UIApplication.sharedApplication, application.delegate == self,
         stateName(application.applicationState)]);
    return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    say([NSString stringWithFormat:@"did finish launching: state %@", stateName(application.applicationState)]);
    say([NSString stringWithFormat:@"application is a %@, delegate is a %@",
         NSStringFromClass(application.class), NSStringFromClass([application.delegate class])]);
    say([NSString stringWithFormat:@"responders: delegate %d, application %d, next of application is delegate %d",
         [self isKindOfClass:UIResponder.class], [application isKindOfClass:UIResponder.class],
         application.nextResponder == (id)self]);
    say([NSString stringWithFormat:@"can become first responder %d", self.canBecomeFirstResponder]);
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    say([NSString stringWithFormat:@"application did become active: state %@", stateName(application.applicationState)]);
}

@end

static NSString *sceneStateName(UISceneActivationState state) {
    switch (state) {
        case UISceneActivationStateUnattached: return @"unattached";
        case UISceneActivationStateForegroundActive: return @"foreground active";
        case UISceneActivationStateForegroundInactive: return @"foreground inactive";
        case UISceneActivationStateBackground: return @"background";
    }
    return @"unknown";
}

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    say([NSString stringWithFormat:@"scene will connect: a %@, delegate is self %d, state %@, application state %@",
         NSStringFromClass(scene.class), scene.delegate == self, sceneStateName(scene.activationState),
         stateName(UIApplication.sharedApplication.applicationState)]);
    say([NSString stringWithFormat:@"session role %@, configuration %@, delegate class %@, scene is session's %d",
         session.role, session.configuration.name, NSStringFromClass(session.configuration.delegateClass),
         session.scene == scene]);
    say([NSString stringWithFormat:@"connected scenes %lu, open sessions %lu",
         (unsigned long)UIApplication.sharedApplication.connectedScenes.count,
         (unsigned long)UIApplication.sharedApplication.openSessions.count]);
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    say([NSString stringWithFormat:@"scene will enter foreground: state %@", sceneStateName(scene.activationState)]);
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    say([NSString stringWithFormat:@"scene did become active: state %@, application state %@",
         sceneStateName(scene.activationState), stateName(UIApplication.sharedApplication.applicationState)]);
    // Scenes connect asynchronously on Darwin, so the exit waits for this
    // rather than for a time after launch.
    [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:NO block:^(NSTimer *timer) {
        say([NSString stringWithFormat:@"timer fired: state %@", stateName(UIApplication.sharedApplication.applicationState)]);
        exit(0);
    }];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        say(@"main");
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil
                        usingBlock:^(NSNotification *note) {
            say([NSString stringWithFormat:@"notification: did finish launching, object is application %d",
                 note.object == UIApplication.sharedApplication]);
        }];
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil
                        usingBlock:^(NSNotification *note) {
            say(@"notification: did become active");
        }];
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
