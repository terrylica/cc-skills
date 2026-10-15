// Level-meter + device-rail fixtures. See test_level_meter.h for scope.
#import "test_level_meter.h"
#import "../Sources/core/LevelMeterMath.h"
#import "../Sources/core/DeviceRailModel.h"
#import <math.h>

#define CHECK(cond, fmt, ...)                                                  \
    do {                                                                       \
        if (!(cond)) {                                                         \
            failures++;                                                        \
            NSLog(@"FAIL %s:%d " fmt, __func__, __LINE__, ##__VA_ARGS__);      \
        }                                                                      \
    } while (0)

#define CHECK_CLOSE(got, want, label)                                          \
    CHECK(fabs((got) - (want)) <= 1e-6, "%@: got %.6f want %.6f", label, (double)(got), (double)(want))

static NSString *FCJoin(NSArray<NSArray *> *segs) {
    NSMutableString *s = [NSMutableString string];
    for (NSArray *seg in segs) [s appendString:seg[0]];
    return s;
}

void test_level_meter_db_mapping(void) {
    CHECK_CLOSE(FCLinearToDb(1.0), 0.0, @"full scale = 0 dBFS");
    CHECK_CLOSE(FCLinearToDb(0.1), -20.0, @"0.1 = -20 dBFS");
    CHECK_CLOSE(FCLinearToDb(0.0), FCMeterFloorDb, @"silence -> floor");
    CHECK_CLOSE(FCLinearToDb(NAN), FCMeterFloorDb, @"NaN -> floor");
    CHECK_CLOSE(FCLinearToDb(4e-4), FCMeterFloorDb, @"quiet-room floor (~-68 dB) reads as silence");
    CHECK_CLOSE(FCLinearToDb(2.0), 0.0, @"over full scale clamps to 0");
    CHECK_CLOSE(FCDbToFraction(-60.0), 0.0, @"floor -> empty");
    CHECK_CLOSE(FCDbToFraction(-30.0), 0.5, @"-30 dB -> half");
    CHECK_CLOSE(FCDbToFraction(-12.0), 0.8, @"-12 dB -> amber boundary 0.8");
    CHECK_CLOSE(FCDbToFraction(3.0), 1.0, @"above 0 -> full");
}

void test_level_meter_ballistics(void) {
    FCMeterState s; FCMeterReset(&s);
    FCMeterStep(&s, -6.0, 0.033);
    CHECK_CLOSE(s.levelDb, -6.0, @"instant attack");
    CHECK_CLOSE(s.peakDb, -6.0, @"peak follows the attack");
    FCMeterStep(&s, -60.0, 0.5);
    CHECK_CLOSE(s.levelDb, -6.0 - 12.0, @"release 24 dB/s for 0.5 s");
    CHECK_CLOSE(s.peakDb, -6.0, @"peak holds during the hold window");
    FCMeterStep(&s, -60.0, 0.6);            // hold expires (1.1 s total)
    FCMeterStep(&s, -60.0, 0.5);            // now the marker falls
    CHECK(s.peakDb < -6.0, "peak falls after hold, got %.2f", s.peakDb);
    CHECK(s.peakDb >= s.levelDb, "marker never below the bar (%.2f vs %.2f)", s.peakDb, s.levelDb);
    for (int i = 0; i < 100; i++) FCMeterStep(&s, -90.0, 0.1);
    CHECK_CLOSE(s.levelDb, FCMeterFloorDb, @"settles at the floor");
    CHECK_CLOSE(s.peakDb, FCMeterFloorDb, @"marker settles at the floor");
}

void test_level_meter_eighth_bar(void) {
    CHECK([FCEighthBlockBar(0.0, 4, @"░") isEqualToString:@"░░░░"], "empty bar");
    CHECK([FCEighthBlockBar(1.0, 4, @"░") isEqualToString:@"████"], "full bar");
    CHECK([FCEighthBlockBar(0.5, 4, @"░") isEqualToString:@"██░░"], "half bar");
    CHECK([FCEighthBlockBar(1.0 / 32.0, 4, @"░") isEqualToString:@"▏░░░"], "one eighth of a cell");
    CHECK([FCEighthBlockBar(0.47, 10, @"░") length] == 10, "constant width");
    CHECK([FCEighthBlockBar(7.0, 3, @"░") isEqualToString:@"███"], "clamped above 1");
}

void test_device_rail_dock_state(void) {
    CHECK(FCDeriveDockState(YES, NO, NO) == FCDockStateAttached, "present wins");
    CHECK(FCDeriveDockState(NO, NO, YES) == FCDockStateUnknown, "never seen -> unknown");
    CHECK(FCDeriveDockState(NO, YES, YES) == FCDockStateEmpty, "dock connected, device absent -> off dock");
    CHECK(FCDeriveDockState(NO, YES, NO) == FCDockStateUnplugged, "dock port dark -> unplugged");
    CHECK([FCCompactAge(42) isEqualToString:@"42s"], "seconds");
    CHECK([FCCompactAge(12 * 60 + 5) isEqualToString:@"12m"], "minutes");
    CHECK([FCCompactAge(3 * 3600 + 5 * 60) isEqualToString:@"3h05m"], "hours");
    CHECK([FCCompactAge(-1) isEqualToString:@""], "unknown -> empty");
}

void test_device_rail_status_parse(void) {
    NSData *ok = [@"{\"v\":1,\"pid\":42,\"updated\":1.5,\"phase\":\"copy\",\"tone\":\"active\",\"text\":\"copy 3/7\","
                  "\"detail\":\"41 MB/s\",\"progress\":0.42,\"summary\":\"✓ 25 on Drive · 14:31\"}" dataUsingEncoding:NSUTF8StringEncoding];
    FCDeviceRailStatus *s = [FCDeviceRailStatus statusFromJSONData:ok];
    CHECK(s && s.pid == 42 && [s.text isEqualToString:@"copy 3/7"], "parses a full record");
    CHECK_CLOSE(s.progress, 0.42, @"progress");
    FCDeviceRailStatus *n = [FCDeviceRailStatus statusFromJSONData:[@"{\"v\":1,\"pid\":null,\"progress\":null,\"tone\":\"idle\"}" dataUsingEncoding:NSUTF8StringEncoding]];
    CHECK(n && n.pid == 0 && n.progress < 0, "nulls -> no pid, no progress");
    CHECK(![FCDeviceRailStatus statusFromJSONData:[@"{\"v\":2}" dataUsingEncoding:NSUTF8StringEncoding]], "unknown schema rejected");
    CHECK(![FCDeviceRailStatus statusFromJSONData:[@"not json" dataUsingEncoding:NSUTF8StringEncoding]], "garbage rejected");
    CHECK(![FCDeviceRailStatus statusFromJSONData:[NSData data]], "empty rejected");
}

void test_device_rail_segments(void) {
    FCDeviceRailStatus *run = [FCDeviceRailStatus statusFromJSONData:[@"{\"v\":1,\"pid\":42,\"phase\":\"copy\",\"tone\":\"active\","
        "\"text\":\"copy 3/7\",\"detail\":\"41 MB/s\",\"progress\":0.5,\"summary\":\"✓ 25 on Drive · 14:31\"}" dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *active = FCJoin(FCDeviceRailSegments(@"TX", nil, nil, FCDockStateAttached, 750, NO, run, YES, 2));
    CHECK([active hasPrefix:@"TX ● docked 12m"], "dock part: %@", active);
    CHECK([active containsString:@"◑ copy 3/7 █████░░░░░  50% · 41 MB/s"], "active line: %@", active);

    NSString *dead = FCJoin(FCDeviceRailSegments(@"TX", nil, nil, FCDockStateAttached, 10, NO, run, NO, 0));
    CHECK([dead containsString:@"⚠ stopped during copy"], "dead pid while active: %@", dead);

    FCDeviceRailStatus *rest = [FCDeviceRailStatus statusFromJSONData:[@"{\"v\":1,\"pid\":null,\"phase\":\"idle\",\"tone\":\"idle\","
        "\"text\":\"up to date\",\"progress\":null,\"summary\":\"✓ 25 on Drive · 14:31\"}" dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *idle = FCJoin(FCDeviceRailSegments(@"TX", nil, nil, FCDockStateEmpty, 200, NO, rest, NO, 0));
    CHECK([idle isEqualToString:@"TX ◌ off dock 3m  │ ✓ 25 on Drive · 14:31"], "resting off dock: %@", idle);

    FCDeviceRailStatus *off = [FCDeviceRailStatus statusFromJSONData:[@"{\"v\":1,\"pid\":null,\"phase\":\"deferred\",\"tone\":\"warn\","
        "\"text\":\"offline · 3 waiting\",\"summary\":\"✓ 25 on Drive · 14:31\"}" dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *def = FCJoin(FCDeviceRailSegments(@"TX", nil, nil, FCDockStateUnplugged, -1, NO, off, NO, 0));
    CHECK([def isEqualToString:@"TX ○ dock unplugged  │ offline · 3 waiting · ✓ 25 on Drive · 14:31"], "deferred: %@", def);

    NSString *blip = FCJoin(FCDeviceRailSegments(@"TX", nil, nil, FCDockStateAttached, 5, YES, nil, NO, 0));
    CHECK([blip isEqualToString:@"TX ↻ docked 5s"], "blip, no status file: %@", blip);
}

void test_device_rail_steps_and_badge(void) {
    FCDeviceRailStatus *run = [FCDeviceRailStatus statusFromJSONData:[@"{\"v\":1,\"pid\":7,\"phase\":\"check\",\"tone\":\"active\","
        "\"text\":\"checking Drive\",\"summary\":\"✓ 26 on Drive\",\"badge\":\"⛨ 26/26 proven\",\"badge_tone\":\"ok\","
        "\"steps\":[[\"read\",\"done\"],[\"reread\",\"skip\"],[\"upload\",\"done\"],[\"check\",\"active\"],[\"seal\",\"todo\"]]}" dataUsingEncoding:NSUTF8StringEncoding]];
    CHECK(run.stepStates.count == 5, "five steps parsed");
    NSArray *marks = FCStepSegments(run.stepStates);
    CHECK(marks.count == 4, "skip draws no mark");
    CHECK([FCJoin(marks) isEqualToString:@"▰▰▰▱"], "marks: %@", FCJoin(marks));
    CHECK([marks[2][1] integerValue] == FCRailRoleActive && [marks[3][1] integerValue] == FCRailRoleDim, "roles");
    NSString *active = FCJoin(FCDeviceRailSegments(@"TX", nil, nil, FCDockStateAttached, -1, NO, run, YES, 0));
    CHECK([active isEqualToString:@"TX ● docked  │ ◐ ▰▰▰▱ checking Drive"], "ok badge hidden mid-run: %@", active);

    FCDeviceRailStatus *rest = [FCDeviceRailStatus statusFromJSONData:[@"{\"v\":1,\"pid\":null,\"tone\":\"idle\",\"text\":\"up to date\","
        "\"summary\":\"✓ 26 on Drive · 16:20\",\"badge\":\"⛨ 26/26 proven\",\"badge_tone\":\"ok\"}" dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *idle = FCJoin(FCDeviceRailSegments(@"TX", nil, nil, FCDockStateEmpty, -1, NO, rest, NO, 0));
    CHECK([idle isEqualToString:@"TX ◌ off dock  │ ✓ 26 on Drive · 16:20 · ⛨ 26/26 proven"], "badge at rest: %@", idle);

    FCDeviceRailStatus *bad = [FCDeviceRailStatus statusFromJSONData:[@"{\"v\":1,\"pid\":9,\"tone\":\"active\",\"text\":\"audit 1/2\","
        "\"badge\":\"⛨ ✗ 1 corrupt\",\"badge_tone\":\"error\"}" dataUsingEncoding:NSUTF8StringEncoding]];
    NSArray *segs = FCDeviceRailSegments(@"TX", nil, nil, FCDockStateAttached, -1, NO, bad, YES, 1);
    CHECK([FCJoin(segs) hasSuffix:@"audit 1/2 · ⛨ ✗ 1 corrupt"], "error badge shown mid-run: %@", FCJoin(segs));
    CHECK([[segs lastObject][1] integerValue] == FCRailRoleError, "error role");

    // Heading + name + dim tag, like "NET Wi-Fi en0".
    NSArray *named = FCDeviceRailSegments(@"MIC", @"Pocket", @"TX", FCDockStateAttached, -1, NO, nil, NO, 0);
    CHECK([FCJoin(named) isEqualToString:@"MIC Pocket TX ● docked"], "header: %@", FCJoin(named));
    CHECK([named[0][1] integerValue] == FCRailRoleLabel && [named[1][1] integerValue] == FCRailRoleName
          && [named[2][1] integerValue] == FCRailRoleDim, "header roles");
}
