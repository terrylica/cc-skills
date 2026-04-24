#import "LandingTimeFormatter.h"
#import "../data/MarketCatalog.h"
#include <string.h>

void FCFormatLandingTime(NSDate *landsAt,
                         const char *mktIana,
                         NSString **outUserStr,
                         NSString **outMktStr) {
    NSTimeZone *localTz = [NSTimeZone localTimeZone];
    NSTimeZone *mktTz = (mktIana && *mktIana)
        ? [NSTimeZone timeZoneWithName:[NSString stringWithUTF8String:mktIana]]
        : nil;

    // User-local same-day check (y-m-d).
    NSCalendar *localCal = [NSCalendar currentCalendar];
    localCal.timeZone = localTz;
    NSCalendarUnit ymd = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay;
    NSDateComponents *nowC  = [localCal components:ymd fromDate:[NSDate date]];
    NSDateComponents *landC = [localCal components:ymd fromDate:landsAt];
    BOOL sameDay = (nowC.year == landC.year && nowC.month == landC.month && nowC.day == landC.day);

    // User-local vs market-local weekday comparison.
    NSCalendar *mktCal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    mktCal.timeZone = mktTz ?: localTz;
    NSInteger localWd = [localCal component:NSCalendarUnitWeekday fromDate:landsAt];
    NSInteger mktWd   = [mktCal component:NSCalendarUnitWeekday fromDate:landsAt];
    BOOL weekdayDiffers = (localWd != mktWd);

    // User-local string.
    NSDateFormatter *userFmt = [[NSDateFormatter alloc] init];
    userFmt.timeZone = localTz;
    BOOL showUserWeekday = weekdayDiffers || !sameDay;
    userFmt.dateFormat = showUserWeekday ? @"EEE HH:mm" : @"HH:mm";
    *outUserStr = [userFmt stringFromDate:landsAt];

    // Market-local string (with TZ abbrev).
    if (mktTz) {
        NSDateFormatter *mFmt = [[NSDateFormatter alloc] init];
        mFmt.timeZone = mktTz;
        mFmt.dateFormat = weekdayDiffers ? @"EEE HH:mm" : @"HH:mm";
        NSString *abbrev = friendlyAbbrevForIana(mktIana, landsAt);
        *outMktStr = [NSString stringWithFormat:@"%@ %@",
            [mFmt stringFromDate:landsAt], abbrev];
    } else {
        *outMktStr = @"";
    }
}
