/* Pure layout math, shared by the runtime and the host regression tests.
 * All dimensions are UIKit/SDL window points, never drawable pixels. */
#ifndef RECOMP_TOUCHPAD_LAYOUT_H
#define RECOMP_TOUCHPAD_LAYOUT_H
#include "touchpad.h"
#include <string.h>

typedef struct {
	float w, h, scale, top, bottom, left, right;
	int on, mirror;
} TpLayoutKey;

static inline float touchpad_layout_margin(float h, float inset) {
	return h * 0.025f + (inset < h * 0.030f ? inset : h * 0.030f);
}

static inline TpVisual touchpad_build_layout(TpLayoutKey p, const uint32_t bits[8]) {
	TpVisual v;
	memset(&v, 0, sizeof v);
	v.w = p.w; v.h = p.h; v.scale = p.scale; v.on = p.on; v.mirror = p.mirror;
	if (!v.on) return v;
	const float ml = touchpad_layout_margin(p.h, p.left);
	const float mr = touchpad_layout_margin(p.h, p.right);
	const float mb = touchpad_layout_margin(p.h, p.bottom * 0.5f);
	const float mt = p.h * 0.025f + p.top;
	const float rl = p.h * 0.140f * p.scale, rb = p.h * 0.055f * p.scale;
	const float gap = rb * 2.2f;
	const float rx = p.mirror ? ml + rb + gap : p.w - mr - rb - gap;
	const float cy = p.h - mb - rb - gap;
	v.sl_x = p.mirror ? p.w - mr - rl : ml + rl;
	v.sl_y = p.h - mb - rl; v.sl_r = rl;
	v.sl_kx = v.sl_x; v.sl_ky = v.sl_y;
	v.sr_r = p.h * 0.115f * p.scale;
	v.b[0] = (TpButton){rx, cy - gap, rb, 0, 0, 0, bits[0], TP_LABEL_TRIANGLE, 0};
	v.b[1] = (TpButton){rx + gap, cy, rb, 0, 0, 0, bits[1], TP_LABEL_CIRCLE, 0};
	v.b[2] = (TpButton){rx, cy + gap, rb, 0, 0, 0, bits[2], TP_LABEL_CROSS, 0};
	v.b[3] = (TpButton){rx - gap, cy, rb, 0, 0, 0, bits[3], TP_LABEL_SQUARE, 0};
	const float sw = p.w * 0.13f, sh = p.h * 0.075f;
	float ll = p.mirror ? p.w - mr - sw : ml;
	float rr = p.mirror ? ml : p.w - mr - sw;
	/* Reserve the eye's 46-point slot plus an 8-point gap, even when mirrored. */
	if (p.mirror) rr += 54.0f; else ll += 54.0f;
	v.b[4] = (TpButton){ll + sw / 2, mt + sh / 2, 0, sw / 2, sh / 2, 1, bits[4], TP_LABEL_L, 0};
	v.b[5] = (TpButton){rr + sw / 2, mt + sh / 2, 0, sw / 2, sh / 2, 1, bits[5], TP_LABEL_R, 0};
	const float pw = p.w * 0.065f, ph = p.h * 0.058f;
	/* A 64-point Menu handle plus a gap must also fit on the smaller iPhones. */
	const float offset = pw * 1.1f > pw * 0.5f + 40 ? pw * 1.1f : pw * 0.5f + 40;
	v.b[6] = (TpButton){p.w / 2 + offset, mt + ph / 2, 0, pw / 2, ph / 2, 1, bits[6], TP_LABEL_START, 0};
	v.b[7] = (TpButton){p.w / 2 - offset, mt + ph / 2, 0, pw / 2, ph / 2, 1, bits[7], TP_LABEL_SELECT, 0};
	v.nb = 8;
	return v;
}
#endif
