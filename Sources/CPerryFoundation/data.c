// Class storage Mach-O images bind to, under Darwin's symbol names.

#define _GNU_SOURCE
#include "CPerryFoundation.h"

#include <string.h>
#include <unistd.h>

int perry_foundation_thread_id(void) { return (int)gettid(); }

#define DARWIN_SYMBOL(name) __asm__(name) __attribute__((visibility("default"), used))

perry_class_storage ns_string DARWIN_SYMBOL("_OBJC_CLASS_$_NSString");
perry_class_storage ns_string_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSString");
// String literals' isa. CoreFoundation exports it as an array; it is the
// class of constant strings.
perry_class_storage cf_constant_string DARWIN_SYMBOL("___CFConstantStringClassReference");
static perry_class_storage cf_constant_string_meta;
perry_class_storage ns_array DARWIN_SYMBOL("_OBJC_CLASS_$_NSArray");
perry_class_storage ns_array_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSArray");
perry_class_storage ns_mutable_array DARWIN_SYMBOL("_OBJC_CLASS_$_NSMutableArray");
perry_class_storage ns_mutable_array_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSMutableArray");
perry_class_storage ns_number DARWIN_SYMBOL("_OBJC_CLASS_$_NSNumber");
perry_class_storage ns_number_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSNumber");
// Number literals the compiler emits as static objects.
perry_class_storage ns_constant_integer DARWIN_SYMBOL("_OBJC_CLASS_$_NSConstantIntegerNumber");
perry_class_storage ns_constant_integer_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSConstantIntegerNumber");
perry_class_storage ns_constant_double DARWIN_SYMBOL("_OBJC_CLASS_$_NSConstantDoubleNumber");
perry_class_storage ns_constant_double_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSConstantDoubleNumber");
perry_class_storage ns_constant_float DARWIN_SYMBOL("_OBJC_CLASS_$_NSConstantFloatNumber");
perry_class_storage ns_constant_float_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSConstantFloatNumber");
static perry_class_storage cf_boolean, cf_boolean_meta;
perry_class_storage ns_mutable_string DARWIN_SYMBOL("_OBJC_CLASS_$_NSMutableString");
perry_class_storage ns_mutable_string_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSMutableString");
perry_class_storage ns_dictionary DARWIN_SYMBOL("_OBJC_CLASS_$_NSDictionary");
perry_class_storage ns_dictionary_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSDictionary");
perry_class_storage ns_mutable_dictionary DARWIN_SYMBOL("_OBJC_CLASS_$_NSMutableDictionary");
perry_class_storage ns_mutable_dictionary_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSMutableDictionary");
perry_class_storage ns_set DARWIN_SYMBOL("_OBJC_CLASS_$_NSSet");
perry_class_storage ns_set_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSSet");
perry_class_storage ns_mutable_set DARWIN_SYMBOL("_OBJC_CLASS_$_NSMutableSet");
perry_class_storage ns_mutable_set_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSMutableSet");
perry_class_storage ns_date DARWIN_SYMBOL("_OBJC_CLASS_$_NSDate");
perry_class_storage ns_date_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSDate");
perry_class_storage ns_timer DARWIN_SYMBOL("_OBJC_CLASS_$_NSTimer");
perry_class_storage ns_timer_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSTimer");
perry_class_storage ns_run_loop DARWIN_SYMBOL("_OBJC_CLASS_$_NSRunLoop");
perry_class_storage ns_run_loop_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSRunLoop");
perry_class_storage ns_notification DARWIN_SYMBOL("_OBJC_CLASS_$_NSNotification");
perry_class_storage ns_notification_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSNotification");
perry_class_storage ns_notification_center DARWIN_SYMBOL("_OBJC_CLASS_$_NSNotificationCenter");
perry_class_storage ns_notification_center_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSNotificationCenter");

