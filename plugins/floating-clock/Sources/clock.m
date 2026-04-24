#import <Cocoa/Cocoa.h>
#import "rendering/VerticallyCenteredTextFieldCell.h"
#import "rendering/AttributedStringLayoutMeasurer.h"
#import "rendering/FontResolver.h"
#import "data/ThemeCatalog.h"
#import "data/MarketCatalog.h"
#import "data/MarketSessionCalculator.h"
#import "preferences/FloatingClockStarterProfiles.h"
#import "content/ActiveSegmentContentBuilder.h"
#import "content/NextSegmentContentBuilder.h"
#import "segments/FloatingClockSegmentViews.h"
#import "core/FloatingClockPanel.h"
#import "core/FloatingClockPanel+Layout.h"
#import "menu/FloatingClockPanel+MenuBuilder.h"
#import "core/FloatingClockPanel+Runtime.h"
#import "preferences/FloatingClockPanel+ProfileManagement.h"
#import "actions/FloatingClockPanel+ActionHandlers.h"

// # FILE-SIZE-OK

// Forward declaration
// Forward declarations no longer needed — FloatingClockPanel and ClockContentView
// are now imported from core/FloatingClockPanel.h and segments/FloatingClockSegmentViews.h


// ClockTheme + kThemes + themeForId moved to Sources/data/ThemeCatalog.{h,m}
// ClockMarket + kMarkets + marketForId moved to Sources/data/MarketCatalog.{h,m}

// SessionState enum + computeSessionState + formatCountdown + buildProgressBar
// + glyphForState + colorForState moved to Sources/data/MarketSessionCalculator.{h,m}

// buildStarterProfiles + profileManagedKeys moved to Sources/preferences/FloatingClockStarterProfiles.{h,m}


// cityCodeForIana moved to Sources/data/MarketCatalog.{h,m}

// colorForState moved to Sources/data/MarketSessionCalculator.{h,m}

// swatchForTheme moved to Sources/data/ThemeCatalog.{h,m}

// resolveClockFont moved to Sources/rendering/FontResolver.{h,m}

// ClockContentView + LocalSegmentView + ActiveSegmentView + NextSegmentView
// moved to Sources/segments/FloatingClockSegmentViews.{h,m}

// FloatingClockPanel @interface moved to Sources/core/FloatingClockPanel.h

@implementation FloatingClockPanel

