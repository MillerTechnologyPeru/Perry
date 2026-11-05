// UIKit's SPI that its Swift module and SwiftUI use, which its public
// headers do not declare.

#import <Foundation/Foundation.h>

// The vibrancy a trait collection's colors take.
typedef NS_ENUM(NSInteger, _UIUserInterfaceVibrancy) {
    _UIUserInterfaceVibrancyNone = 0,
    _UIUserInterfaceVibrancyVibrant = 1,
};
