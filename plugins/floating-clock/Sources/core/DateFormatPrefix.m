#import "DateFormatPrefix.h"

NSString *FCDateFormatPrefix(NSString *presetId) {
    if ([presetId isEqualToString:@"long"])         return @"EEEE MMMM d  ";
    if ([presetId isEqualToString:@"iso"])          return @"yyyy-MM-dd  ";
    if ([presetId isEqualToString:@"numeric"])      return @"M/d  ";
    if ([presetId isEqualToString:@"weeknum"])      return @"'Wk' w  ";
    if ([presetId isEqualToString:@"dayofyr"])      return @"'Day' D  ";
    if ([presetId isEqualToString:@"usa"])          return @"M/d/yyyy  ";
    if ([presetId isEqualToString:@"european"])     return @"d.M.yyyy  ";
    if ([presetId isEqualToString:@"compact_iso"])  return @"MM-dd  ";
    if ([presetId isEqualToString:@"weekday_only"]) return @"EEEE  ";       // iter-227 — e.g. "Saturday"
    if ([presetId isEqualToString:@"monthday"])     return @"MMM d  ";      // iter-227 — e.g. "Apr 25"
    return @"EEE MMM d  ";  // "short" default (also the nil / unknown fallback)
}
