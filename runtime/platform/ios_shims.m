/*
 * iOS: the TheosWin toolchain ships clang but no compiler-rt for Darwin, so the
 * availability builtins clang emits for @available / API_AVAILABLE are undefined
 * at link time. This is the same shim the platform probe needed; without it any
 * Objective-C file in the runtime fails to link with
 *   undefined symbol: __isPlatformVersionAtLeast
 *
 * Behaviour matches compiler-rt's for a plain (non-variant) platform check:
 * compare the requested version against the running OS.
 */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <stdint.h>
#include <stdio.h>
#include <limits.h>

static int32_t nativ_version_at_least(uint32_t major, uint32_t minor, uint32_t subminor)
{
    NSOperatingSystemVersion v;
    v.majorVersion = (NSInteger)major;
    v.minorVersion = (NSInteger)minor;
    v.patchVersion = (NSInteger)subminor;
    return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:v] ? 1 : 0;
}

int32_t __isPlatformVersionAtLeast(uint32_t platform, uint32_t major, uint32_t minor, uint32_t subminor)
{
    (void)platform; /* single-platform iOS builds only */
    return nativ_version_at_least(major, minor, subminor);
}

int32_t __isPlatformOrVariantPlatformVersionAtLeast(uint32_t platform, uint32_t major, uint32_t minor,
                                                    uint32_t subminor, uint32_t variant_platform)
{
    (void)platform;
    (void)variant_platform;
    return nativ_version_at_least(major, minor, subminor);
}

/* The app's Documents folder (with a trailing slash): the one place the Files app lets a player see and change
 * anything -- session.log, env.txt, fs/. SDL_GetPrefPath puts its folder in Library/Application Support, which
 * nothing outside the app can open. */
const char *ios_documents_dir(void)
{
    static char buf[PATH_MAX];
    if (buf[0]) return buf;
    @autoreleasepool {
        NSString *p = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        if (p.length) snprintf(buf, sizeof buf, "%s/", p.UTF8String);
    }
    return buf;
}

/* The notch and the home indicator, in *points* -- the units UIKit reports them in, and the ones the UI
 * is laid out in (ImGui draws in the window's point size; the pad in window.c mixes them with layouts in
 * points). A decade of this returning pixels pushed a phone's on-screen controls 2-3x their proper
 * distance in from every edge. Zero before a scene is connected, which is fine -- the layout is remade
 * every frame. */
void ios_safe_insets(float *top, float *bottom, float *left, float *right)
{
    *top = *bottom = *left = *right = 0.0f;
    @autoreleasepool {
        UIWindow *w = nil;
        for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *win in ((UIWindowScene *)sc).windows) {
                if (win.isKeyWindow) { w = win; break; }
            }
            if (w) break;
        }
        if (!w) w = [UIApplication sharedApplication].windows.firstObject;
        if (!w) return;
        UIEdgeInsets e = w.safeAreaInsets;
        *top = (float)e.top;
        *bottom = (float)e.bottom;
        *left = (float)e.left;
        *right = (float)e.right;
    }
}
