// HotKeySpec fixtures. See test_hotkey_spec.h for scope.
#import "test_hotkey_spec.h"
#import "../Sources/core/HotKeySpec.h"
#import <Carbon/Carbon.h>   // kVK_* and modifier constants (header-only use)

#define CHECK(cond, fmt, ...)                                                  \
    do {                                                                       \
        if (!(cond)) {                                                         \
            failures++;                                                        \
            NSLog(@"FAIL %s:%d " fmt, __func__, __LINE__, ##__VA_ARGS__);      \
        }                                                                      \
    } while (0)

static BOOL parses(NSString *spec, uint32_t wantCode, uint32_t wantMods) {
    uint32_t code = 0xFFFF, mods = 0xFFFF;
    return FCParseHotKeySpec(spec, &code, &mods) && code == wantCode && mods == wantMods;
}

void test_hotkey_spec_default_chord(void) {
    const uint32_t all4 = controlKey | optionKey | shiftKey | cmdKey;
    CHECK(parses(@"ctrl+opt+shift+cmd+H", kVK_ANSI_H, all4), "shipped default is the 4-modifier H chord");
    // Modifier order must not matter — people type them in any order.
    CHECK(parses(@"cmd+shift+opt+ctrl+h", kVK_ANSI_H, all4), "modifier order is free");
    CHECK(parses(@"F19", kVK_F19, 0), "a bare key is allowed");
    CHECK(parses(@"ctrl+opt+F12", kVK_F12, controlKey | optionKey), "F-keys");
    CHECK(parses(@"shift+cmd+/", kVK_ANSI_Slash, shiftKey | cmdKey), "punctuation key");
}

void test_hotkey_spec_aliases_and_case(void) {
    CHECK(parses(@"Control+Option+Command+K", kVK_ANSI_K, controlKey | optionKey | cmdKey), "long names");
    CHECK(parses(@"ctrl+alt+k", kVK_ANSI_K, controlKey | optionKey), "alt == opt");
    CHECK(parses(@"  ctrl + opt + Space ", kVK_Space, controlKey | optionKey), "whitespace tolerated");
    CHECK(parses(@"CTRL+OPT+PAGEDOWN", kVK_PageDown, controlKey | optionKey), "case-insensitive named key");
}

void test_hotkey_spec_rejects_malformed(void) {
    uint32_t code = 7, mods = 7;
    NSArray *bad = @[ @"", @"   ", @"ctrl+opt", @"ctrl+", @"+H", @"ctrl++H", @"ctrl+ctrl+H",
                      @"hyper+H", @"ctrl+opt+F21", @"ctrl+H+J", @"none", @"ctrl+opt+shift+cmd+" ];
    for (NSString *s in bad) {
        CHECK(!FCParseHotKeySpec(s, &code, &mods), "must reject '%@'", s);
    }
    CHECK(!FCParseHotKeySpec(nil, &code, &mods), "nil rejected");
    CHECK(!FCParseHotKeySpec((NSString *)(id)@42, &code, &mods), "non-string defaults value rejected");
    CHECK(code == 7 && mods == 7, "outputs untouched on failure (got %u/%u)", code, mods);
}

void test_hotkey_spec_display(void) {
    CHECK([FCHotKeySpecDisplayString(@"cmd+shift+opt+ctrl+h") isEqualToString:@"⌃⌥⇧⌘H"],
          "canonical glyph order, got %@", FCHotKeySpecDisplayString(@"cmd+shift+opt+ctrl+h"));
    CHECK([FCHotKeySpecDisplayString(@"ctrl+opt+f19") isEqualToString:@"⌃⌥F19"], "F-key display");
    CHECK([FCHotKeySpecDisplayString(@"opt+space") isEqualToString:@"⌥Space"], "named key display");
    CHECK(FCHotKeySpecDisplayString(@"ctrl+") == nil, "unparseable -> nil");
}
