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

NSArray<NSArray<NSString *> *> *FCDateFormatMenuPairs(void) {
    return @[@[@"Short         (Thu Apr 23)",         @"short"],
             @[@"Long          (Thursday April 23)",  @"long"],
             @[@"ISO           (2026-04-23)",         @"iso"],
             @[@"Compact ISO   (04-23)",              @"compact_iso"],
             @[@"Numeric       (4/23)",               @"numeric"],
             @[@"USA           (4/23/2026)",          @"usa"],
             @[@"European      (23.4.2026)",          @"european"],
             @[@"Week Number   (Wk 17)",              @"weeknum"],
             @[@"Day of Year   (Day 114)",            @"dayofyr"],
             @[@"Weekday Only  (Saturday)",           @"weekday_only"],
             @[@"Month-Day     (Apr 25)",             @"monthday"]];
}

