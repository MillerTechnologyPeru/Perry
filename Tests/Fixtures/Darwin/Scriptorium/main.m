// JavaScriptCore: evaluating scripts, values of each type and their
// conversions both ways, properties and subscripts, calling, constructing
// and invoking, exceptions and the exception handler, blocks as JavaScript
// functions with the current this and arguments, an Objective-C object
// exported through JSExport, contexts sharing a virtual machine, and the
// C API. Error messages differ between JavaScriptCore versions, so errors
// print by name.

#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

@protocol PointExports <JSExport>
@property double x;
@property double y;
@property (readonly) double length;
- (NSString *)describeWithPrefix:(NSString *)prefix;
JSExportAs(scale, - (void)scaleBy:(double)factor);
+ (instancetype)pointWithX:(double)x y:(double)y;
@end

@interface Pointer2D : NSObject <PointExports>
@property double hidden;
@end

@implementation Pointer2D
@synthesize x, y;
- (double)length { return sqrt(x * x + y * y); }
- (NSString *)describeWithPrefix:(NSString *)prefix { return [NSString stringWithFormat:@"%@(%g, %g)", prefix, x, y]; }
- (void)scaleBy:(double)factor { x *= factor; y *= factor; }
+ (instancetype)pointWithX:(double)x y:(double)y {
    Pointer2D *point = [Pointer2D new];
    point.x = x;
    point.y = y;
    return point;
}
@end

static NSString *kind(JSValue *value) {
    if (value.isUndefined) return @"undefined";
    if (value.isNull) return @"null";
    if (value.isBoolean) return @"boolean";
    if (value.isNumber) return @"number";
    if (value.isString) return @"string";
    if (value.isArray) return @"array";
    if (value.isDate) return @"date";
    if (value.isObject) return @"object";
    return @"?";
}

