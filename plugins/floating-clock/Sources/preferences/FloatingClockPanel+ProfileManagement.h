// Category: save/load/switch/delete named preference bundles, plus the
// optional Claude Code auto-memory sync that records the currently-active
// profile to ~/.claude/projects/.../memory/floating_clock_active_profile.md.
#import "../core/FloatingClockPanel.h"

NS_ASSUME_NONNULL_BEGIN

@interface FloatingClockPanel (ProfileManagement)

- (void)activateProfile:(NSString *)name;
- (void)saveCurrentProfileAs:(id)sender;
- (void)quickSaveCurrentProfile:(id)sender;
- (void)saveAsDefaultProfile:(id)sender;
- (void)deleteProfile:(NSMenuItem *)sender;
- (void)switchToProfile:(NSMenuItem *)sender;
- (void)recordProfileActivationInCCMemory:(NSString *)profileName;

@end

NS_ASSUME_NONNULL_END
