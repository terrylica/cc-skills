#import "AudioDeviceSelectionMenuController.h"
#import "AudioStatusIndicator.h"
#import "BluetoothPairedAudioDeviceConnector.h"

// Connect-then-route tuning. BT baseband typically opens in 1–4s; the
// CoreAudio endpoint follows within ~2s more. Bounds chosen from the
// SwitchAudioSource-loop canon (30s ceiling there is for cold BT radios;
// 12s covers the realistic window without feeling hung).
static const NSTimeInterval kConnectTimeoutSecs = 12.0;
static const NSTimeInterval kHALPollStepSecs    = 0.5;
static const int            kHALPollMaxTries    = 16;   // 8s of polling

// Hijack-guard window: coreaudiod's auto-route of the OTHER scope usually
// lands within seconds of the BT connect, but AirPods HFP negotiation can
// take 10s+ (adversarial review 2026-06-11) — 40 × 0.5s = 20s covers the
// slow path at the cost of a few extra cheap HAL reads. Restores are capped
// so we can never livelock against a determined second writer.
static const int kGuardMaxTries    = 40;
static const int kGuardMaxRestores = 3;

static inline int FCScopeIdx(BOOL isInput) { return isInput ? 0 : 1; }

@implementation FCAudioDeviceSelectionMenuController {
    __weak FCAudioStatusIndicator *_indicator;
    // Explicit-selection generation per scope ([0]=input, [1]=output).
    // A running guard captures the generation at start and aborts the
    // moment the user makes their own choice in that scope.
    uint64_t _selGen[2];
}

- (instancetype)initWithIndicator:(FCAudioStatusIndicator *)indicator {
    if ((self = [super init])) {
        _indicator = indicator;
    }
    return self;
}

#pragma mark Menu construction

static NSMenuItem *FCHeaderItem(NSString *title) {
    NSMenuItem *h = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    h.enabled = NO;
    return h;
}

- (NSMenu *)menuForInput:(BOOL)isInput {
    FCAudioStatusIndicator *ind = _indicator;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    menu.autoenablesItems = NO;   // we manage enabled state explicitly

    [menu addItem:FCHeaderItem(isInput ? @"INPUT DEVICE" : @"OUTPUT DEVICE")];

    // ── Live CoreAudio devices: selectable immediately ──
    NSArray<NSDictionary *> *live = [ind liveDevicesForInput:isInput];
    AudioObjectID current = [ind currentDefaultDeviceForInput:isInput];
    for (NSDictionary *d in live) {
        NSString *name = d[@"name"];
        AudioObjectID devID = (AudioObjectID)[d[@"id"] unsignedIntValue];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name
                                                      action:@selector(selectLiveDevice:)
                                               keyEquivalent:@""];
        item.target = self;
        item.enabled = YES;
        item.state = (devID == current) ? NSControlStateValueOn : NSControlStateValueOff;
        item.representedObject = @{ @"id": @(devID), @"isInput": @(isInput) };
        item.toolTip = [NSString stringWithFormat:@"Switch %@ to %@ now",
                        isInput ? @"input" : @"output", name];
        [menu addItem:item];
    }
    if (live.count == 0) {
        [menu addItem:FCHeaderItem(@"(no live devices)")];
    }

    // ── Paired Bluetooth audio devices without a live endpoint here ──
    // Includes devices currently serving ANOTHER host (iPhone): selecting
    // one issues openConnection, which audio devices honor as "switch to
    // the most recent requester" — the takeover path.
    NSArray<FCBluetoothAudioDevice *> *bt =
        [FCBluetoothPairedAudioDeviceConnector pairedAudioDevices];
    NSMutableArray<FCBluetoothAudioDevice *> *offline = [NSMutableArray array];
    for (FCBluetoothAudioDevice *d in bt) {
        if ([self liveList:live containsName:d.name]) continue;  // already selectable above
        [offline addObject:d];
    }
    if (offline.count > 0) {
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:FCHeaderItem(@"BLUETOOTH — CONNECT")];
        for (FCBluetoothAudioDevice *d in offline) {
            NSString *title = [NSString stringWithFormat:@"○ %@", d.name];
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                          action:@selector(connectBluetoothDevice:)
                                                   keyEquivalent:@""];
            item.target = self;
            item.enabled = YES;
            item.representedObject = @{ @"address": d.addressString,
                                        @"name":    d.name,
                                        @"isInput": @(isInput) };
            item.toolTip = [NSString stringWithFormat:
                @"Paired but not connected to this Mac. Click to connect and "
                @"switch %@ to it — if it is currently held by another device "
                @"(e.g. an iPhone), this asks it to come over here.",
                isInput ? @"input" : @"output"];
            [menu addItem:item];
        }
    }
    return menu;
}

