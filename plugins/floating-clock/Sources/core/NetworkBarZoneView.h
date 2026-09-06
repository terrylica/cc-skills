// The single interactive zone of the network picker bar.
//
// Mirrors FCAudioZoneView's contract: the zone OWNS its render state
// (caching + change flash), the indicator feeds it a fresh value once per
// tick, and user actions travel back through the owner. Unlike the audio bar
// there is only ONE zone — a machine has one default route, not an
// independent in/out pair.
#import <Cocoa/Cocoa.h>

@class FCNetworkStatusIndicator;

NS_ASSUME_NONNULL_BEGIN

// Layout: [NET  service name  device ....  addr  ↓rate ↑rate  signal]
//          \____ left, identity ____/        \__ right, telemetry __/
//
// The BSD device (en0, en13, …) sits immediately after the service name, in a
// dimmed weight. The friendly name alone is ambiguous — two adapters can carry
// similar names, and every diagnostic tool the user reaches for next
// (ifconfig, route, tcpdump, the scan scripts) is keyed by the BSD name, not
// the service name. The right-click menu already pairs the two; showing the
// same pair on the bar means the answer is there without opening the menu.
//
// Two labels rather than one: the service name is the anchor and stays hard
// left, while the telemetry group is right-aligned so its fields do not slide
// around horizontally as the name changes length. That mirrors the audio bar,
// where the device name is left and the controls are pinned right.
//
// left-click  → cycle to the next switchable service
// right-click → pull-out service menu (via -menuForEvent:)
@interface FCNetworkZoneView : NSView

@property (nonatomic, weak) FCNetworkStatusIndicator *owner;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *statsLabel;

- (instancetype)initWithFrame:(NSRect)frame owner:(FCNetworkStatusIndicator *)owner;

// Apply fresh state. Internally cached — labels only redraw when the rendered
// composite actually changes, keeping the 1 Hz tick allocation-free at steady
// state. `degraded` renders the amber/red treatment used for a failed switch
// or an unknown primary interface. `stats` is the pre-composed telemetry run,
// or nil to leave the right side empty.
//
// `device` is the BSD name; pass nil when unknown. It is suppressed when it
// equals `name`, which happens on the degraded path where the raw device IS
// the label — printing "en13 en13" would look like a bug.
- (void)renderService:(nullable NSString *)name
               device:(nullable NSString *)device
             degraded:(BOOL)degraded
                stats:(nullable NSAttributedString *)stats;

// Natural width of the CURRENT content, so the indicator can publish a width
// need to the overlay consensus. Measured from the live attributed strings, so
// it always matches what is actually drawn.
- (CGFloat)naturalContentWidth;

@end

NS_ASSUME_NONNULL_END