- (instancetype)init {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    // Migrate from legacy TextColor to ColorTheme BEFORE registerDefaults
    if ([d objectForKey:@"ColorTheme"] == nil) {
        NSString *mapped = @"terminal";
        // Check if legacy TextColor was explicitly set (not a default)
        NSString *legacy = [d objectForKey:@"TextColor"];
        if ([legacy isKindOfClass:[NSString class]]) {
            if ([legacy isEqualToString:@"amber"])      mapped = @"amber_crt";
            else if ([legacy isEqualToString:@"green"]) mapped = @"green_phosphor";
            // cyan/red/white all fall through to "terminal"
        }
        [d setObject:mapped forKey:@"ColorTheme"];
        [d synchronize];
    }

    // Migrate DisplayMode: if not set and SelectedMarket != "local", use "single-market"; else use "three-segment"
    if ([d objectForKey:@"DisplayMode"] == nil) {
        NSString *sel = [d stringForKey:@"SelectedMarket"];
        NSString *mode = @"three-segment";  // default for fresh installs
        if ([sel isKindOfClass:[NSString class]] && ![sel isEqualToString:@"local"]) {
            mode = @"single-market";  // migrate legacy users
        }
        [d setObject:mode forKey:@"DisplayMode"];
        [d synchronize];
    }

    // Register default values for NSUserDefaults (after migration, so if ColorTheme wasn't set, it's now there)
    [d registerDefaults:@{
        @"ShowSeconds": @YES,
        @"ShowDate": @YES,
        @"TimeFormat": @"24h",
        @"FontSize": @24.0,
        @"SelectedMarket": @"local",
        @"DisplayMode": @"three-segment",
        @"LocalTheme": @"terminal",
        @"ActiveTheme": @"green_phosphor",
        @"NextTheme": @"soft_glass",
        @"ActiveBarCells": @40,
        @"NextItemCount": @3,
        @"DateFormat": @"short",
        @"CanvasOpacity": @0.75,
        @"ProgressBarStyle": @"dots",
        @"LayoutMode": @"stacked-local-top",
        @"SegmentGap": @"normal",
        @"CornerStyle": @"rounded",
        @"ShadowStyle": @"none",
        @"ActiveFontSize": @11.0,
        @"NextFontSize": @11.0,
        @"FontWeight": @"medium",
        @"LetterSpacing": @"normal",
        @"ShowFlags": @YES,
        @"Density": @"default",
        @"ShowUTCReference": @YES,
        @"ShowSkyState": @YES,
        @"ShowProgressPercent": @NO,
        @"Profiles": buildStarterProfiles(),
        @"ActiveProfile": @"Default",
    }];

    // Ensure Profiles and ActiveProfile are persisted (registerDefaults doesn't persist to disk)
    if ([d objectForKey:@"Profiles"] == nil) {
        [d setObject:buildStarterProfiles() forKey:@"Profiles"];
    }
    if ([d objectForKey:@"ActiveProfile"] == nil) {
        [d setObject:@"Default" forKey:@"ActiveProfile"];
    }
    [d synchronize];

    NSRect defaultFrame = NSMakeRect(0, 0, 140, 50);
    self = [super initWithContentRect:defaultFrame
                            styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (!self) return nil;

    self.level = NSFloatingWindowLevel;
    self.floatingPanel = YES;
    self.becomesKeyOnlyIfNeeded = YES;
    self.movableByWindowBackground = YES;
    self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary;
    self.hasShadow = YES;
    self.opaque = NO;
    self.titleVisibility = NSWindowTitleHidden;
    // Panel background must be fully clear in three-segment mode — segment
    // views own their own backgrounds. Otherwise the panel's default solid
    // windowBackgroundColor blocks desktop/other-app visibility when
    // CanvasOpacity < 1. (Single-market and local-only modes overwrite this
    // with the theme's bg color.)
    self.backgroundColor = [NSColor clearColor];

    // Custom content view for menu support
    ClockContentView *cv = [[ClockContentView alloc] initWithFrame:defaultFrame];
    cv.wantsLayer = YES;
    cv.layer.cornerRadius = 10.0;
    cv.layer.masksToBounds = YES;
    cv.layer.backgroundColor = [[NSColor clearColor] CGColor];
    cv.panel = self;
    self.contentView = cv;

    // Text field for clock display
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSInsetRect(defaultFrame, 8, 8)];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.alignment = NSTextAlignmentCenter;
    label.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [cv addSubview:label];
    _label = label;

    // Secondary label for session state (hidden in local mode)
    NSTextField *sessionLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 8, 200, 16)];
    sessionLabel.editable = NO;
    sessionLabel.selectable = NO;
    sessionLabel.bezeled = NO;
    sessionLabel.drawsBackground = NO;
    sessionLabel.alignment = NSTextAlignmentCenter;
    sessionLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
    sessionLabel.hidden = YES;  // default hidden for local mode
    sessionLabel.autoresizingMask = NSViewWidthSizable;
    [cv addSubview:sessionLabel];
    _sessionLabel = sessionLabel;

    // Attach menu to content view
    NSMenu *menu = [self buildMenu];
    cv.menu = menu;
    menu.delegate = cv;

    [self restorePosition];
    [self applyDisplaySettings];
    [self setupTimer];

    // Install ⌘Q global handler; retain the returned observer so we can
    // remove it on terminate — otherwise leaks reports a 32-byte root leak
    // on the _NSLocalEventObserver.
    _keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                        handler:^NSEvent *(NSEvent *e) {
        if ((e.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagCommand &&
            [e.charactersIgnoringModifiers isEqualToString:@"q"]) {
            [NSApp terminate:nil];
            return nil;
        }
        return e;
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidMove:)
                                                 name:NSWindowDidMoveNotification
                                               object:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screensChanged:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];
    return self;
}


#pragma mark - Display Settings

// buildMenu / submenuTitled / groupedSubmenuTitled / setChecksInMenu /
// representedObject:matchesValue: / refreshMenuChecks moved to
// Sources/menu/FloatingClockPanel+MenuBuilder.m

// applyDisplaySettings / applyThreeSegmentLayout / relayoutThreeSegmentIfNeeded /
// applyLocalOnlyLayout / applySingleMarketLayout moved to
// Sources/core/FloatingClockPanel+Layout.{h,m}

/* applyThreeSegmentLayout — moved */

// Re-measure ACTIVE/NEXT content and resize window if it changed. Called
// from tickThreeSegment on every 1Hz update so the clock grows/shrinks as
// markets open and close throughout the day. setFrame is a no-op when
// values match, so this stays cheap.

#pragma mark - Profile Management


- (void)setDateFormat:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"DateFormat"];
        [self applyDisplaySettings];
    }
}


@end

// @implementation blocks for the 4 view classes moved to
// Sources/segments/FloatingClockSegmentViews.m

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        FloatingClockPanel *panel = [[FloatingClockPanel alloc] init];
        [panel makeKeyAndOrderFront:nil];
        [app run];
    }
    return 0;
}