// CoreAudio names and BT names usually match exactly; nicknamed AirPods can
// differ by suffixes, so accept containment either way (case-insensitive).
- (BOOL)liveList:(NSArray<NSDictionary *> *)live containsName:(NSString *)btName {
    for (NSDictionary *d in live) {
        NSString *liveName = d[@"name"];
        if ([liveName caseInsensitiveCompare:btName] == NSOrderedSame) return YES;
        if ([liveName rangeOfString:btName options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
        if ([btName rangeOfString:liveName options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

#pragma mark Actions

- (void)noteExplicitDeviceSelectionForInput:(BOOL)isInput {
    _selGen[FCScopeIdx(isInput)]++;
}

- (void)selectLiveDevice:(NSMenuItem *)item {
    NSDictionary *info = item.representedObject;
    BOOL isInput = [info[@"isInput"] boolValue];
    [self noteExplicitDeviceSelectionForInput:isInput];   // cancels any guard here
    [_indicator selectDeviceID:(AudioObjectID)[info[@"id"] unsignedIntValue]
                      forInput:isInput];
}

- (void)connectBluetoothDevice:(NSMenuItem *)item {
    NSDictionary *info = item.representedObject;
    NSString *address = info[@"address"];
    NSString *name    = info[@"name"];
    BOOL isInput      = [info[@"isInput"] boolValue];
    FCAudioStatusIndicator *ind = _indicator;
    [self noteExplicitDeviceSelectionForInput:isInput];

    // Scope-independence snapshot (2026-06-11 fix): capture the OTHER
    // scope's default BEFORE the connect, because coreaudiod auto-routes it
    // to a Bluetooth device the moment the baseband link opens. The guard
    // below restores it if (and only if) the connected device hijacked it.
    BOOL otherIsInput = !isInput;
    AudioObjectID otherBefore = [ind currentDefaultDeviceForInput:otherIsInput];
    NSString *otherBeforeName = [self nameOfLiveDevice:otherBefore forInput:otherIsInput];

    // ⏳ in the zone while the baseband + HAL settle.
    [ind setTransientStatus:[NSString stringWithFormat:@"⏳ %@…", name]
                   forInput:isInput
                    seconds:kConnectTimeoutSecs + kHALPollMaxTries * kHALPollStepSecs];

    __weak typeof(self) weakSelf = self;
    [FCBluetoothPairedAudioDeviceConnector
        connectDeviceWithAddress:address
                         timeout:kConnectTimeoutSecs
                      completion:^(BOOL success, NSString *failureReason) {
        typeof(self) self_ = weakSelf;
        if (!self_) return;
        if (!success) {
            [self_ showFailure:name reason:failureReason forInput:isInput];
            return;
        }
        // Baseband is up. Two parallel 0.5s loops:
        //   1. wait for the TARGET scope's endpoint and route to it;
        //   2. guard the OTHER scope against the auto-route hijack —
        //      runs regardless of whether (1) succeeds, because the hijack
        //      happens at connect time, not at our routing time.
        [self_ pollHALForDeviceNamed:name forInput:isInput remainingTries:kHALPollMaxTries];
        BOOL otherWasAlreadyThisDevice =
            otherBeforeName && [self_ name:otherBeforeName matchesName:name];
        if (otherBefore != 0 && !otherWasAlreadyThisDevice) {
            [self_ guardScope:otherIsInput
               previousDevice:otherBefore
                connectedName:name
                   generation:self_->_selGen[FCScopeIdx(otherIsInput)]
                     restores:0
               remainingTries:kGuardMaxTries];
        }
    }];
}

#pragma mark Other-scope hijack guard (2026-06-11 independence fix)

- (void)guardScope:(BOOL)otherIsInput
    previousDevice:(AudioObjectID)before
     connectedName:(NSString *)connectedName
        generation:(uint64_t)gen
          restores:(int)restores
    remainingTries:(int)remaining {
    FCAudioStatusIndicator *ind = _indicator;
    if (!ind || remaining <= 0) return;
    // User made an explicit choice in this scope — their call, stand down.
    if (_selGen[FCScopeIdx(otherIsInput)] != gen) return;

    AudioObjectID cur = [ind currentDefaultDeviceForInput:otherIsInput];
    // NOTE: hijack detection keys on the ID changing (cur != before) FIRST,
    // then the name match — so a same-named different-ID endpoint (AirPods
    // are TWO HAL devices with one name) is still correctly restored.
    if (cur != before && cur != 0) {
        NSString *curName = [self nameOfLiveDevice:cur forInput:otherIsInput];
        if (curName && [self name:curName matchesName:connectedName]) {
            // coreaudiod auto-routed this scope to the device we just
            // connected — undo it. The user asked for the OTHER scope only.
            if (restores >= kGuardMaxRestores) {
                // It keeps coming back — stop fighting, but SAY so instead
                // of leaving a silently-wrong device (review 2026-06-11).
                [ind setTransientStatus:@"✗ macOS keeps re-routing"
                               forInput:otherIsInput
                                seconds:4.0];
                return;
            }
            // HAL IDs are reassigned when devices vanish; a stale restore
            // target would silently no-op (review 2026-06-11). Existence is
            // probed across ALL devices — virtual included — because the
            // pre-connect default may legitimately be a virtual transport
            // (Background Music, Lark loopback): we restore the user's
            // ACTUAL prior state; the cycle ring's virtual exclusion only
            // governs what we OFFER, not what we restore.
            if (![ind deviceIDStillExists:before]) return;
            NSLog(@"[audio-bar] guard: restoring %@ default (hijacked by '%@')",
                  otherIsInput ? @"input" : @"output", curName);
            [ind selectDeviceID:before forInput:otherIsInput];
            // Visible ↩ cue — without it the zone silently snaps back and
            // reads as a glitch (review 2026-06-11).
            NSString *restoredName = [self nameOfLiveDevice:before forInput:otherIsInput];
            [ind setTransientStatus:[NSString stringWithFormat:@"↩ %@", restoredName ?: @"restored"]
                           forInput:otherIsInput
                            seconds:2.5];
            restores++;
        } else {
            // Changed to something unrelated (user, app, device unplug) —
            // not our hijack; never fight it.
            return;
        }
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kHALPollStepSecs * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) self_ = weakSelf;
        if (!self_) return;   // app teardown mid-guard — nothing to protect
        [self_ guardScope:otherIsInput
           previousDevice:before
            connectedName:connectedName
               generation:gen
                 restores:restores
           remainingTries:remaining - 1];
    });
}

// Name of a live HAL device in scope, or nil. (Guard needs id → name.)
- (NSString *)nameOfLiveDevice:(AudioObjectID)devID forInput:(BOOL)isInput {
    if (devID == 0) return nil;
    for (NSDictionary *d in [_indicator liveDevicesForInput:isInput]) {
        if ([d[@"id"] unsignedIntValue] == devID) return d[@"name"];
    }
    return nil;
}

// Same containment-tolerant match the HAL poll uses (BT names vs HAL names).
- (BOOL)name:(NSString *)a matchesName:(NSString *)b {
    if (!a.length || !b.length) return NO;
    if ([a caseInsensitiveCompare:b] == NSOrderedSame) return YES;
    if ([a rangeOfString:b options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    if ([b rangeOfString:a options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

#pragma mark Connect → HAL appearance → route

- (void)pollHALForDeviceNamed:(NSString *)name
                     forInput:(BOOL)isInput
               remainingTries:(int)remaining {
    FCAudioStatusIndicator *ind = _indicator;
    if (!ind) return;
    AudioObjectID dev = [ind liveDeviceIDMatchingName:name forInput:isInput];
    if (dev != 0) {
        [ind setTransientStatus:nil forInput:isInput seconds:0];
        [ind selectDeviceID:dev forInput:isInput];
        return;
    }
    if (remaining <= 0) {
        // Connected at the BT layer but no endpoint in this scope. Honest
        // failure beats silent success: e.g. a speaker picked in the INPUT
        // menu, or macOS still negotiating profiles.
        [self showFailure:name reason:@"no audio endpoint appeared" forInput:isInput];
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kHALPollStepSecs * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [weakSelf pollHALForDeviceNamed:name forInput:isInput remainingTries:remaining - 1];
    });
}

- (void)showFailure:(NSString *)name reason:(NSString *)reason forInput:(BOOL)isInput {
    NSLog(@"[audio-bar] BT connect '%@' failed: %@", name, reason);
    [_indicator setTransientStatus:[NSString stringWithFormat:@"✗ %@", name]
                          forInput:isInput
                           seconds:3.0];
}

@end
