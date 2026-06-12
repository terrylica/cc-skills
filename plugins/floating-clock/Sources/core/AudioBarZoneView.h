// One interactive half of the audio I/O bar (IN or OUT) — split from
// AudioStatusIndicator during the 2026-06-12 modularization. The zone OWNS
// its render state (caching, change-flash deadlines, muted tint); the
// indicator feeds it fresh HAL values once per tick and receives user
// actions back through the owner methods declared in
// AudioStatusIndicator.h.
#import <Cocoa/Cocoa.h>

@class FCAudioStatusIndicator;

// Interactive half of the bar. Hit regions, left→right:
//   [prefix+device name ........][−][level][+]
// name click → cycle device · −/+ click → step volume · scroll → fine adjust.
//
// The zone OWNS its render state (2026-06-11 extras refactor): caching,
// the change-flash deadlines, and the muted tint all live here so the
// indicator just feeds it fresh HAL values once per tick.
@interface FCAudioZoneView : NSView
@property (nonatomic, weak) FCAudioStatusIndicator *owner;
@property (nonatomic, assign) BOOL isInput;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *minusLabel;
@property (nonatomic, strong) NSTextField *levelLabel;
@property (nonatomic, strong) NSTextField *plusLabel;

// Designated initializer (declared here since the 2026-06-12 split —
// previously same-file visibility hid the missing declaration).
- (instancetype)initWithFrame:(NSRect)frame
                      isInput:(BOOL)isInput
                        owner:(FCAudioStatusIndicator *)owner;

// Apply fresh state. Internally cached — labels only redraw when the
// rendered composite (name/pct/muted/flash-phase) actually changes.
- (void)renderDevice:(NSString *)name levelPercent:(NSInteger)pct muted:(BOOL)muted;
@end
