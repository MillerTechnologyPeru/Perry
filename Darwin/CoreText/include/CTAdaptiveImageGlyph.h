// CoreText's adaptive image glyph, which its public headers do not declare:
// the Objective-C class that holds an adaptive image glyph's image data.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(18.0))
@interface CTAdaptiveImageGlyph : NSObject
- (instancetype)initWithImageContent:(NSData *)imageContent;
@property (readonly, copy) NSData *imageContent;
@property (readonly, copy) NSString *contentIdentifier;
@property (readonly, copy) NSString *contentDescription;
@end

NS_ASSUME_NONNULL_END
