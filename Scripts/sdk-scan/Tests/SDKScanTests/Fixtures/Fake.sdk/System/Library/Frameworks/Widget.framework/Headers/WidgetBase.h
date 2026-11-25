// A made-up root class for sdk-scan's tests.
typedef signed char BOOL;

__attribute__((objc_root_class))
@interface WidgetBase
+ (instancetype)alloc;
- (instancetype)init;
@end

@interface WidgetBase (Naming)
@property (nonatomic) const char *name;
- (void)setName:(const char *)name animated:(BOOL)animated;
@end
