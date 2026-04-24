#import "FontResolver.h"

NSFont *resolveClockFont(CGFloat size) {
    NSString *override = [[NSUserDefaults standardUserDefaults] stringForKey:@"FontName"];
    if ([override isKindOfClass:[NSString class]] && override.length > 0) {
        NSFont *f = [NSFont fontWithName:override size:size];
        if (f) return f;
    }

    NSString *plist = [NSHomeDirectory() stringByAppendingPathComponent:
                       @"Library/Preferences/com.googlecode.iterm2.plist"];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:plist];
    if ([prefs isKindOfClass:[NSDictionary class]]) {
        NSArray *bookmarks = prefs[@"New Bookmarks"];
        NSString *defaultGuid = prefs[@"Default Bookmark Guid"];
        NSDictionary *chosen = nil;

        if ([bookmarks isKindOfClass:[NSArray class]]) {
            for (NSDictionary *bm in bookmarks) {
                if (![bm isKindOfClass:[NSDictionary class]]) continue;
                NSString *guid = bm[@"Guid"];
                if ([guid isKindOfClass:[NSString class]] && defaultGuid &&
                    [guid isEqualToString:defaultGuid]) {
                    chosen = bm;
                    break;
                }
            }
            if (!chosen && bookmarks.count > 0) {
                NSDictionary *first = bookmarks[0];
                if ([first isKindOfClass:[NSDictionary class]]) chosen = first;
            }
        }

        if ([chosen isKindOfClass:[NSDictionary class]]) {
            NSString *spec = chosen[@"Normal Font"];
            if ([spec isKindOfClass:[NSString class]] && spec.length > 0) {
                // "FontName 12" → extract FontName portion
                NSRange r = [spec rangeOfString:@" " options:NSBackwardsSearch];
                NSString *name = (r.location != NSNotFound) ? [spec substringToIndex:r.location] : spec;
                NSFont *f = [NSFont fontWithName:name size:size];
                if (f) return f;
            }
        }
    }

    if (@available(macOS 10.15, *)) {
        return [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightMedium];
    }

    NSFont *menlo = [NSFont fontWithName:@"Menlo-Regular" size:size];
    return menlo ?: [NSFont systemFontOfSize:size weight:NSFontWeightMedium];
}

NSFontWeight FCParseFontWeight(NSString *weightId) {
    if (![weightId isKindOfClass:[NSString class]] || weightId.length == 0) {
        return NSFontWeightMedium;
    }
    if ([weightId isEqualToString:@"regular"])  return NSFontWeightRegular;
    if ([weightId isEqualToString:@"medium"])   return NSFontWeightMedium;
    if ([weightId isEqualToString:@"semibold"]) return NSFontWeightSemibold;
    if ([weightId isEqualToString:@"bold"])     return NSFontWeightBold;
    if ([weightId isEqualToString:@"heavy"])    return NSFontWeightHeavy;
    return NSFontWeightMedium;
}

NSFont *FCResolveMonoFont(CGFloat size, NSFontWeight weight) {
    if (@available(macOS 10.15, *)) {
        return [NSFont monospacedSystemFontOfSize:size weight:weight];
    }
    NSFont *menlo = [NSFont fontWithName:@"Menlo-Regular" size:size];
    return menlo ?: [NSFont systemFontOfSize:size weight:weight];
}

NSFontWeight FCResolveSegmentWeight(NSString *segmentKey) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *local = [d stringForKey:segmentKey];
    if ([local isKindOfClass:[NSString class]] && local.length > 0) {
        return FCParseFontWeight(local);
    }
    return FCParseFontWeight([d stringForKey:@"FontWeight"]);
}

CGFloat FCParseLetterSpacing(NSString *spacingId) {
    if (![spacingId isKindOfClass:[NSString class]] || spacingId.length == 0) {
        return 0.0;
    }
    if ([spacingId isEqualToString:@"compact"]) return -1.0;
    if ([spacingId isEqualToString:@"tight"])   return -0.5;
    if ([spacingId isEqualToString:@"normal"])  return  0.0;
    if ([spacingId isEqualToString:@"airy"])    return  0.5;
    if ([spacingId isEqualToString:@"wide"])    return  1.0;
    return 0.0;
}

void FCApplyLetterSpacing(NSMutableAttributedString *out) {
    if (!out || out.length == 0) return;
    CGFloat kern = FCParseLetterSpacing(
        [[NSUserDefaults standardUserDefaults] stringForKey:@"LetterSpacing"]);
    if (fabs(kern) < 0.001) return;
    [out addAttribute:NSKernAttributeName
                value:@(kern)
                range:NSMakeRange(0, out.length)];
}