static JSValueRef nativeAdd(JSContextRef context, JSObjectRef function, JSObjectRef thisObject, size_t count,
                            const JSValueRef arguments[], JSValueRef *exception) {
    double sum = 0;
    for (size_t i = 0; i < count; i++) sum += JSValueToNumber(context, arguments[i], exception);
    return JSValueMakeNumber(context, sum);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        JSContext *context = [JSContext new];
        context.name = @"Scriptorium";
        say([NSString stringWithFormat:@"eval: %@ %@ %@ %@", [context evaluateScript:@"1 + 2 * 3"], [context evaluateScript:@"'a' + 'b'"],
             [context evaluateScript:@"[1, 2, 3].map(n => n * n).join('-')"], [context evaluateScript:@"typeof Symbol()"]]);
        for (NSString *script in @[@"undefined", @"null", @"true", @"42.5", @"'text'", @"[1, 'two']", @"new Date(0)", @"({a: 1})",
                                   @"(function () {})"]) {
            JSValue *value = [context evaluateScript:script];
            say([NSString stringWithFormat:@"kind %@: %@", script, kind(value)]);
        }

        // Conversions out.
        JSValue *object = [context evaluateScript:@"({name: 'Perry', count: 3, ratio: 0.5, ok: true, list: [1, 'x', null], nested: {deep: [true]}})"];
        NSDictionary *dictionary = [object toDictionary];
        NSArray *keys = [dictionary.allKeys sortedArrayUsingSelector:@selector(compare:)];
        say([NSString stringWithFormat:@"toDictionary: %@; count %@ ratio %@ ok %@ list %@ nested %@", [keys componentsJoinedByString:@","],
             dictionary[@"count"], dictionary[@"ratio"], dictionary[@"ok"], [dictionary[@"list"] componentsJoinedByString:@"|"],
             [dictionary[@"nested"][@"deep"] firstObject]]);
        JSValue *number = [context evaluateScript:@"3.75"];
        say([NSString stringWithFormat:@"numbers: double %.2f int32 %d uint32 %u bool %d string %@ number %@", [number toDouble], [number toInt32],
             [number toUInt32], [number toBool], [number toString], [number toNumber]]);
        say([NSString stringWithFormat:@"strings: %@ %@ %@, null %@ undefined %@", [[context evaluateScript:@"[1,2]"] toString],
             [[context evaluateScript:@"({})"] toString], [[context evaluateScript:@"false"] toString],
             [[context evaluateScript:@"null"] toObject], [[context evaluateScript:@"undefined"] toObject]]);
        NSDate *date = [[context evaluateScript:@"new Date(86400000)"] toDate];
        say([NSString stringWithFormat:@"date: %.0f, array %@", date.timeIntervalSince1970,
             [[[context evaluateScript:@"[3, 'b', true]"] toArray] componentsJoinedByString:@","]]);

        // Conversions in.
        context[@"fromObjC"] = @{@"title": @"hello", @"values": @[@1, @2.5, @YES], @"none": [NSNull null], @"when": [NSDate dateWithTimeIntervalSince1970:1000]};
        say([NSString stringWithFormat:@"in: %@", [context evaluateScript:@"JSON.stringify([fromObjC.title, fromObjC.values, fromObjC.none, typeof fromObjC.values[2], fromObjC.when instanceof Date, fromObjC.when.getTime()])"]]);
        JSValue *made = [JSValue valueWithNewObjectInContext:context];
        made[@"a"] = @1;
        [made setValue:@"two" forProperty:@"b"];
        made[@"list"] = [JSValue valueWithNewArrayInContext:context];
        made[@"list"][0] = @"zero";
        [made[@"list"] setValue:@"one" atIndex:1];
        say([NSString stringWithFormat:@"built: %@, has b %d c %d, deleted %d, length %@", [context[@"JSON"] invokeMethod:@"stringify" withArguments:@[made]],
             [made hasProperty:@"b"], [made hasProperty:@"c"], [made deleteProperty:@"a"], made[@"list"][@"length"]]);
        say([NSString stringWithFormat:@"values: %@ %@ %@ %@ %@ %@", [JSValue valueWithBool:YES inContext:context], [JSValue valueWithDouble:1.5 inContext:context],
             [JSValue valueWithInt32:-7 inContext:context], [JSValue valueWithNullInContext:context], [JSValue valueWithUndefinedInContext:context],
             [JSValue valueWithNewRegularExpressionFromPattern:@"a+" flags:@"g" inContext:context]]);

        // Equality and instances.
        JSValue *one = [JSValue valueWithInt32:1 inContext:context];
        say([NSString stringWithFormat:@"equality: %d %d %d %d, instance %d", [one isEqualToObject:@1], [one isEqualToObject:@"1"],
             [one isEqualWithTypeCoercionToObject:@"1"], [one isEqualToObject:[JSValue valueWithDouble:1 inContext:context]],
             [[context evaluateScript:@"[]"] isInstanceOf:context[@"Array"]]]);

        // Calling.
        [context evaluateScript:@"function add(a, b) { return a + b; } function Box(v) { this.v = v; } Box.prototype.twice = function () { return this.v * 2; };"];
        JSValue *box = [context[@"Box"] constructWithArguments:@[@21]];
        say([NSString stringWithFormat:@"call: %@, construct %@, invoke %@, missing %@", [context[@"add"] callWithArguments:@[@2, @3]], box[@"v"],
             [box invokeMethod:@"twice" withArguments:@[]], [context[@"nothing"] callWithArguments:@[]]]);

        // Exceptions.
        JSValue *thrown = [context evaluateScript:@"null.property"];
        say([NSString stringWithFormat:@"exception: result %@, name %@, has message %d, cleared %d", kind(thrown), context.exception[@"name"],
             [context.exception[@"message"] toString].length > 0, ({ context.exception = nil; context.exception == nil; })]);
        __block NSMutableArray *caught = [NSMutableArray array];
        context.exceptionHandler = ^(JSContext *where, JSValue *exception) {
            [caught addObject:[exception[@"name"] toString]];
            where.exception = exception;
        };
        [context evaluateScript:@"throw new RangeError('out')"];
        [context evaluateScript:@"undefinedFunction()"];
        [context evaluateScript:@"JSON.parse('{')"];
        say([NSString stringWithFormat:@"handler: %@, exception kept %@", [caught componentsJoinedByString:@","], context.exception[@"name"]]);
        context.exception = nil;

        // Blocks.
        context[@"multiply"] = ^(double a, double b) { return a * b; };
        context[@"greet"] = ^NSString *(NSString *name) { return [@"hi " stringByAppendingString:name]; };
        context[@"info"] = ^{
            NSArray *arguments = [JSContext currentArguments];
            JSValue *this = [JSContext currentThis];
            return [NSString stringWithFormat:@"%lu args, first %@, this has tag %d, same context %d", (unsigned long)arguments.count, arguments.firstObject,
                    [this hasProperty:@"tag"], [JSContext currentContext] == context];
        };
        context[@"fail"] = ^{
            [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"from block" inContext:[JSContext currentContext]];
        };
        say([NSString stringWithFormat:@"blocks: %@ %@ / %@ / %@", [context evaluateScript:@"multiply(6, 7)"], [context evaluateScript:@"greet('Perry')"],
             [context evaluateScript:@"({tag: 1, info}).info(5, 'x')"], [context evaluateScript:@"try { fail(); 'no' } catch (e) { 'caught ' + e.message }"]]);
        say([NSString stringWithFormat:@"block kind: %@", [context evaluateScript:@"typeof multiply"]]);

        // An exported object.
        Pointer2D *point = [Pointer2D pointWithX:3 y:4];
        context[@"point"] = point;
        context[@"Point"] = [Pointer2D class];
        say([NSString stringWithFormat:@"export: %@", [context evaluateScript:@"[point.x, point.y, point.length, point.describeWithPrefix('P'), typeof point.hidden, typeof point.scaleBy].join(' ')"]]);
        [context evaluateScript:@"point.x = 6; point.scale(0.5);"];
        say([NSString stringWithFormat:@"export changed: %g %g, round trip %d", point.x, point.y, [context[@"point"] toObject] == point]);
        say([NSString stringWithFormat:@"export class: %@", [context evaluateScript:@"var q = Point.pointWithXY(1, 2); q.describeWithPrefix('Q')"]]);
        say([NSString stringWithFormat:@"export to objc: %@", NSStringFromClass([[[context evaluateScript:@"q"] toObject] class])]);

        // Contexts in one virtual machine share values.
        JSContext *other = [[JSContext alloc] initWithVirtualMachine:context.virtualMachine];
        other[@"shared"] = context[@"add"];
        say([NSString stringWithFormat:@"vm: same %d, shared call %@, globals separate %d", other.virtualMachine == context.virtualMachine,
             [other evaluateScript:@"shared(10, 5)"], [other[@"add"] isUndefined]]);
        say([NSString stringWithFormat:@"global: %@, name %@, ref round trip %d", [context.globalObject[@"Math"][@"PI"] toString], context.name,
             [JSContext contextWithJSGlobalContextRef:context.JSGlobalContextRef] == context]);

        // The C API.
        JSGlobalContextRef global = JSGlobalContextCreate(NULL);
        JSStringRef source = JSStringCreateWithUTF8CString("[1, 2, 3].length + 0.5");
        JSValueRef result = JSEvaluateScript(global, source, NULL, NULL, 1, NULL);
        JSStringRelease(source);
        JSStringRef name = JSStringCreateWithUTF8CString("nativeAdd");
        JSObjectRef function = JSObjectMakeFunctionWithCallback(global, name, nativeAdd);
        JSObjectSetProperty(global, JSContextGetGlobalObject(global), name, function, kJSPropertyAttributeNone, NULL);
        JSStringRelease(name);
        JSStringRef call = JSStringCreateWithUTF8CString("nativeAdd(1, 2, 39)");
        JSValueRef added = JSEvaluateScript(global, call, NULL, NULL, 1, NULL);
        JSStringRelease(call);
        JSStringRef text = JSValueToStringCopy(global, JSValueMakeBoolean(global, true), NULL);
        char buffer[16];
        JSStringGetUTF8CString(text, buffer, sizeof(buffer));
        JSStringRelease(text);
        JSValueRef thrownError = NULL;
        JSStringRef bad = JSStringCreateWithUTF8CString("(");
        JSValueRef none = JSEvaluateScript(global, bad, NULL, NULL, 1, &thrownError);
        JSStringRelease(bad);
        say([NSString stringWithFormat:@"c api: %.1f, native %.0f, string %s, type %d, syntax error %d %d", JSValueToNumber(global, result, NULL),
             JSValueToNumber(global, added, NULL), buffer, JSValueGetType(global, result), none == NULL, thrownError != NULL]);
        JSValue *bridged = [JSValue valueWithJSValueRef:added inContext:[JSContext contextWithJSGlobalContextRef:global]];
        say([NSString stringWithFormat:@"bridged: %@", [bridged toNumber]]);
        JSGlobalContextRelease(global);
    }
    return 0;
}
