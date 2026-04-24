#import "FloatingClockPanel+ActionHandlers.h"
#import "../core/FloatingClockPanel+Layout.h"

@implementation FloatingClockPanel (ActionHandlers)

- (void)toggleShowSeconds:(NSMenuItem *)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:@"ShowSeconds"] forKey:@"ShowSeconds"];
    [self applyDisplaySettings];
}

- (void)toggleShowDate:(NSMenuItem *)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:@"ShowDate"] forKey:@"ShowDate"];
    [self applyDisplaySettings];
}

- (void)setTimeFormat:(NSMenuItem *)sender {
    if (sender.representedObject) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"TimeFormat"];
        [self applyDisplaySettings];
    }
}

- (void)setFontSize:(NSMenuItem *)sender {
    if (sender.representedObject) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"FontSize"];
        [self applyDisplaySettings];
    }
}

- (void)setColorTheme:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"ColorTheme"];
        [self applyDisplaySettings];
    }
}

- (void)setLocalTheme:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"LocalTheme"];
        [self applyDisplaySettings];
    }
}

- (void)setActiveTheme:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"ActiveTheme"];
        [self applyDisplaySettings];
    }
}

- (void)setNextTheme:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"NextTheme"];
        [self applyDisplaySettings];
    }
}

- (void)setMarket:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"SelectedMarket"];
        [self applyDisplaySettings];
    }
}

- (void)setDisplayMode:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"DisplayMode"];
        [self applyDisplaySettings];
    }
}

- (void)setCanvasOpacity:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setDouble:[sender.representedObject doubleValue] forKey:@"CanvasOpacity"];
        [self applyDisplaySettings];
    }
}

- (void)setActiveBarCells:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setInteger:[sender.representedObject integerValue] forKey:@"ActiveBarCells"];
        [self applyDisplaySettings];
    }
}

- (void)setProgressBarStyle:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"ProgressBarStyle"];
        [self applyDisplaySettings];
    }
}

- (void)setLayoutMode:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"LayoutMode"];
        [self applyDisplaySettings];
    }
}

- (void)setSegmentGap:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"SegmentGap"];
        [self applyDisplaySettings];
    }
}

- (void)setCornerStyle:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"CornerStyle"];
        [self applyDisplaySettings];
    }
}

- (void)setShadowStyle:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"ShadowStyle"];
        [self applyDisplaySettings];
    }
}

- (void)setActiveFontSize:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setDouble:[sender.representedObject doubleValue] forKey:@"ActiveFontSize"];
        [self applyDisplaySettings];
    }
}

- (void)setNextFontSize:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setDouble:[sender.representedObject doubleValue] forKey:@"NextFontSize"];
        [self applyDisplaySettings];
    }
}

- (void)toggleShowFlags:(NSMenuItem *)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:![d boolForKey:@"ShowFlags"] forKey:@"ShowFlags"];
    [self applyDisplaySettings];
}

- (void)toggleShowUTCReference:(NSMenuItem *)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL cur = ![d objectForKey:@"ShowUTCReference"] || [d boolForKey:@"ShowUTCReference"];
    [d setBool:!cur forKey:@"ShowUTCReference"];
    [self applyDisplaySettings];
}

- (void)toggleShowSkyState:(NSMenuItem *)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL cur = ![d objectForKey:@"ShowSkyState"] || [d boolForKey:@"ShowSkyState"];
    [d setBool:!cur forKey:@"ShowSkyState"];
    [self applyDisplaySettings];
}

- (void)setDensity:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSString class]]) {
        [[NSUserDefaults standardUserDefaults] setObject:sender.representedObject forKey:@"Density"];
        [self applyDisplaySettings];
    }
}

- (void)setNextItemCount:(NSMenuItem *)sender {
    if ([sender.representedObject isKindOfClass:[NSNumber class]]) {
        [[NSUserDefaults standardUserDefaults] setInteger:[sender.representedObject integerValue] forKey:@"NextItemCount"];
        [self applyDisplaySettings];
    }
}

- (void)applyTheme:(const ClockTheme *)theme toSegmentView:(NSView *)seg textField:(NSTextField *)field {
    // CanvasOpacity is the direct backdrop alpha. "Opaque (100%)" means
    // genuinely opaque — user expectation. Theme's built-in alpha field
    // is the fallback when no CanvasOpacity is set (fresh install now
    // defaults to 1.0 so fresh look is opaque; user picks lower from menu
    // if they want see-through). Text always stays at alpha=1.0.
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    CGFloat bgAlpha;
    if ([d objectForKey:@"CanvasOpacity"]) {
        bgAlpha = [d doubleForKey:@"CanvasOpacity"];
    } else {
        bgAlpha = theme->alpha;
    }
    if (bgAlpha < 0.10) bgAlpha = 0.10;
    if (bgAlpha > 1.00) bgAlpha = 1.00;
    seg.layer.backgroundColor = [[NSColor colorWithRed:theme->bg_r green:theme->bg_g blue:theme->bg_b alpha:bgAlpha] CGColor];
    field.textColor = [NSColor colorWithRed:theme->fg_r green:theme->fg_g blue:theme->fg_b alpha:1.0];
}

- (void)resetPosition:(id)sender {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"FloatingClockWindowFrame"];
    [d removeObjectForKey:@"FloatingClockScreenNumber"];
    [self setFrame:[self defaultFrame] display:YES animate:YES];
}

- (void)showAbout:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Floating Clock";
    alert.informativeText = @"Minimal always-on-top floating desktop clock.\n\nObjective-C + NSPanel.\n© 2026 Terry Li";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

@end
