#import "HotKeySpec.h"
#import <Carbon/Carbon.h>   // kVK_* and controlKey/optionKey/... constants only

static NSDictionary<NSString *, NSNumber *> *FCHotKeyKeyTable(void) {
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @"a": @(kVK_ANSI_A), @"b": @(kVK_ANSI_B), @"c": @(kVK_ANSI_C), @"d": @(kVK_ANSI_D),
            @"e": @(kVK_ANSI_E), @"f": @(kVK_ANSI_F), @"g": @(kVK_ANSI_G), @"h": @(kVK_ANSI_H),
            @"i": @(kVK_ANSI_I), @"j": @(kVK_ANSI_J), @"k": @(kVK_ANSI_K), @"l": @(kVK_ANSI_L),
            @"m": @(kVK_ANSI_M), @"n": @(kVK_ANSI_N), @"o": @(kVK_ANSI_O), @"p": @(kVK_ANSI_P),
            @"q": @(kVK_ANSI_Q), @"r": @(kVK_ANSI_R), @"s": @(kVK_ANSI_S), @"t": @(kVK_ANSI_T),
            @"u": @(kVK_ANSI_U), @"v": @(kVK_ANSI_V), @"w": @(kVK_ANSI_W), @"x": @(kVK_ANSI_X),
            @"y": @(kVK_ANSI_Y), @"z": @(kVK_ANSI_Z),
            @"0": @(kVK_ANSI_0), @"1": @(kVK_ANSI_1), @"2": @(kVK_ANSI_2), @"3": @(kVK_ANSI_3),
            @"4": @(kVK_ANSI_4), @"5": @(kVK_ANSI_5), @"6": @(kVK_ANSI_6), @"7": @(kVK_ANSI_7),
            @"8": @(kVK_ANSI_8), @"9": @(kVK_ANSI_9),
            @"f1": @(kVK_F1), @"f2": @(kVK_F2), @"f3": @(kVK_F3), @"f4": @(kVK_F4),
            @"f5": @(kVK_F5), @"f6": @(kVK_F6), @"f7": @(kVK_F7), @"f8": @(kVK_F8),
            @"f9": @(kVK_F9), @"f10": @(kVK_F10), @"f11": @(kVK_F11), @"f12": @(kVK_F12),
            @"f13": @(kVK_F13), @"f14": @(kVK_F14), @"f15": @(kVK_F15), @"f16": @(kVK_F16),
            @"f17": @(kVK_F17), @"f18": @(kVK_F18), @"f19": @(kVK_F19), @"f20": @(kVK_F20),
            @"`": @(kVK_ANSI_Grave), @"-": @(kVK_ANSI_Minus), @"=": @(kVK_ANSI_Equal),
            @"[": @(kVK_ANSI_LeftBracket), @"]": @(kVK_ANSI_RightBracket),
            @"\\": @(kVK_ANSI_Backslash), @";": @(kVK_ANSI_Semicolon), @"'": @(kVK_ANSI_Quote),
            @",": @(kVK_ANSI_Comma), @".": @(kVK_ANSI_Period), @"/": @(kVK_ANSI_Slash),
            @"space": @(kVK_Space), @"return": @(kVK_Return), @"tab": @(kVK_Tab),
            @"escape": @(kVK_Escape), @"delete": @(kVK_Delete),
            @"home": @(kVK_Home), @"end": @(kVK_End),
            @"pageup": @(kVK_PageUp), @"pagedown": @(kVK_PageDown),
            @"left": @(kVK_LeftArrow), @"right": @(kVK_RightArrow),
            @"up": @(kVK_UpArrow), @"down": @(kVK_DownArrow),
        };
    });
    return table;
}

static uint32_t FCHotKeyModifierForToken(NSString *t) {
    if ([t isEqualToString:@"ctrl"] || [t isEqualToString:@"control"]) return controlKey;
    if ([t isEqualToString:@"opt"] || [t isEqualToString:@"option"] || [t isEqualToString:@"alt"]) return optionKey;
    if ([t isEqualToString:@"shift"]) return shiftKey;
    if ([t isEqualToString:@"cmd"] || [t isEqualToString:@"command"]) return cmdKey;
    return 0;
}

// Split on '+', but a trailing "+" key ("ctrl++") is not supported: '+' is
// shift+'=' on ANSI, so spell it "shift+=".
static NSArray<NSString *> *FCHotKeyTokens(NSString *spec) {
    NSString *trimmed = [[spec stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lowercaseString];
    if (trimmed.length == 0) return nil;
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *raw in [trimmed componentsSeparatedByString:@"+"]) {
        NSString *t = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (t.length == 0) return nil;   // "ctrl++x", "+x", "x+"
        [out addObject:t];
    }
    return out;
}

BOOL FCParseHotKeySpec(NSString *spec, uint32_t *keyCode, uint32_t *carbonModifiers) {
    if (![spec isKindOfClass:[NSString class]]) return NO;
    NSArray<NSString *> *tokens = FCHotKeyTokens(spec);
    if (tokens.count == 0) return NO;
    uint32_t mods = 0;
    for (NSUInteger i = 0; i + 1 < tokens.count; i++) {
        uint32_t m = FCHotKeyModifierForToken(tokens[i]);
        if (m == 0 || (mods & m)) return NO;   // unknown or duplicate modifier
        mods |= m;
    }
    NSNumber *code = FCHotKeyKeyTable()[tokens.lastObject];
    if (!code) return NO;                      // last token must be a key
    if (keyCode) *keyCode = code.unsignedIntValue;
    if (carbonModifiers) *carbonModifiers = mods;
    return YES;
}

NSString *FCHotKeySpecDisplayString(NSString *spec) {
    uint32_t code = 0, mods = 0;
    if (!FCParseHotKeySpec(spec, &code, &mods)) return nil;
    NSMutableString *s = [NSMutableString string];
    if (mods & controlKey) [s appendString:@"⌃"];
    if (mods & optionKey)  [s appendString:@"⌥"];
    if (mods & shiftKey)   [s appendString:@"⇧"];
    if (mods & cmdKey)     [s appendString:@"⌘"];
    NSString *key = FCHotKeyTokens(spec).lastObject;
    NSDictionary *named = @{ @"space": @"Space", @"return": @"↩", @"tab": @"⇥", @"escape": @"⎋",
                             @"delete": @"⌫", @"home": @"↖", @"end": @"↘", @"pageup": @"⇞",
                             @"pagedown": @"⇟", @"left": @"←", @"right": @"→", @"up": @"↑",
                             @"down": @"↓" };
    [s appendString:named[key] ?: key.uppercaseString];
    return s;
}
