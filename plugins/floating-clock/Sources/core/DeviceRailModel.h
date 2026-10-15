// Device rail model (2026-10-15) — pure, AppKit-free, unit-tested (test_device_rail).
//
// The device rail shows (a) where a watched USB device is relative to the port it docks on, read by
// the clock itself from the IOPort registry, and (b) what an external job is doing with it, read from
// a JSON status file that job writes. The plugin knows nothing about the device or the job: the
// vendor/product IDs, the label and the status-file path are preferences, and the job owns the text.
//
// Status file contract (schema v1, written atomically by the job):
//   {"v":1,"pid":123|null,"updated":<unix s>,"phase":"copy","tone":"active|ok|warn|error|idle",
//    "text":"copy 3/7","detail":"41 MB/s","progress":0.42|null,"summary":"✓ 25 on Drive · 14:31"}
//   pid set = a run is alive (a dead pid with an active tone = the job stopped mid-way).
//   Optional, additive (still v1):
//   "badge":"⛨ 26/26 proven","badge_tone":"ok"   a standing seal (e.g. integrity), shown after the
//                                                 summary at rest, and while running if not ok;
//   "steps":[["read","done"],["upload","active"],["check","todo"]]   the run's pipeline, one mark
//                                                 per step: done/active/fail/todo (skip = no mark).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FCDockState) {
    FCDockStateUnknown = 0,   // device never seen on any port yet
    FCDockStateUnplugged,     // the port it last docked on has nothing connected
    FCDockStateEmpty,         // that port is connected (dock/cable present) but the device is absent
    FCDockStateAttached,      // the device is enumerated
};

FCDockState FCDeriveDockState(BOOL devicePresent, BOOL dockPortKnown, BOOL dockPortConnected);

// Colour roles the view maps to its palette.
typedef NS_ENUM(NSInteger, FCRailRole) {
    FCRailRoleLabel = 0, FCRailRoleText, FCRailRoleDim, FCRailRoleOK, FCRailRoleActive, FCRailRoleWarn, FCRailRoleError,
    FCRailRoleName,   // the device's name after the heading (its own tint, like the heading's family)
};

@interface FCDeviceRailStatus : NSObject
@property (nonatomic) int pid;               // 0 = no run alive
@property (nonatomic) double updated;
@property (nonatomic, copy) NSString *phase;
@property (nonatomic, copy) NSString *tone;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic) double progress;       // <0 = none
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSString *badge;
@property (nonatomic, copy) NSString *badgeTone;
@property (nonatomic, copy) NSArray<NSString *> *stepStates;  // one state per step, in order
+ (nullable instancetype)statusFromJSONData:(NSData *)data;
@end

// The rail's segments: an array of @[NSString text, NSNumber role]. The header is `label` (an
// all-caps heading like NET/IN, e.g. "MIC"), then the optional `name` (the product name) and a dim `tag`
// ("TX"), mirroring the network rail's "NET Wi-Fi en0". `pidAlive` is the caller's
// kill(pid,0) check; `dockSecs` = seconds in the current dock state (<0 unknown); `spin` = frame
// counter for the activity spinner; `blip` = the device dropped and came back moments ago.
NSArray<NSArray *> *FCDeviceRailSegments(NSString *label, NSString *_Nullable name, NSString *_Nullable tag,
                                         FCDockState dock, double dockSecs, BOOL blip,
                                         FCDeviceRailStatus *_Nullable status, BOOL pidAlive,
                                         NSUInteger spin);

// The pipeline marks for `stepStates` as segments (▰ done/active/fail, ▱ todo; skip omitted).
NSArray<NSArray *> *FCStepSegments(NSArray<NSString *> *states);

// "12m", "3h05m", "2d" — compact age.
NSString *FCCompactAge(double secs);

NS_ASSUME_NONNULL_END
