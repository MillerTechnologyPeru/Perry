// A made-up framework for sdk-scan's tests.
#import <Widget/WidgetBase.h>

@protocol WidgetDrawing
- (void)drawInContext:(void *)context;
@end

/// A widget.
__attribute__((availability(macos, introduced=10.10)))
@interface Widget : WidgetBase <WidgetDrawing> {
    int _count;
}
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly) int count;
@property (class, nonatomic, readonly) Widget *sharedWidget;
- (instancetype)initWithName:(const char *)name count:(int)count;
+ (Widget *)widgetNamed:(const char *)name;
- (void)oldMethod __attribute__((availability(macos, introduced=10.0, deprecated=10.12)));
@end

extern const char *const WidgetDidChangeNotification;
extern int WidgetCount(Widget *widget, BOOL visibleOnly);
