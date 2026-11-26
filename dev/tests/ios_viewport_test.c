/* cc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined ios_viewport_test.c -lm -o /tmp/ios-viewport-test */
#include <assert.h>
#include <stdio.h>
#include "../../runtime/platform/ios_viewport.h"

int main(void) {
    const IosViewRect landscape = {0, 0, 932, 430};
    const IosViewRect portrait = {0, 0, 430, 932};
    IosViewportPlan p = ios_viewport_plan(landscape, landscape, 2796, 1290, 3, 932, 430, 0);
    assert(p.allowed && !p.frame && !p.drawable && !p.layout);

    p = ios_viewport_plan(landscape, portrait, 1290, 2796, 3, 430, 932, 0);
    assert(p.allowed && p.frame && p.drawable && p.layout);
    assert(p.drawable_w == 2796 && p.drawable_h == 1290);

    p = ios_viewport_plan(landscape, landscape, 2796, 1290, 3, 430, 932, 0);
    assert(p.allowed && !p.frame && !p.drawable && p.layout); /* logical-size-only corruption */

    p = ios_viewport_plan(landscape, landscape, 1290, 2796, 3, 932, 430, 0);
    assert(p.allowed && !p.frame && p.drawable && p.layout); /* drawable-only corruption */

    const IosViewRect keyboard = {0, -170, 932, 430};
    p = ios_viewport_plan(landscape, keyboard, 2796, 1290, 3, 932, 430, 1);
    assert(!p.allowed && !p.frame && !p.drawable && !p.layout); /* SDL deliberately moves the input above the keyboard */

    /* Rotation, presentation and inactive-window guards all defer work until UIKit settles. */
    for (int guard = 1; guard <= 4; guard++) {
        p = ios_viewport_plan(landscape, portrait, 1290, 2796, 3, 430, 932, guard);
        assert(!p.allowed && !p.layout);
    }
    p = ios_viewport_plan(portrait, portrait, 1290, 2796, 3, 430, 932, 0);
    assert(!p.allowed);

    const IosViewRect phone11 = {0, 0, 896, 414};
    p = ios_viewport_plan(phone11, portrait, 0, 0, 2, 430, 932, 0);
    assert(p.drawable_w == 1792 && p.drawable_h == 828 && p.frame && p.layout);
    puts("PASS: healthy, portrait, logical-only, drawable-only, keyboard/transition deferral and 2x/3x viewport recovery");
    return 0;
}
