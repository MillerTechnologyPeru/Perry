// UIKit's SPI that its Swift module and SwiftUI use, which its public
// headers do not declare.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// The vibrancy a trait collection's colors take.
typedef NS_ENUM(NSInteger, _UIUserInterfaceVibrancy) {
    _UIUserInterfaceVibrancyNone = 0,
    _UIUserInterfaceVibrancyVibrant = 1,
};

NS_ASSUME_NONNULL_BEGIN

// Perry's initializers for actions and menus, under their Swift
// initializers: the class methods those stand for are unavailable to Swift.
@interface UIAction (PerryInitializers)
- (instancetype)initWithPerryTitle:(NSString *)title
                              image:(nullable UIImage *)image
                         identifier:(nullable UIActionIdentifier)identifier
                            handler:(UIActionHandler)handler
    NS_SWIFT_NAME(init(_perryTitle:image:identifier:handler:));
@end

@interface UIMenu (PerryInitializers)
- (instancetype)initWithPerryTitle:(NSString *)title
                              image:(nullable UIImage *)image
                         identifier:(nullable UIMenuIdentifier)identifier
                            options:(UIMenuOptions)options
                           children:(NSArray<UIMenuElement *> *)children
    NS_SWIFT_NAME(init(_perryTitle:image:identifier:options:children:));
@end

NS_ASSUME_NONNULL_END
