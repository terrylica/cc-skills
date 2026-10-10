// ClockVisibilityToggle — hide/unhide the whole clock (2026-10-10).
//
// One switch for the clock panel AND every rail welded to it (audio, network,
// brightness, TTS, mic-mute and VPN banners), so the space the stack occupies
// can be reclaimed and given back in one keystroke.
//
// Three equivalent entry points, all funnelled into -setHidden:source:
//   1. A Carbon global hotkey, spec read once at launch from the defaults key
//      `ToggleVisibilityHotKey` (see HotKeySpec.h for the grammar; "" or
//      "none" disables it). Carbon hotkeys need no Accessibility or Input
//      Monitoring grant. Relaunch to apply a changed spec.
//   2. The context-menu item "Hide Clock".
//   3. Distributed notifications, so scripts and other tools (BTT, Karabiner
//      shell_command, Shortcuts) can drive it without knowing the hotkey:
//        <CFBundleIdentifier>.visibility.toggle | .show | .hide
//      The app binary posts these itself: `floating-clock --toggle|--show|--hide`.
//
// Visibility is deliberately NOT persisted: a relaunch (login, crash,
// reinstall) always shows the clock, so it can never stay lost.
//
// How the rails follow: each indicator's refresh treats FCClockUserHidden()
// exactly like its own "disabled" state and runs its normal hide ceremony.
// The brightness boost is left as it is while hidden — hiding is transient,
// and dimming the screen as a side effect of hiding a clock would read as a
// bug. (Hiding the brightness BAR itself, a persistent choice, still releases
// the boost — see toggleShowBrightnessBar:.)
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif
// YES while the user has hidden the clock. Cheap; read by every rail per tick.
BOOL FCClockUserHidden(void);
#ifdef __cplusplus
}
#endif

// "<CFBundleIdentifier>.visibility.<verb>" for verb toggle | show | hide.
NSString *FCVisibilityNotificationName(NSString *verb);
extern NSString *const FCToggleVisibilityHotKeyDefault;  // registered default spec

@interface FCClockVisibilityToggle : NSObject

+ (instancetype)shared;

// Wire up the panel, register the hotkey and the notification observers.
// `afterChange` runs after every state change (the panel passes its tick so
// the rails follow within the same run-loop turn, not up to 1 s later).
- (void)installWithPanel:(NSPanel *)panel afterChange:(void (^)(void))afterChange;

- (void)toggleWithSource:(NSString *)source;
- (void)setHidden:(BOOL)hidden source:(NSString *)source;

// The active hotkey in glyph form ("⌃⌥⇧⌘F19"), or nil when none is registered.
@property (nonatomic, readonly, nullable) NSString *hotKeyDisplay;

@end

// CLI side: if argv carries --toggle/--show/--hide, post the matching
// notification to the running instance and return YES (caller exits 0).
BOOL FCHandleVisibilityCommandLine(int argc, const char *_Nonnull argv[_Nonnull]);

NS_ASSUME_NONNULL_END
