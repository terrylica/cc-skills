// Dual-zone landing-time formatter. Used by NEXT TO OPEN (and any
// future section that needs to render "when does this event land in
// both timezones") to produce user-local and market-local strings
// with consistent weekday-differs disambiguation.
//
// Rules:
//   - When the landing date (y-m-d) is TODAY in user-local:
//       userStr = "HH:mm"
//   - When landing date differs:
//       userStr = "EEE HH:mm"
//   - When the landing WEEKDAY differs between user-local and market-local
//     (e.g. Sun your time vs. Mon market time):
//       mktStr  = "EEE HH:mm ABBREV"
//     Otherwise:
//       mktStr  = "HH:mm ABBREV"
//
// This encodes the iter-49 + iter-68 disambiguation rules as a single
// function so future callers get identical behavior automatically.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

void FCFormatLandingTime(NSDate *landsAt,
                         const char * _Nullable mktIana,
                         NSString * _Nonnull * _Nonnull outUserStr,
                         NSString * _Nonnull * _Nonnull outMktStr);

NS_ASSUME_NONNULL_END
