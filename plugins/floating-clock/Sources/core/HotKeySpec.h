// HotKeySpec — parse and format global-hotkey specs (2026-10-10).
//
// A spec is a human-typed, `defaults write`-friendly string such as
// "ctrl+opt+shift+cmd+H": zero or more modifiers joined by '+', then exactly
// one key name. Modifier aliases: ctrl|control, opt|option|alt,
// shift, cmd|command. Key names: A-Z, 0-9, F1-F20, US-ANSI punctuation
// (` - = [ ] \ ; ' , . /), and Space/Return/Tab/Escape/Delete/Home/End/
// PageUp/PageDown/Left/Right/Up/Down. Matching is case-insensitive.
//
// Pure data layer: Foundation + HIToolbox constants only, no AppKit, so it
// links into the unit-test binary. The Carbon registration that consumes
// these values lives in ClockVisibilityToggle.m.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

// Parse `spec`. On success returns YES and writes the Carbon virtual key code
// and Carbon modifier mask (controlKey|optionKey|shiftKey|cmdKey). Returns NO
// for nil/empty specs, unknown tokens, duplicate modifiers, or a missing or
// repeated key. Outputs are untouched on failure.
BOOL FCParseHotKeySpec(NSString *_Nullable spec, uint32_t *keyCode, uint32_t *carbonModifiers);

// Glyph form for menus and logs, e.g. "⌃⌥⇧⌘F19" (Apple's canonical
// modifier order). Returns nil when the spec does not parse.
NSString *_Nullable FCHotKeySpecDisplayString(NSString *_Nullable spec);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
