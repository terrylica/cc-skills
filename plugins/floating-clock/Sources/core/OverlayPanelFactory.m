#import "OverlayPanelFactory.h"

NSPanel *FCCreateOverlayPanel(NSPanel *clockPanel, CGSize size, BOOL ignoresMouse) {
    NSRect r = NSMakeRect(0, 0, size.width, size.height);
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:r
                  styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    panel.level                     = (clockPanel ? clockPanel.level : NSFloatingWindowLevel) + 1;
    panel.opaque                    = NO;
    panel.backgroundColor           = [NSColor clearColor];
    panel.hasShadow                 = YES;
    panel.ignoresMouseEvents        = ignoresMouse;
    panel.becomesKeyOnlyIfNeeded    = YES;
    panel.hidesOnDeactivate         = NO;
    panel.movableByWindowBackground = NO;   // overlay clicks are controls, not drags
    panel.collectionBehavior        = NSWindowCollectionBehaviorCanJoinAllSpaces
                                    | NSWindowCollectionBehaviorStationary
                                    | NSWindowCollectionBehaviorIgnoresCycle;
    return panel;
}

NSTextField *FCCreateBannerLabel(CGFloat bannerHeight, CGFloat width, NSString *text) {
    const CGFloat labelH = 16.0;
    NSTextField *label = [[NSTextField alloc]
        initWithFrame:NSMakeRect(0, (bannerHeight - labelH) / 2.0, width, labelH)];
    label.editable         = NO;
    label.selectable       = NO;
    label.bezeled          = NO;
    label.drawsBackground  = NO;
    label.alignment        = NSTextAlignmentCenter;
    label.textColor        = [NSColor whiteColor];
    label.font             = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightBold];
    label.stringValue      = text;
    label.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    return label;
}
