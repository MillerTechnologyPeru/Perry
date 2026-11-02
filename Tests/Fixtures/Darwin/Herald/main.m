// User notifications: content, sounds, triggers and their next dates,
// requests, categories and actions, copying and archiving them. The
// notification center needs a launched app, which the simulator's spawned
// processes are not, so it is not compared here.

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        UNMutableNotificationContent *content = [UNMutableNotificationContent new];
        content.title = @"Delivery";
        content.subtitle = @"Truck 7";
        content.body = @"Arriving in 10 minutes";
        content.badge = @3;
        content.sound = [UNNotificationSound defaultSound];
        content.categoryIdentifier = @"DELIVERY";
        content.threadIdentifier = @"route-42";
        content.userInfo = @{@"stop": @5};
        say([NSString stringWithFormat:@"content: %@ / %@ / %@ badge %@ category %@ thread %@ info %@ attachments %lu",
             content.title, content.subtitle, content.body, content.badge, content.categoryIdentifier, content.threadIdentifier,
             content.userInfo[@"stop"], (unsigned long)content.attachments.count]);
        UNNotificationContent *frozen = [content copy];
        UNMutableNotificationContent *thawed = [frozen mutableCopy];
        thawed.title = @"Changed";
        say([NSString stringWithFormat:@"copies: %@ %@, mutable %d %d, equal %d", frozen.title, thawed.title,
             [frozen isKindOfClass:UNMutableNotificationContent.class], [thawed isKindOfClass:UNMutableNotificationContent.class],
             [frozen isEqual:content]]);
        UNMutableNotificationContent *empty = [UNMutableNotificationContent new];
        say([NSString stringWithFormat:@"empty: title '%@' body '%@' badge %@ sound %@ info %lu category '%@' level %lu score %.1f",
             empty.title, empty.body, empty.badge, empty.sound, (unsigned long)empty.userInfo.count, empty.categoryIdentifier,
             (unsigned long)empty.interruptionLevel, empty.relevanceScore]);

        UNNotificationSound *named = [UNNotificationSound soundNamed:@"chime.caf"];
        say([NSString stringWithFormat:@"sounds: equal default %d, named equal %d", [[UNNotificationSound defaultSound] isEqual:[UNNotificationSound defaultSound]],
             [named isEqual:[UNNotificationSound soundNamed:@"chime.caf"]]]);

        UNTimeIntervalNotificationTrigger *interval = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:90 repeats:NO];
        NSTimeInterval untilNext = interval.nextTriggerDate.timeIntervalSinceNow;
        say([NSString stringWithFormat:@"interval: %.0f repeats %d, next in ~%.0f", interval.timeInterval, interval.repeats, untilNext]);
        UNTimeIntervalNotificationTrigger *repeating = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:120 repeats:YES];
        say([NSString stringWithFormat:@"repeating: %.0f %d", repeating.timeInterval, repeating.repeats]);

        NSDateComponents *components = [NSDateComponents new];
        components.hour = 9;
        components.minute = 30;
        UNCalendarNotificationTrigger *calendar = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:components repeats:YES];
        NSDateComponents *next = [NSCalendar.currentCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond
                                                               fromDate:calendar.nextTriggerDate];
        say([NSString stringWithFormat:@"calendar: %ld:%ld repeats %d, next at %ld:%02ld:%02ld, in future %d", (long)calendar.dateComponents.hour,
             (long)calendar.dateComponents.minute, calendar.repeats, (long)next.hour, (long)next.minute, (long)next.second,
             calendar.nextTriggerDate.timeIntervalSinceNow > 0]);

        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"eta" content:content trigger:interval];
        say([NSString stringWithFormat:@"request: %@ %@ trigger %@, content copied %d", request.identifier, request.content.title,
             NSStringFromClass(request.trigger.class), request.content != content]);

        UNNotificationAction *accept = [UNNotificationAction actionWithIdentifier:@"ACCEPT" title:@"Accept"
                                                                          options:UNNotificationActionOptionForeground];
        UNNotificationAction *reject = [UNNotificationAction actionWithIdentifier:@"REJECT" title:@"Reject"
                                                                          options:UNNotificationActionOptionDestructive];
        UNTextInputNotificationAction *reply = [UNTextInputNotificationAction actionWithIdentifier:@"REPLY" title:@"Reply"
            options:UNNotificationActionOptionNone textInputButtonTitle:@"Send" textInputPlaceholder:@"Message"];
        UNNotificationCategory *category = [UNNotificationCategory categoryWithIdentifier:@"DELIVERY" actions:@[accept, reject, reply]
            intentIdentifiers:@[] options:UNNotificationCategoryOptionCustomDismissAction];
        say([NSString stringWithFormat:@"category: %@ actions %@ options %lu, reply %@/%@, accept options %lu",
             category.identifier, [[category.actions valueForKey:@"identifier"] componentsJoinedByString:@","], (unsigned long)category.options,
             reply.textInputButtonTitle, reply.textInputPlaceholder, (unsigned long)accept.options]);
        say([NSString stringWithFormat:@"identifiers: %@ %@, domain %@", UNNotificationDefaultActionIdentifier,
             UNNotificationDismissActionIdentifier, UNErrorDomain]);

        NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:request requiringSecureCoding:YES error:NULL];
        UNNotificationRequest *restored = [NSKeyedUnarchiver unarchivedObjectOfClass:UNNotificationRequest.class fromData:archive error:NULL];
        say([NSString stringWithFormat:@"archived: %@ %@ %@ %.0f", restored.identifier, restored.content.body,
             restored.content.userInfo[@"stop"], ((UNTimeIntervalNotificationTrigger *)restored.trigger).timeInterval]);

    }
    return 0;
}
