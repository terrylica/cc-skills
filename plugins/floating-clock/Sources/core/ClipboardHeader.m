#import "ClipboardHeader.h"

NSString *FCComposeClipboardSnapshot(NSString *label, NSString *body, NSDate *now) {
    if (body.length == 0) return @"";
    NSDateFormatter *hdrFmt = [[NSDateFormatter alloc] init];
    hdrFmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    hdrFmt.dateFormat = @"yyyy-MM-dd HH:mm:ss 'UTC'";
    NSString *stamp = [hdrFmt stringFromDate:now ?: [NSDate date]];
    NSString *safeLabel = label ?: @"";
    return [NSString stringWithFormat:@"# Floating Clock · %@ · %@\n%@",
            safeLabel, stamp, body];
}