perry_class_storage ns_data DARWIN_SYMBOL("_OBJC_CLASS_$_NSData");
perry_class_storage ns_data_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSData");
perry_class_storage ns_mutable_data DARWIN_SYMBOL("_OBJC_CLASS_$_NSMutableData");
perry_class_storage ns_mutable_data_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSMutableData");
perry_class_storage ns_url DARWIN_SYMBOL("_OBJC_CLASS_$_NSURL");
perry_class_storage ns_url_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSURL");
perry_class_storage ns_uuid DARWIN_SYMBOL("_OBJC_CLASS_$_NSUUID");
perry_class_storage ns_uuid_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSUUID");
perry_class_storage ns_null DARWIN_SYMBOL("_OBJC_CLASS_$_NSNull");
perry_class_storage ns_null_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSNull");
perry_class_storage ns_json_serialization DARWIN_SYMBOL("_OBJC_CLASS_$_NSJSONSerialization");
perry_class_storage ns_json_serialization_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSJSONSerialization");
perry_class_storage ns_process_info DARWIN_SYMBOL("_OBJC_CLASS_$_NSProcessInfo");
perry_class_storage ns_process_info_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSProcessInfo");
perry_class_storage ns_bundle DARWIN_SYMBOL("_OBJC_CLASS_$_NSBundle");
perry_class_storage ns_bundle_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSBundle");
perry_class_storage ns_error DARWIN_SYMBOL("_OBJC_CLASS_$_NSError");
perry_class_storage ns_error_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSError");
perry_class_storage ns_thread DARWIN_SYMBOL("_OBJC_CLASS_$_NSThread");
perry_class_storage ns_thread_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSThread");
perry_class_storage ns_user_defaults DARWIN_SYMBOL("_OBJC_CLASS_$_NSUserDefaults");
perry_class_storage ns_user_defaults_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSUserDefaults");
perry_class_storage ns_file_manager DARWIN_SYMBOL("_OBJC_CLASS_$_NSFileManager");
perry_class_storage ns_file_manager_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSFileManager");

// Run loop mode names. Both frameworks' names point at the same strings.
void *ns_default_run_loop_mode DARWIN_SYMBOL("_NSDefaultRunLoopMode");
void *ns_run_loop_common_modes DARWIN_SYMBOL("_NSRunLoopCommonModes");
void *cf_run_loop_default_mode DARWIN_SYMBOL("_kCFRunLoopDefaultMode");
void *cf_run_loop_common_modes DARWIN_SYMBOL("_kCFRunLoopCommonModes");
void *cf_null DARWIN_SYMBOL("_kCFNull");
void *ns_cocoa_error_domain DARWIN_SYMBOL("_NSCocoaErrorDomain");
void *ns_posix_error_domain DARWIN_SYMBOL("_NSPOSIXErrorDomain");
void *ns_localized_description_key DARWIN_SYMBOL("_NSLocalizedDescriptionKey");
void *ns_file_path_error_key DARWIN_SYMBOL("_NSFilePathErrorKey");
void *ns_underlying_error_key DARWIN_SYMBOL("_NSUnderlyingErrorKey");
// NSFileManager attribute keys and values.
void *constant_NSFileType DARWIN_SYMBOL("_NSFileType");
void *constant_NSFileTypeDirectory DARWIN_SYMBOL("_NSFileTypeDirectory");
void *constant_NSFileTypeRegular DARWIN_SYMBOL("_NSFileTypeRegular");
void *constant_NSFileTypeSymbolicLink DARWIN_SYMBOL("_NSFileTypeSymbolicLink");
void *constant_NSFileSize DARWIN_SYMBOL("_NSFileSize");
void *constant_NSFileModificationDate DARWIN_SYMBOL("_NSFileModificationDate");
void *constant_NSFilePosixPermissions DARWIN_SYMBOL("_NSFilePosixPermissions");

static void **const constants[PERRY_CONSTANT_COUNT] = {
    [PERRY_CONSTANT_NSDefaultRunLoopMode] = &ns_default_run_loop_mode,
    [PERRY_CONSTANT_NSRunLoopCommonModes] = &ns_run_loop_common_modes,
    [PERRY_CONSTANT_kCFRunLoopDefaultMode] = &cf_run_loop_default_mode,
    [PERRY_CONSTANT_kCFRunLoopCommonModes] = &cf_run_loop_common_modes,
    [PERRY_CONSTANT_kCFNull] = &cf_null,
    [PERRY_CONSTANT_NSCocoaErrorDomain] = &ns_cocoa_error_domain,
    [PERRY_CONSTANT_NSPOSIXErrorDomain] = &ns_posix_error_domain,
    [PERRY_CONSTANT_NSLocalizedDescriptionKey] = &ns_localized_description_key,
    [PERRY_CONSTANT_NSFilePathErrorKey] = &ns_file_path_error_key,
    [PERRY_CONSTANT_NSUnderlyingErrorKey] = &ns_underlying_error_key,
    [PERRY_CONSTANT_NSFileType] = &constant_NSFileType,
    [PERRY_CONSTANT_NSFileTypeDirectory] = &constant_NSFileTypeDirectory,
    [PERRY_CONSTANT_NSFileTypeRegular] = &constant_NSFileTypeRegular,
    [PERRY_CONSTANT_NSFileTypeSymbolicLink] = &constant_NSFileTypeSymbolicLink,
    [PERRY_CONSTANT_NSFileSize] = &constant_NSFileSize,
    [PERRY_CONSTANT_NSFileModificationDate] = &constant_NSFileModificationDate,
    [PERRY_CONSTANT_NSFilePosixPermissions] = &constant_NSFilePosixPermissions,
};

