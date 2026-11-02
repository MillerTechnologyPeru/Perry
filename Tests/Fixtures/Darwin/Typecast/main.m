// Uniform type identifiers: UTType's system types, lookups by extension and
// MIME type, conformance, dynamic types, and MobileCoreServices' C API.

#import <Foundation/Foundation.h>
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE && !TARGET_OS_MACCATALYST
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <CoreServices/CoreServices.h>
#endif
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *describe(UTType *type) {
    if (!type) return @"nil";
    return [NSString stringWithFormat:@"%@ ext=%@ mime=%@ declared=%d dynamic=%d public=%d", type.identifier,
            type.preferredFilenameExtension, type.preferredMIMEType, type.isDeclared, type.isDynamic, type.isPublicType];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSArray<UTType *> *constants = @[UTTypeItem, UTTypeContent, UTTypeData, UTTypeText, UTTypePlainText, UTTypeUTF8PlainText,
            UTTypeHTML, UTTypeXML, UTTypeJSON, UTTypePropertyList, UTTypeImage, UTTypeJPEG, UTTypePNG, UTTypeGIF, UTTypeHEIC,
            UTTypeTIFF, UTTypeBMP, UTTypeSVG, UTTypePDF, UTTypeMovie, UTTypeVideo, UTTypeMPEG4Movie, UTTypeQuickTimeMovie,
            UTTypeAudio, UTTypeMP3, UTTypeMPEG4Audio, UTTypeWAV, UTTypeZIP, UTTypeGZIP, UTTypeArchive, UTTypeFolder,
            UTTypeDirectory, UTTypeURL, UTTypeFileURL, UTTypeVCard, UTTypeRTF, UTTypeCommaSeparatedText, UTTypeSourceCode,
            UTTypeSwiftSource, UTTypeExecutable, UTTypeFont, UTTypeEmailMessage, UTTypeCalendarEvent, UTTypeSpreadsheet,
            UTTypePresentation, UTTypeDatabase, UTTypeLivePhoto, UTTypeRAWImage, UTTypeWebP, UTTypeICO];
        for (UTType *type in constants) say(describe(type));

        say(@"-- by extension");
        for (NSString *ext in @[@"jpg", @"jpeg", @"JPG", @"png", @"txt", @"json", @"pdf", @"mp4", @"mov", @"m4a", @"mp3",
                                @"zip", @"html", @"csv", @"heic", @"gif", @"svg", @"xml", @"plist", @"swift", @"docx", @"xlsx"]) {
            say([NSString stringWithFormat:@"%@: %@", ext, describe([UTType typeWithFilenameExtension:ext])]);
        }
        say(@"-- by MIME type");
        for (NSString *mime in @[@"image/jpeg", @"image/png", @"text/plain", @"application/json", @"application/pdf", @"video/mp4",
                                 @"audio/mpeg", @"text/html", @"application/zip", @"text/csv", @"image/svg+xml"]) {
            say([NSString stringWithFormat:@"%@: %@", mime, describe([UTType typeWithMIMEType:mime])]);
        }

        say(@"-- conformance");
        say([NSString stringWithFormat:@"jpeg: image %d data %d item %d text %d content %d", [UTTypeJPEG conformsToType:UTTypeImage],
             [UTTypeJPEG conformsToType:UTTypeData], [UTTypeJPEG conformsToType:UTTypeItem], [UTTypeJPEG conformsToType:UTTypeText],
             [UTTypeJPEG conformsToType:UTTypeContent]]);
        say([NSString stringWithFormat:@"json: text %d plain %d; mp4 movie %d audiovisual %d; folder directory %d",
             [UTTypeJSON conformsToType:UTTypeText], [UTTypeJSON conformsToType:UTTypePlainText],
             [UTTypeMPEG4Movie conformsToType:UTTypeMovie], [UTTypeMPEG4Movie conformsToType:UTTypeAudiovisualContent],
             [UTTypeFolder conformsToType:UTTypeDirectory]]);
        say([NSString stringWithFormat:@"subtype %d supertype %d, equal %d", [UTTypePNG isSubtypeOfType:UTTypeImage],
             [UTTypeImage isSupertypeOfType:UTTypePNG], [[UTType typeWithIdentifier:@"public.png"] isEqual:UTTypePNG]]);
        NSArray *supertypes = [[UTTypePNG.supertypes allObjects] valueForKey:@"identifier"];
        say([NSString stringWithFormat:@"png supertypes: %@", [[supertypes sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]]);
        say([NSString stringWithFormat:@"jpeg tags: %@ / %@", [UTTypeJPEG.tags[UTTagClassFilenameExtension] componentsJoinedByString:@","],
             [UTTypeJPEG.tags[UTTagClassMIMEType] componentsJoinedByString:@","]]);
        say([NSString stringWithFormat:@"description: %@ / %@", UTTypeJPEG.localizedDescription, UTTypePlainText.localizedDescription]);

        say(@"-- dynamic and unknown");
        UTType *unknown = [UTType typeWithFilenameExtension:@"perryxyz"];
        say([NSString stringWithFormat:@"unknown ext: dynamic %d, prefix %d, data %d, ext %@", unknown.isDynamic,
             [unknown.identifier hasPrefix:@"dyn."], [unknown conformsToType:UTTypeData], unknown.preferredFilenameExtension]);
        UTType *conforming = [UTType typeWithFilenameExtension:@"perryxyz" conformingToType:UTTypeText];
        say([NSString stringWithFormat:@"conforming: text %d same %d", [conforming conformsToType:UTTypeText], [conforming isEqual:unknown]]);
        say([NSString stringWithFormat:@"unknown id: %@, unknown mime %d", describe([UTType typeWithIdentifier:@"com.example.nothing"]),
             [UTType typeWithMIMEType:@"application/x-perry-nothing"].isDynamic]);
        UTType *exported = [UTType exportedTypeWithIdentifier:@"org.perry.custom"];
        say([NSString stringWithFormat:@"exported undeclared: %@", exported.identifier]);

        say(@"-- MobileCoreServices");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CFStringRef jpeg = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, CFSTR("jpg"), NULL);
        CFStringRef mime = UTTypeCopyPreferredTagWithClass(kUTTypePNG, kUTTagClassMIMEType);
        CFStringRef ext = UTTypeCopyPreferredTagWithClass(kUTTypeMPEG4, kUTTagClassFilenameExtension);
        say([NSString stringWithFormat:@"c api: %@ %@ %@, conforms %d %d, equal %d, constants %@ %@ %@ %@", jpeg, mime, ext,
             UTTypeConformsTo(kUTTypeJPEG, kUTTypeImage), UTTypeConformsTo(kUTTypeJPEG, kUTTypeMovie),
             UTTypeEqual(kUTTypePNG, CFSTR("public.png")), kUTTypeImage, kUTTypeMovie, kUTTypePlainText, kUTTypeData]);
        CFStringRef dyn = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, CFSTR("perryxyz"), kUTTypeData);
        say([NSString stringWithFormat:@"c dynamic: %d %d", UTTypeIsDynamic(dyn), UTTypeIsDeclared(kUTTypePNG)]);
#pragma clang diagnostic pop
    }
    return 0;
}
