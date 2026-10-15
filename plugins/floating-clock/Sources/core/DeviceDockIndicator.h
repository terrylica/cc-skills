// Device rail (2026-10-15) — where a watched USB device is, and what an external job is doing with it.
//
// Stack order 15: directly above the audio I/O bar. Generic and inert by default; a deployment opts in:
//
//   defaults write com.cc-skills.floating-clock DeviceRailEnabled   -bool YES
//   defaults write com.cc-skills.floating-clock DeviceRailVendorID  -int  <idVendor, decimal>
//   defaults write com.cc-skills.floating-clock DeviceRailProductID -int  <idProduct, decimal>
//   defaults write com.cc-skills.floating-clock DeviceRailLabel     -string "TX"   # short label
//   defaults write com.cc-skills.floating-clock DeviceRailStatusFile -string "~/.local/state/<job>/rail.json"
//
// Dock state comes from the IOPort registry, read in-process once a second (no subprocess, no
// polling daemon): the port the device last enumerated on is remembered (DeviceRailDockPort), so
// "device gone but that port still connected" reads as OFF DOCK, and "port not connected" as DOCK
// UNPLUGGED. Job state comes from the status file (contract in DeviceRailModel.h).
#import <Cocoa/Cocoa.h>
#import "OverlayStack.h"

@class FCAudioStatusIndicator;

NS_ASSUME_NONNULL_BEGIN

@interface FCDeviceDockIndicator : NSObject <FCStackRail>
- (instancetype)initWithClockPanel:(NSPanel *)clockPanel;
// The audio I/O bar sits directly below this rail (not a registered rail), so its slot is counted here.
@property (nonatomic, weak, nullable) FCAudioStatusIndicator *audioIndicator;
- (void)refresh;        // 1 Hz tick
- (void)syncPosition;
- (BOOL)isShowing;
@end

NS_ASSUME_NONNULL_END