void **perry_foundation_constant(perry_foundation_constant_id which) { return constants[which]; }

// Collection literals whose elements are all constants.
perry_class_storage ns_constant_array DARWIN_SYMBOL("_OBJC_CLASS_$_NSConstantArray");
perry_class_storage ns_constant_array_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSConstantArray");
perry_class_storage ns_constant_dictionary DARWIN_SYMBOL("_OBJC_CLASS_$_NSConstantDictionary");
perry_class_storage ns_constant_dictionary_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSConstantDictionary");

// The boolean objects, which @YES and @NO reference directly, and
// kCFBooleanTrue/False, which point at them.
struct perry_boolean { perry_class_storage *isa; uint64_t value; };
struct perry_boolean boolean_true DARWIN_SYMBOL("___kCFBooleanTrue") = { &cf_boolean, 1 };
struct perry_boolean boolean_false DARWIN_SYMBOL("___kCFBooleanFalse") = { &cf_boolean, 0 };
const struct perry_boolean *const cf_boolean_true DARWIN_SYMBOL("_kCFBooleanTrue") = &boolean_true;
const struct perry_boolean *const cf_boolean_false DARWIN_SYMBOL("_kCFBooleanFalse") = &boolean_false;

static perry_class_storage *const classes[PERRY_CLASS_COUNT][2] = {
    [PERRY_CLASS_NSString] = { &ns_string, &ns_string_meta },
    [PERRY_CLASS_NSConstantString] = { &cf_constant_string, &cf_constant_string_meta },
    [PERRY_CLASS_NSArray] = { &ns_array, &ns_array_meta },
    [PERRY_CLASS_NSMutableArray] = { &ns_mutable_array, &ns_mutable_array_meta },
    [PERRY_CLASS_NSNumber] = { &ns_number, &ns_number_meta },
    [PERRY_CLASS_NSConstantIntegerNumber] = { &ns_constant_integer, &ns_constant_integer_meta },
    [PERRY_CLASS_NSConstantDoubleNumber] = { &ns_constant_double, &ns_constant_double_meta },
    [PERRY_CLASS_NSConstantFloatNumber] = { &ns_constant_float, &ns_constant_float_meta },
    [PERRY_CLASS_NSCFBoolean] = { &cf_boolean, &cf_boolean_meta },
    [PERRY_CLASS_NSMutableString] = { &ns_mutable_string, &ns_mutable_string_meta },
    [PERRY_CLASS_NSDictionary] = { &ns_dictionary, &ns_dictionary_meta },
    [PERRY_CLASS_NSMutableDictionary] = { &ns_mutable_dictionary, &ns_mutable_dictionary_meta },
    [PERRY_CLASS_NSSet] = { &ns_set, &ns_set_meta },
    [PERRY_CLASS_NSMutableSet] = { &ns_mutable_set, &ns_mutable_set_meta },
    [PERRY_CLASS_NSConstantArray] = { &ns_constant_array, &ns_constant_array_meta },
    [PERRY_CLASS_NSConstantDictionary] = { &ns_constant_dictionary, &ns_constant_dictionary_meta },
    [PERRY_CLASS_NSDate] = { &ns_date, &ns_date_meta },
    [PERRY_CLASS_NSTimer] = { &ns_timer, &ns_timer_meta },
    [PERRY_CLASS_NSRunLoop] = { &ns_run_loop, &ns_run_loop_meta },
    [PERRY_CLASS_NSNotification] = { &ns_notification, &ns_notification_meta },
    [PERRY_CLASS_NSNotificationCenter] = { &ns_notification_center, &ns_notification_center_meta },
    [PERRY_CLASS_NSData] = { &ns_data, &ns_data_meta },
    [PERRY_CLASS_NSMutableData] = { &ns_mutable_data, &ns_mutable_data_meta },
    [PERRY_CLASS_NSURL] = { &ns_url, &ns_url_meta },
    [PERRY_CLASS_NSUUID] = { &ns_uuid, &ns_uuid_meta },
    [PERRY_CLASS_NSNull] = { &ns_null, &ns_null_meta },
    [PERRY_CLASS_NSJSONSerialization] = { &ns_json_serialization, &ns_json_serialization_meta },
    [PERRY_CLASS_NSProcessInfo] = { &ns_process_info, &ns_process_info_meta },
    [PERRY_CLASS_NSBundle] = { &ns_bundle, &ns_bundle_meta },
    [PERRY_CLASS_NSError] = { &ns_error, &ns_error_meta },
    [PERRY_CLASS_NSThread] = { &ns_thread, &ns_thread_meta },
    [PERRY_CLASS_NSUserDefaults] = { &ns_user_defaults, &ns_user_defaults_meta },
    [PERRY_CLASS_NSFileManager] = { &ns_file_manager, &ns_file_manager_meta },
};

