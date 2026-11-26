/* Decisions for repairing a settled iOS surface, independent of UIKit for host tests. */
#ifndef NATIV_IOS_VIEWPORT_H
#define NATIV_IOS_VIEWPORT_H
#include <math.h>

typedef struct { double x, y, w, h; } IosViewRect;
typedef struct {
    int allowed, frame, drawable, layout;
    double drawable_w, drawable_h;
} IosViewportPlan;

static inline IosViewportPlan ios_viewport_plan(IosViewRect target, IosViewRect current,
    double drawable_w, double drawable_h, double scale, int logical_w, int logical_h,
    int blocked)
{
    IosViewportPlan plan = {0};
    if (blocked || target.w <= 0 || target.h <= 0 || target.h > target.w || scale <= 0) return plan;
    plan.allowed = 1;
    plan.drawable_w = round(target.w * scale);
    plan.drawable_h = round(target.h * scale);
    plan.frame = fabs(current.x - target.x) > 0.01 || fabs(current.y - target.y) > 0.01 ||
        fabs(current.w - target.w) > 0.01 || fabs(current.h - target.h) > 0.01;
    plan.drawable = fabs(drawable_w - plan.drawable_w) > 0.01 || fabs(drawable_h - plan.drawable_h) > 0.01;
    /* UIKit_SetWindowSize is a no-op on iOS. A fresh UIKit layout must publish the real size
     * even when only SDL's cached logical dimensions are stale. */
    plan.layout = plan.frame || plan.drawable || logical_w != (int)round(target.w) || logical_h != (int)round(target.h);
    return plan;
}
#endif
