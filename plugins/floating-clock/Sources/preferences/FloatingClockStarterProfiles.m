#import "FloatingClockStarterProfiles.h"

NSDictionary *buildStarterProfiles(void) {
    return @{
        @"Default": @{
            @"DisplayMode": @"three-segment",
            @"LocalTheme": @"terminal",
            @"ActiveTheme": @"green_phosphor",
            @"NextTheme": @"soft_glass",
            @"ColorTheme": @"terminal",
            @"FontSize": @24.0,
            @"ShowSeconds": @YES,
            @"ShowDate": @YES,
            @"DateFormat": @"short",
            @"TimeFormat": @"24h",
            @"CanvasOpacity": @0.75,
            @"ActiveBarCells": @40,
            @"NextItemCount": @3,
            @"SelectedMarket": @"local",
        },
        @"Day Trader": @{
            @"DisplayMode": @"three-segment",
            @"LocalTheme": @"amber_crt",
            @"ActiveTheme": @"amber_crt",
            @"NextTheme": @"amber_crt",
            @"FontSize": @32.0,
            @"ShowSeconds": @YES,
            @"ShowDate": @NO,
            @"TimeFormat": @"24h",
            @"ActiveBarCells": @12,
            @"NextItemCount": @5,
            @"SelectedMarket": @"nyse",
        },
        @"Night Owl": @{
            @"DisplayMode": @"local-only",
            @"ColorTheme": @"soft_glass",
            @"FontSize": @16.0,
            @"ShowSeconds": @YES,
            @"ShowDate": @NO,
            @"TimeFormat": @"24h",
        },
        @"Minimalist": @{
            @"DisplayMode": @"local-only",
            @"ColorTheme": @"high_contrast",
            @"FontSize": @20.0,
            @"ShowSeconds": @NO,
            @"ShowDate": @NO,
            @"TimeFormat": @"24h",
        },
        @"Watch Party": @{
            @"DisplayMode": @"single-market",
            @"ColorTheme": @"dracula",
            @"FontSize": @48.0,
            @"ShowSeconds": @YES,
            @"ShowDate": @YES,
            @"TimeFormat": @"24h",
            @"SelectedMarket": @"nyse",
        },
    };
}

NSArray<NSString *> *profileManagedKeys(void) {
    return @[
        @"DisplayMode", @"LocalTheme", @"ActiveTheme", @"NextTheme", @"ColorTheme",
        @"FontName", @"FontSize", @"ShowSeconds", @"ShowDate", @"TimeFormat",
        @"DateFormat", @"CanvasOpacity", @"ProgressBarStyle", @"LayoutMode", @"SegmentGap", @"CornerStyle", @"ShadowStyle",
        @"ActiveBarCells", @"NextItemCount", @"SelectedMarket",
        @"ActiveFontSize", @"NextFontSize", @"ShowFlags", @"Density",
        @"ShowUTCReference",
    ];
}