void *perry_foundation_boolean(int value) { return value ? (void *)&boolean_true : (void *)&boolean_false; }

// Objective-C class names, for defining classes by name.
static const char *const class_names[PERRY_CLASS_COUNT] = {
    [PERRY_CLASS_NSString] = "NSString",
    [PERRY_CLASS_NSConstantString] = "__NSCFConstantString",
    [PERRY_CLASS_NSArray] = "NSArray",
    [PERRY_CLASS_NSMutableArray] = "NSMutableArray",
    [PERRY_CLASS_NSNumber] = "NSNumber",
    [PERRY_CLASS_NSConstantIntegerNumber] = "NSConstantIntegerNumber",
    [PERRY_CLASS_NSConstantDoubleNumber] = "NSConstantDoubleNumber",
    [PERRY_CLASS_NSConstantFloatNumber] = "NSConstantFloatNumber",
    [PERRY_CLASS_NSCFBoolean] = "__NSCFBoolean",
    [PERRY_CLASS_NSMutableString] = "NSMutableString",
    [PERRY_CLASS_NSDictionary] = "NSDictionary",
    [PERRY_CLASS_NSMutableDictionary] = "NSMutableDictionary",
    [PERRY_CLASS_NSSet] = "NSSet",
    [PERRY_CLASS_NSMutableSet] = "NSMutableSet",
    [PERRY_CLASS_NSConstantArray] = "NSConstantArray",
    [PERRY_CLASS_NSConstantDictionary] = "NSConstantDictionary",
    [PERRY_CLASS_NSDate] = "NSDate",
    [PERRY_CLASS_NSTimer] = "NSTimer",
    [PERRY_CLASS_NSRunLoop] = "NSRunLoop",
    [PERRY_CLASS_NSNotification] = "NSNotification",
    [PERRY_CLASS_NSNotificationCenter] = "NSNotificationCenter",
    [PERRY_CLASS_NSData] = "NSData",
    [PERRY_CLASS_NSMutableData] = "NSMutableData",
    [PERRY_CLASS_NSURL] = "NSURL",
    [PERRY_CLASS_NSUUID] = "NSUUID",
    [PERRY_CLASS_NSNull] = "NSNull",
    [PERRY_CLASS_NSJSONSerialization] = "NSJSONSerialization",
    [PERRY_CLASS_NSProcessInfo] = "NSProcessInfo",
    [PERRY_CLASS_NSBundle] = "NSBundle",
    [PERRY_CLASS_NSError] = "NSError",
    [PERRY_CLASS_NSThread] = "NSThread",
    [PERRY_CLASS_NSUserDefaults] = "NSUserDefaults",
    [PERRY_CLASS_NSFileManager] = "NSFileManager",
};

perry_class_storage *perry_foundation_class_named(const char *name, perry_class_storage **metaclass) {
    for (int which = 0; which < PERRY_CLASS_COUNT; which++) {
        if (class_names[which] && strcmp(class_names[which], name) == 0) {
            *metaclass = classes[which][1];
            return classes[which][0];
        }
    }
    return NULL;
}

perry_class_storage *perry_foundation_class(perry_foundation_class_id which) { return classes[which][0]; }
perry_class_storage *perry_foundation_metaclass(perry_foundation_class_id which) { return classes[which][1]; }
