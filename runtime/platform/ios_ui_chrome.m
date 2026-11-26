/* UIKit chrome above SDL's final Metal view. All view/layout/input mutation is main-thread
 * only. No raw layer is attached to the UIWindow and no game thread calls UIKit. */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <Metal/Metal.h>
#include <stdlib.h>
#include <math.h>
#include "../ui/touchpad.h"   /* runtime/ui/touchpad.h: the one true layout -- tp_layout's own TpVisual */

/* the game's own (window.c / overlay.cpp) */
extern int  touchpad_on(void); extern void touchpad_set_on(int on);   /* (touchpad.h has the layout structs; these two here read as actions) */
extern void overlay_toast_titled(const char *title, const char *body, double seconds);
extern void overlay_bar_open(void);
extern int  overlay_is_open(void);
extern int overlay_native_settings_wanted(void);
extern int overlay_native_settings_page(void);
extern int  overlay_owns_point(float x, float y);
extern int  overlay_pad_hidden(void);   /* overlay.cpp: the bar/menus/a dialog over the picture -- the pad draws no pixels then */
extern void touchpad_native_press(int which);    /* window.c: the same state a finger on the glass would set */
extern void touchpad_native_release(int which);
void ios_ui_haptic(int kind);                    /* this file's own: 0 light, 1 medium, 2 soft */
/* the bar's handles (window.c / overlay.cpp / settings): every row's action the same one the ImGui row took */
extern int  touchpad_scale(void); extern void touchpad_set_scale(int percent);
extern int  touchpad_mirror(void); extern void touchpad_set_mirror(int on);   /* touchpad.h has these too; the externs keep the list in one place */
extern int  window_touchpad_rstick(void);
extern int  settings_int(const char *key, int dflt);
extern void settings_set_int(const char *key, int value);
extern void settings_save(void);
extern int  gfx_gpu_render_scale_max(void); extern int gfx_gpu_render_scale_wanted(void); extern void gfx_gpu_render_scale_request(int n);
extern int  overlay_game_paused(void); extern void overlay_set_paused(int on); extern void overlay_open(void);
extern float overlay_volume(void); extern void overlay_set_volume(float v);
extern int  overlay_frame_rate_wanted(void); extern void overlay_frame_rate_request(int fr); extern int overlay_frame_rate_offered(void);
extern void overlay_request_quit(void);
extern int overlay_quit_confirm(void);
extern int  overlay_stats_level(void); extern void overlay_set_stats(int level);
extern void overlay_show_controls_page(void);
/* Step 39: the settings center, the OSD, the pause card, the intro strip (overlay.cpp's own handles) */
extern void overlay_close(void);
extern int  overlay_intro_up(void); extern void overlay_intro_dismiss(void);
extern int  overlay_osd_lines(char lines[][40], int max);
extern double overlay_fps(void);
extern int  overlay_game_has(const char *k); extern int overlay_capable(const char *k);
extern float overlay_opt_get(const char *k); extern void overlay_opt_set(const char *k, float v);
extern int  overlay_lang_count(void); extern const char *overlay_lang_label(int i);
extern int  overlay_lang_get(void); extern void overlay_lang_set(int i);
extern int  overlay_controls_count(void); extern void overlay_controls_row(int i, const char **action, const char **pad);
extern int  overlay_gyro_present(void); extern int overlay_gyro_get(void); extern void overlay_gyro_set(int on);
extern int  overlay_gyro_pose_get(void); extern void overlay_gyro_pose_set(int flat);
extern void overlay_gyro_recentre(void);
extern int  window_touch_contacts(int port, int *keys, int *xs, int *ys, int max);
extern double settings_float(const char *key, double dflt); extern void settings_set_float(const char *key, double value);
extern const char *settings_str(const char *key, const char *dflt, char *buf, int bufsize);
extern void settings_set_str(const char *key, const char *value);

static UIWindow      *g_win;
static UIView        *g_host;        /* pass-through window child above SDL's final root view */
static UIButton     *g_eye;          /* owned by the window (installed once, never removed) */
static UIButton     *g_pull_pill;    /* the top-centre handle: a tap brings the strip down (a swipe belongs to iOS's own top edge) */
static UIView       *g_toast_host;   /* the corner the toasts stack into, owned the same way */
static UIStackView  *g_toast_stack;  /* the toasts, newest on top, the oldest past three */
static int           g_installed;    /* ios_ui_chrome_install ran: everything's in place */
static int           g_eye_on = -1;  /* what the eye last drew: the menu's toggle must reach it too */
static int           g_pad_disabled;      /* RECOMP_NATIVE_PAD=0: the native pad stands down (the ImGui pad draws, the finger path owns the taps) */

/* while the chrome is installed this is the pad's own word: overlay.cpp gates pad_draw on it, so
 * a disabled native pad is the *whole* ImGui pad exactly as before, not a blank screen */
int ios_ui_chrome_pad_on(void) { return g_installed && !g_pad_disabled; }

int ios_ui_chrome_active(void) { return g_installed; }

/* the session log tells the story of a phone from a thousand miles away: every state flip and
 * every tap of the chrome says itself here, stderr into the same log the game writes */
static void chrome_log(const char *fmt, ...) {
	va_list ap; va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	fputc('\n', stderr);
	va_end(ap);
}
static double chrome_now(void) { return CACurrentMediaTime(); }
static UIColor *rgba(int r, int g, int b, float a);   /* defined below the pad section: the glyphs ask for it first */
static UIVisualEffectView *blur_fill(UIView *host, UIBlurEffectStyle st);   /* the frosted material (the settings center defines it) */

/* A transparent container whose empty areas never swallow SDL/game touches. */
@interface ChromeHost : UIView
@end
@implementation ChromeHost
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:p withEvent:event];
    return hit == self ? nil : hit;
}
@end

/* The artwork can stay modest while the button remains a 44-point touch target. */
@interface ChromeButton : UIButton
@end
@implementation ChromeButton
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)event {
    (void)event;
    const CGFloat dx = fmax(0, (44 - self.bounds.size.width) / 2);
    const CGFloat dy = fmax(0, (44 - self.bounds.size.height) / 2);
    return CGRectContainsPoint(CGRectInset(self.bounds, -dx, -dy), p);
}
@end

static CGRect chrome_safe_rect(void) {
    return UIEdgeInsetsInsetRect(g_host.bounds, g_win.safeAreaInsets);
}
static void chrome_layout(void);

/* ---- the eye ---------------------------------------------------------------------------- */
/* Small vector glyphs rendered into images; their visibility comes from correct view ordering. */
static UIImage *glyph(NSString *kind, CGFloat w, CGFloat h, UIColor *stroke) {
	UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(w, h)];
	UIImage *im = [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
		CGContextRef c = rc.CGContext;
		CGContextSetStrokeColorWithColor(c, stroke.CGColor);
		CGContextSetFillColorWithColor(c, stroke.CGColor);
		CGContextSetLineWidth(c, 1.8f);
		CGContextSetLineCap(c, kCGLineCapRound);
		CGContextSetLineJoin(c, kCGLineJoinRound);
		if ([kind isEqualToString:@"eye"] || [kind isEqualToString:@"eye.slash"]) {
			UIBezierPath *p = [UIBezierPath bezierPath];
			[p moveToPoint:CGPointMake(1.5f, h * 0.5f)];
			[p addQuadCurveToPoint:CGPointMake(w - 1.5f, h * 0.5f) controlPoint:CGPointMake(w * 0.5f, -h * 0.30f)];
			[p addQuadCurveToPoint:CGPointMake(1.5f, h * 0.5f) controlPoint:CGPointMake(w * 0.5f, h * 1.30f)];
			[p stroke];
			[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(w * 0.5f - 2.6f, h * 0.5f - 2.6f, 5.2f, 5.2f)] fill];
			if ([kind isEqualToString:@"eye.slash"]) {
				UIBezierPath *s = [UIBezierPath bezierPath];
				[s moveToPoint:CGPointMake(1.0f, h - 1.0f)];
				[s addLineToPoint:CGPointMake(w - 1.0f, 1.0f)];
				[s stroke];
			}
		} else if ([kind isEqualToString:@"chevron"]) {
			UIBezierPath *p = [UIBezierPath bezierPath];
			[p moveToPoint:CGPointMake(w * 0.26f, h * 0.40f)];
			[p addLineToPoint:CGPointMake(w * 0.5f, h * 0.66f)];
			[p addLineToPoint:CGPointMake(w * 0.74f, h * 0.40f)];
			[p stroke];
		} else if ([kind isEqualToString:@"check"]) {   /* a checkmark */
			UIBezierPath *p = [UIBezierPath bezierPath];
			[p moveToPoint:CGPointMake(w * 0.18f, h * 0.54f)];
			[p addLineToPoint:CGPointMake(w * 0.42f, h * 0.80f)];
			[p addLineToPoint:CGPointMake(w * 0.84f, h * 0.20f)];
			[p stroke];
		}
	}];
	[r release];
	return im;
}
static void eye_look(void) {
	const int on = touchpad_on();
	if (on == g_eye_on) return;
	g_eye_on = on;
	UIImage *img = glyph(on ? @"eye" : @"eye.slash", 24.0f, 15.0f,
	                      on ? rgba(235, 240, 255, 0.92f) : rgba(160, 166, 180, 0.85f));
	[g_eye setImage:[img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
    g_eye.accessibilityLabel = on ? @"Hide on-screen controls" : @"Show on-screen controls";
    g_eye.accessibilityValue = on ? @"On" : @"Off";
    g_eye.selected = on != 0;
	g_eye.backgroundColor = [UIColor colorWithWhite:0.13f alpha:(on ? 0.72f : 0.52f)];
}

/* ---- the pad: UIKit's own buttons, and the picture drawn ---------------------------------- */
static int bar_visible(void);   /* the native strip's own state, asked by the pad's gates below */
/* Native touch areas and artwork use the same completed TpVisual, in window points. */
@interface PadBtn : UIView {
 @public
	int idx;              /* TpButton's index: window.c speaks `which - 10` */
	int pill;
	int down;             /* this touch has the button */
}
@end

@implementation PadBtn
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)ev {
	(void)ev;
	if (!touchpad_on() || overlay_is_open()) return NO;
	if (bar_visible()) return NO;   /* the strip is down: its panel owns the screen, the shield takes the rest */
	if (overlay_pad_hidden()) return NO;   /* the bar's down, a menu, a dialog (Step 34's bits): whatever made the picture stand down stands its touches down -- the tabs sit on the pills' zone, and a menu must be pressable */
	{	/* wherever ImGui owns the point, the finger is its (a menu over the shoulders, a dialog):
		 * fall through as though this control were not here -- the exact behaviour the tap used to have.
		 * The native Menu button handles navigation independently. */
		const CGPoint wp = [self convertPoint:p toView:nil];
		/* The native Menu button owns navigation; the rest remains playable. */
		if (overlay_owns_point(wp.x, wp.y)) return NO;
	}
	if (pill) return CGRectContainsPoint(CGRectInset(self.bounds, -fmax(0, (44 - self.bounds.size.width) / 2), -fmax(0, (44 - self.bounds.size.height) / 2)), p);
	const float cxr = self.bounds.size.width * 0.5f, cyr = self.bounds.size.height * 0.5f;
	return hypotf(p.x - cxr, p.y - cyr) <= cxr;   /* the 1.18-radius circle, in the box the frame is */
}
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)ev { (void)ev;
	const CGPoint p = [[t anyObject] locationInView:nil];
	if (!down) {
		down = 1;
		if (!overlay_is_open()) { touchpad_native_press(10 + idx); ios_ui_haptic(pill ? 1 : 0); }
		chrome_log("    chrome: btn %d (%s) down at (%.0f, %.0f), pressed %d", idx, pill ? "pill" : "round", p.x, p.y, !overlay_is_open());
	} }
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)ev { (void)t; (void)ev;
	if (down) { chrome_log("    chrome: btn %d up", idx); down = 0; touchpad_native_release(10 + idx); } }
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)ev { (void)t; (void)ev;
	if (down) { chrome_log("    chrome: btn %d cancelled", idx); down = 0; touchpad_native_release(10 + idx); } }
@end

static UIColor *rgba(int r, int g, int b, float a) { return [UIColor colorWithRed:r / 255.0f green:g / 255.0f blue:b / 255.0f alpha:a]; }

/* the Vita's own glyphs, given Core Graphics' paths (the shapes and weights the ImGui card drew) */
static void pad_glyph_cg(CGContextRef c, int label, float cx, float cy, float r, UIColor *col) {
	const float t = r * 0.26f;          /* the stencil's line weight */
	CGContextSetStrokeColorWithColor(c, col.CGColor);
	CGContextSetFillColorWithColor(c, col.CGColor);
	CGContextSetLineWidth(c, t);
	switch (label) {
	case TP_LABEL_CROSS: { const float s = r * 0.5f;
		CGContextMoveToPoint(c, cx - s, cy - s); CGContextAddLineToPoint(c, cx + s, cy + s);
		CGContextMoveToPoint(c, cx - s, cy + s); CGContextAddLineToPoint(c, cx + s, cy - s);
		CGContextStrokePath(c); } break;
	case TP_LABEL_CIRCLE:
		CGContextStrokeEllipseInRect(c, CGRectMake(cx - r * 0.48f, cy - r * 0.48f, r * 0.96f, r * 0.96f));
		break;
	case TP_LABEL_SQUARE: { const float s = r * 0.42f;
		CGContextStrokePath(c);
		CGPathRef box = CGPathCreateWithRoundedRect(CGRectMake(cx - s, cy - s, 2 * s, 2 * s), r * 0.14f, r * 0.14f, NULL);
		CGContextAddPath(c, box); CGPathRelease(box); CGContextStrokePath(c); } break;
	case TP_LABEL_TRIANGLE: { const float s = r * 0.42f;
		CGContextStrokePath(c);
		CGContextMoveToPoint(c, cx, cy - s * 1.08f); CGContextAddLineToPoint(c, cx + s, cy + s * 0.62f);
		CGContextAddLineToPoint(c, cx - s, cy + s * 0.62f); CGContextClosePath(c); CGContextStrokePath(c); } break;
	case TP_LABEL_START: { const float s = r * 0.34f;
		CGContextStrokePath(c);
		CGContextMoveToPoint(c, cx - s * 0.7f, cy - s); CGContextAddLineToPoint(c, cx - s * 0.7f, cy + s);
		CGContextAddLineToPoint(c, cx + s, cy); CGContextClosePath(c); CGContextFillPath(c); } break;
	case TP_LABEL_SELECT: { const float s = r * 0.36f;
		CGContextStrokePath(c);
		CGContextSetLineWidth(c, s * 0.42f);
		CGContextMoveToPoint(c, cx - s, cy - s * 0.5f); CGContextAddLineToPoint(c, cx + s, cy - s * 0.5f); CGContextStrokePath(c);
		CGContextMoveToPoint(c, cx - s, cy + s * 0.5f); CGContextAddLineToPoint(c, cx + s, cy + s * 0.5f); CGContextStrokePath(c); } break;
	}
	CGContextSetLineWidth(c, t);
}

/* Paint one button or stick into its own cached image. Visibility is decided once by sync. */
static void pad_paint_cg(CGContextRef c, const TpVisual *tv) {
	const float a = (tv->opacity < 0 ? 0 : tv->opacity > 100 ? 100 : tv->opacity) / 100.0f;
	UIColor *fill = rgba(12, 14, 18, 0.55f * a), *ring = rgba(235, 240, 255, 0.75f * a);
	UIColor *text = rgba(235, 240, 255, 0.90f * a), *hot = rgba(255, 255, 255, a);
	UIColor *base = rgba(10, 12, 16, 0.30f * a), *knob_fill = rgba(235, 240, 255, 0.22f * a);

	if (tv->sl_active || tv->sr_active) {   /* the sticks, only while a thumb is on one */
		CGContextSetLineWidth(c, 1.5f);
		if (tv->sl_active) {
			CGContextSetFillColorWithColor(c, base.CGColor); CGContextSetStrokeColorWithColor(c, ring.CGColor);
			CGContextFillEllipseInRect(c, CGRectMake(tv->sl_x - tv->sl_r, tv->sl_y - tv->sl_r, 2 * tv->sl_r, 2 * tv->sl_r));
			CGContextStrokeEllipseInRect(c, CGRectMake(tv->sl_x - tv->sl_r, tv->sl_y - tv->sl_r, 2 * tv->sl_r, 2 * tv->sl_r));
			const float kr = tv->sl_r * 0.42f;
			CGContextSetFillColorWithColor(c, knob_fill.CGColor); CGContextSetStrokeColorWithColor(c, hot.CGColor);
			CGContextFillEllipseInRect(c, CGRectMake(tv->sl_kx - kr, tv->sl_ky - kr, 2 * kr, 2 * kr));
			CGContextStrokeEllipseInRect(c, CGRectMake(tv->sl_kx - kr, tv->sl_ky - kr, 2 * kr, 2 * kr));
		}
		if (tv->sr_active) {
			CGContextSetFillColorWithColor(c, base.CGColor); CGContextSetStrokeColorWithColor(c, ring.CGColor);
			CGContextFillEllipseInRect(c, CGRectMake(tv->sr_x - tv->sr_r, tv->sr_y - tv->sr_r, 2 * tv->sr_r, 2 * tv->sr_r));
			CGContextStrokeEllipseInRect(c, CGRectMake(tv->sr_x - tv->sr_r, tv->sr_y - tv->sr_r, 2 * tv->sr_r, 2 * tv->sr_r));
			const float kr = tv->sr_r * 0.42f;
			CGContextSetFillColorWithColor(c, knob_fill.CGColor); CGContextSetStrokeColorWithColor(c, hot.CGColor);
			CGContextFillEllipseInRect(c, CGRectMake(tv->sr_kx - kr, tv->sr_ky - kr, 2 * kr, 2 * kr));
			CGContextStrokeEllipseInRect(c, CGRectMake(tv->sr_kx - kr, tv->sr_ky - kr, 2 * kr, 2 * kr));
		}
	}
	for (int i = 0; i < tv->nb; i++) {   /* the buttons: the same fill, ring and glyph, down lighting the pressed one */
		const TpButton *b = &tv->b[i];
		UIColor *cf = b->down ? rgba(255, 255, 255, 0.30f * a) : fill;
		UIColor *co = b->down ? hot : ring;
		UIColor *ct = b->down ? hot : text;
		CGContextSetFillColorWithColor(c, cf.CGColor);
		if (b->pill) {
			UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(b->x - b->hw, b->y - b->hh, 2 * b->hw, 2 * b->hh) cornerRadius:b->hh];
			CGContextSetStrokeColorWithColor(c, co.CGColor); CGContextSetLineWidth(c, 1.5f);
			[p fill]; [p stroke];
			if (b->label == TP_LABEL_L || b->label == TP_LABEL_R) {
				NSString *l = [NSString stringWithUTF8String:(b->label == TP_LABEL_L ? "L" : "R")];
				UIFont *f = [UIFont systemFontOfSize:b->hh * 1.05f weight:UIFontWeightMedium];
				NSDictionary *at = @{NSFontAttributeName: f, NSForegroundColorAttributeName: ct};
				const CGSize ts = [l sizeWithAttributes:at];   /* drawInRect hangs a line from the rect's top: centering is measured, not asked */
				[l drawAtPoint:CGPointMake(b->x - ts.width * 0.5f, b->y - ts.height * 0.5f) withAttributes:at];
			} else pad_glyph_cg(c, b->label, b->x, b->y, b->hh * 1.1f, ct);
		} else {
			const float dr = b->r;   /* the painted circle, back at its own size (the phone's word: only the icon was oversized, not the button) */
			const float gr = dr * 1.05f;   /* the glyph inside, smaller than the old proportions: a mark in the circle, not a badge on it */
			CGContextSetStrokeColorWithColor(c, co.CGColor); CGContextSetLineWidth(c, 1.5f);
			CGContextFillEllipseInRect(c, CGRectMake(b->x - dr, b->y - dr, 2 * dr, 2 * dr));
			CGContextStrokeEllipseInRect(c, CGRectMake(b->x - dr, b->y - dr, 2 * dr, 2 * dr));
			pad_glyph_cg(c, b->label, b->x, b->y, gr, ct);
		}
	}
}

/* Each control owns a small cached image. Moving a stick must not allocate/rasterize a
 * full 2796x1290 canvas every refresh; unchanged buttons cost no image work at all. */
@interface PadLayer : UIView {
    CALayer *pictures[10];
    TpVisual previous[10];
    CGFloat imageScale[10];
    BOOL valid[10];
}
- (void)sync;
@end
@implementation PadLayer
- (void)paint:(TpVisual)visual inRect:(CGRect)rect slot:(int)slot scale:(CGFloat)scale {
    if (!pictures[slot]) {
        pictures[slot] = [CALayer layer]; [self.layer addSublayer:pictures[slot]];
    }
    pictures[slot].hidden = NO;
    if (valid[slot] && !memcmp(&visual, &previous[slot], sizeof visual) && imageScale[slot] == scale) return;
    previous[slot] = visual; imageScale[slot] = scale; valid[slot] = YES;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO; format.scale = scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:rect.size format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextTranslateCTM(context.CGContext, -rect.origin.x, -rect.origin.y);
        pad_paint_cg(context.CGContext, &visual);
    }];
    pictures[slot].frame = rect; pictures[slot].contentsScale = scale;
    pictures[slot].contents = (id)image.CGImage;
    [renderer release];
}
- (void)sync {
    const TpVisual snapshot = *touchpad_visuals();
    const BOOL show = snapshot.on && snapshot.nb > 0 && !overlay_pad_hidden() && !bar_visible();
    self.hidden = !show;
    if (!show || !self.window) return;
    const CGSize size = self.bounds.size;
    if (fabs(snapshot.w - size.width) > 1 || fabs(snapshot.h - size.height) > 1) {
        self.hidden = YES; memset(valid, 0, sizeof valid); return;
    }
    const CGFloat scale = self.window.screen.scale;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (int i = 0; i < 8; i++) {
        if (i >= snapshot.nb) { pictures[i].hidden = YES; continue; }
        TpVisual visual = {0}; visual.on = 1; visual.opacity = snapshot.opacity;
        visual.nb = 1; visual.b[0] = snapshot.b[i];
        const TpButton b = visual.b[0];
        const CGFloat hw = b.pill ? b.hw : b.r, hh = b.pill ? b.hh : b.r;
        [self paint:visual inRect:CGRectMake(b.x - hw - 2, b.y - hh - 2, hw * 2 + 4, hh * 2 + 4) slot:i scale:scale];
    }
    for (int stick = 0; stick < 2; stick++) {
        const int active = stick ? snapshot.sr_active : snapshot.sl_active;
        if (!active) { pictures[8 + stick].hidden = YES; continue; }
        const float x = stick ? snapshot.sr_x : snapshot.sl_x, y = stick ? snapshot.sr_y : snapshot.sl_y;
        const float reach = stick ? snapshot.sr_r : snapshot.sl_r;
        float dx = (stick ? snapshot.sr_kx : snapshot.sl_kx) - x;
        float dy = (stick ? snapshot.sr_ky : snapshot.sl_ky) - y;
        const float length = hypotf(dx, dy);
        if (length > reach && length > 0) { dx *= reach / length; dy *= reach / length; }
        TpVisual visual = {0}; visual.on = 1; visual.opacity = snapshot.opacity;
        visual.sl_active = 1; visual.sl_x = x; visual.sl_y = y; visual.sl_r = reach;
        visual.sl_kx = x + dx; visual.sl_ky = y + dy;
        const CGFloat extent = reach * 1.42 + 2; /* base + fully deflected knob, including stroke */
        [self paint:visual inRect:CGRectMake(x - extent, y - extent, extent * 2, extent * 2) slot:8 + stick scale:scale];
    }
    [CATransaction commit];
}
@end

static PadLayer *g_pad_layer;        /* control-sized cached artwork, synchronized with tp_layout */
static PadBtn   *g_pad_hits[8];       /* its touch areas, positioned from the same TpVisual */
static UIImpactFeedbackGenerator *g_hap[3];   /* light / medium / soft, prepared as they're first asked */

void ios_ui_chrome_cancel_controls(void) {
    for (int i = 0; i < 8; i++) if (g_pad_hits[i]) g_pad_hits[i]->down = 0;
}

/* the taptic engine's answer: 0 light (a button, the eye, a pull), 1 medium (the shoulders), 2 soft
 * (a thumb's hold becoming a stick). Thread-safe: whatever calls it, the tap happens on the main */
void ios_ui_haptic(int kind) {
	if (!g_installed) return;
	if (kind < 0 || kind > 2) kind = 0;
	if (![NSThread isMainThread]) { const int k = kind; dispatch_async(dispatch_get_main_queue(), ^{ ios_ui_haptic(k); }); return; }
	if (!g_hap[kind]) {
		g_hap[kind] = [[UIImpactFeedbackGenerator alloc] initWithStyle:(kind == 1 ? UIImpactFeedbackStyleMedium : kind == 2 ? UIImpactFeedbackStyleSoft : UIImpactFeedbackStyleLight)];
		[g_hap[kind] prepare];
	}
	[g_hap[kind] impactOccurred];
}
/* The whole daily surface of the ImGui overlay -- pull-down bar and its three menus -- built as UIKit's
 * own: a strip with three tabs, each opening a panel of rows below it, every row driving the exact
 * function the ImGui row drove (overlay.cpp's native handles, no new state invented). While the chrome
 * is up: taps in the top strip's middle band (and only there -- "so L and R don't misstrigger it")
 * slide the strip down; a tab holds its panel; a tap anywhere else closes both; the pad and its touches
 * stand down while the strip is up, exactly as the ImGui bar's bit did. The ImGui bar and its pull tab
 * build never (overlay.cpp gates them on ios_ui_chrome_active); RECOMP_NATIVE_CHROME=0 restores all of it. */
static UIView *g_bar;                /* the strip itself */
static UIButton *g_bar_tab[3];      /* Game / Display / Controls */
static UIView *g_shield;             /* tap-anywhere-to-close: one tap, the game never sees it */
static UIScrollView *g_panel_scroll;
static UIView *g_panel_content;
static UIView *g_panel;              /* the open panel (its rows rebuilt per state change) */
static int g_panel_tab = -1;         /* which panel is open (-1: none) */
static int g_bar_shown;              /* the strip is down (its own slide state) */
static double g_bar_last;            /* the last moment the strip was touched */
static UIView *g_rows;               /* where panel primitives add (the strip's panel, or the settings center's page) */

/* UIControl does not retain targets. Associate each action with its own owner instead of
 * a global array: rebuilding a panel must never delete the bar's or page tabs' targets. */
@interface BN : NSObject { @public void (^b)(void); }
- (void)fire;
@end
@implementation BN
- (void)dealloc { [b release]; [super dealloc]; }
- (void)fire {
    /* An action may rebuild/remove its own control. Keep the executing block alive. */
    void (^run)(void) = [b copy];
    run(); [run release];
}
@end
static char action_key;
static BN *action_for(id owner, void (^block)(void)) {
    NSMutableArray *actions = objc_getAssociatedObject(owner, &action_key);
    if (!actions) {
        actions = [NSMutableArray array];
        objc_setAssociatedObject(owner, &action_key, actions, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BN *action = [[[BN alloc] init] autorelease];
    action->b = [block copy]; [actions addObject:action];
    return action;
}
static void control_on(UIControl *control, UIControlEvents events, void (^block)(void)) {
    [control addTarget:action_for(control, block) action:@selector(fire) forControlEvents:events];
}
static void tap_on(UIView *view, void (^block)(void)) {
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] init];
    [tap addTarget:action_for(tap, block) action:@selector(fire)];
    [view addGestureRecognizer:tap]; [tap release];
}

/* the strip's colours and type, one place */
static UIFont *bar_row_font(void) { return [UIFont systemFontOfSize:14.5f]; }

/* a panel row's primitives -- manual frames, manual memory, nothing clever */
static UILabel *panel_head(CGRect f, NSString *s) {
	UILabel *l = [[UILabel alloc] initWithFrame:f];
	l.text = s; l.font = [UIFont systemFontOfSize:11.5f weight:UIFontWeightMedium];
	l.textColor = rgba(150, 156, 172, 1.0f);
	[g_rows addSubview:l]; [l release];
	return l;
}
static UIView *panel_line(CGRect f) {
	UIView *v = [[UIView alloc] initWithFrame:f];
	v.backgroundColor = rgba(255, 255, 255, 0.08f);
	[g_rows addSubview:v]; [v release];
	return v;
}
static UIView *panel_dot(CGRect f) {   /* selected row */
	UIImageView *v = [[UIImageView alloc] initWithFrame:CGRectMake(f.origin.x - 6.0f, f.origin.y - 4.0f, 14.0f, 14.0f)];
	v.image = glyph(@"check", 14.0f, 14.0f, rgba(240, 192, 96, 1.0f));
	[g_rows addSubview:v]; [v release];
	return v;
}
static UIButton *panel_button(CGRect f, NSString *title) {
	UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
	b.frame = f;
	b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
	b.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
	b.titleLabel.font = bar_row_font();
	[b setTitleColor:rgba(234, 236, 244, 0.94f) forState:UIControlStateNormal];
	[b setTitle:title forState:UIControlStateNormal];
	[b setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted | UIControlStateSelected];
	b.layer.cornerRadius = 6.0f;
	{	/* test29 crashed on it: setBackgroundColor:forState: is no UIButton API -- the highlight is
		 * a stretchable tile instead, its corners capped so the rounding survives the stretch */
		static UIImage *hi;
		if (!hi) {
			UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(18, 18)];
			UIImage *tile = [r imageWithActions:^(UIGraphicsImageRendererContext *rc) {
				UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 18, 18) cornerRadius:6];
				[rgba(255, 255, 255, 0.10f) setFill]; [p fill];
			}];
			[r release];
			hi = [[tile resizableImageWithCapInsets:UIEdgeInsetsMake(6, 6, 6, 6)] retain];
		}
		[b setBackgroundImage:hi forState:UIControlStateHighlighted];
	}
	[g_rows addSubview:b];
	return b;
}
static void panel_fire_on_highlight(UIButton *b, void (^blk)(void)) {   /* the row owns its action */
	control_on(b, UIControlEventTouchUpInside, blk);
}

/* the panel's three contents -- the phone's own rows, the same actions the ImGui menus took */
static void bar_panel_rebuild(void);
static void bar_up_close_all(void);
static void bar_make(void);
void ios_ui_settings_open(int tab);   /* the full menu, native (below) */
static CGFloat panel_rows(int tab) {
	g_rows = g_panel_content;
	CGFloat y = 6;
	const CGFloat row = 44.0f, inset = 14.0f;
	const CGRect vb = g_panel.bounds;
	UIButton *b;
	if (tab == 0) {   /* Game */
		b = panel_button(CGRectMake(0, y, vb.size.width, row), overlay_game_paused() ? @"Resume" : @"Pause");
		panel_fire_on_highlight(b, ^{ overlay_set_paused(overlay_game_paused() ? 0 : 1); bar_panel_rebuild(); });
		y += row;
		b = panel_button(CGRectMake(0, y, vb.size.width, row), @"All settings…");
		panel_fire_on_highlight(b, ^{ bar_up_close_all(); ios_ui_settings_open(2); });   /* the center's Game page */
		y += row;
		{	/* Volume: the label, the slider, the live value */
			UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(inset, y + 7, 64, 19)];
			l.text = @"Volume"; l.font = bar_row_font(); l.textColor = rgba(234, 236, 244, 0.94f);
			[g_rows addSubview:l]; [l release];
			UILabel *vl = [[UILabel alloc] initWithFrame:CGRectMake(vb.size.width - 56, y + 7, 44, 19)];
			vl.font = bar_row_font(); vl.textColor = rgba(150, 156, 172, 1.0f); vl.text = [NSString stringWithFormat:@"%.0f%%", overlay_volume() * 100.0f];
			[g_rows addSubview:vl]; [vl release];
			UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(inset + 70, y + 3, vb.size.width - inset - 74 - 56, 28)];
			sl.minimumValue = 0.0f; sl.maximumValue = 1.0f; sl.value = overlay_volume();
			sl.minimumTrackTintColor = rgba(240, 192, 96, 1.0f);
			[g_rows addSubview:sl];
			/* no ARC: __block keeps the slider's blocks from retaining the slider that targets them */
	__block UISlider *wsl = sl; __block UILabel *wvl = vl;
	control_on(sl, UIControlEventValueChanged, ^{ overlay_set_volume(wsl.value); wvl.text = [NSString stringWithFormat:@"%.0f%%", wsl.value * 100.0f]; });
			[sl release];
		}
		y += row + 4;
		if (overlay_frame_rate_offered()) {
			y += 4;
			UILabel *h = panel_head(CGRectMake(inset, y, vb.size.width - 2 * inset, 16), @"Frame rate"); (void)h;
			y += 18;
			const int fr = overlay_frame_rate_wanted();
			b = panel_button(CGRectMake(0, y, vb.size.width, row), @"30");
			if (fr < 60) panel_dot(CGRectMake(vb.size.width - 20, y + row * 0.5f - 3, 6, 6));
			panel_fire_on_highlight(b, ^{ overlay_frame_rate_request(30); bar_panel_rebuild(); });
			y += row;
			b = panel_button(CGRectMake(0, y, vb.size.width, row), @"60 (experimental)");
			if (fr >= 60) panel_dot(CGRectMake(vb.size.width - 20, y + row * 0.5f - 3, 6, 6));
			panel_fire_on_highlight(b, ^{ overlay_frame_rate_request(60); bar_panel_rebuild(); });
			y += row;
		}
		panel_line(CGRectMake(0, y + 2, vb.size.width, 1)); y += 10;
		b = panel_button(CGRectMake(0, y, vb.size.width, row), @"Quit game");
		panel_fire_on_highlight(b, ^{ bar_up_close_all(); overlay_quit_confirm(); });
		y += row;
	}
	if (tab == 1) {   /* Display */
		{
			UILabel *h = panel_head(CGRectMake(inset, y, vb.size.width - 2 * inset, 16), @"On-screen stats"); (void)h;
			y += 18;
			static const char *const names[3] = { "Off", "FPS", "Full" };
			const int lvl = overlay_stats_level();
			for (int i = 0; i < 3; i++) {
				UIButton *r = panel_button(CGRectMake(0, y, vb.size.width, row), [NSString stringWithUTF8String:names[i]]);
				if (lvl == i) panel_dot(CGRectMake(vb.size.width - 20, y + row * 0.5f - 3, 6, 6));
				const int pick = i;
				panel_fire_on_highlight(r, ^{ overlay_set_stats(pick); bar_panel_rebuild(); });
				y += row;
			}
		}
		y += 4; panel_line(CGRectMake(0, y, vb.size.width, 1)); y += 8;
		{
			UILabel *h = panel_head(CGRectMake(inset, y, vb.size.width - 2 * inset, 16), @"Resolution"); (void)h;
			y += 18;
			int mx = gfx_gpu_render_scale_max(); if (mx > 3) mx = 3;
			const int rs = gfx_gpu_render_scale_wanted();
			for (int n = 1; n <= mx; n++) {
				NSString *l = [NSString stringWithFormat:@"%dx   %d x %d", n, 960 * n, 544 * n];
				UIButton *r = panel_button(CGRectMake(0, y, vb.size.width, row), l);
				if (rs == n) panel_dot(CGRectMake(vb.size.width - 20, y + row * 0.5f - 3, 6, 6));
				const int pick = n;
				panel_fire_on_highlight(r, ^{ gfx_gpu_render_scale_request(pick); bar_panel_rebuild(); });
				y += row;
			}
		}
	}
	if (tab == 2) {   /* Controls */
		{	int on = touchpad_on();
			UIButton *r = panel_button(CGRectMake(0, y, vb.size.width, row), @"On-screen controls");
			UILabel *st = [[UILabel alloc] initWithFrame:CGRectMake(vb.size.width - 58, y + 8, 44, 18)];
			st.font = bar_row_font(); st.textColor = on ? rgba(240, 192, 96, 1.0f) : rgba(150, 156, 172, 1.0f);
			st.text = on ? @"On" : @"Off";
			[g_rows addSubview:st]; [st release];
			panel_fire_on_highlight(r, ^{ touchpad_set_on(touchpad_on() ? 0 : 1); bar_panel_rebuild(); });
			y += row;
		}
		{	int on = window_touchpad_rstick() != 0;
			UIButton *r = panel_button(CGRectMake(0, y, vb.size.width, row), @"Second stick");
			UILabel *st = [[UILabel alloc] initWithFrame:CGRectMake(vb.size.width - 58, y + 8, 44, 18)];
			st.font = bar_row_font(); st.textColor = on ? rgba(240, 192, 96, 1.0f) : rgba(150, 156, 172, 1.0f);
			st.text = on ? @"On" : @"Off";
			[g_rows addSubview:st]; [st release];
			panel_fire_on_highlight(r, ^{ settings_set_int("touchpad_rstick", window_touchpad_rstick() ? 0 : 1); settings_save(); bar_panel_rebuild(); });
			y += row;
		}
		{	/* Control size: 60..160 */
			UILabel *l = panel_head(CGRectMake(inset, y + 8, vb.size.width - 2 * inset - 56, 18), @"Control size");
			(void)l; l.text = @"Control size"; l.font = bar_row_font(); l.textColor = rgba(234, 236, 244, 0.94f);
			UILabel *vl = [[UILabel alloc] initWithFrame:CGRectMake(vb.size.width - 56, y + 8, 44, 18)];
			vl.font = bar_row_font(); vl.textColor = rgba(150, 156, 172, 1.0f);
			int v = touchpad_scale();
			vl.text = [NSString stringWithFormat:@"%d%%", v];
			[g_rows addSubview:vl]; [vl release];
			UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(inset, y + 26, vb.size.width - 2 * inset, 24)];
			sl.minimumValue = 60; sl.maximumValue = 160; sl.value = v;
			sl.minimumTrackTintColor = rgba(240, 192, 96, 1.0f);
			[g_rows addSubview:sl];
			__block UISlider *wsl = sl; __block UILabel *wvl = vl;   /* no ARC: keeps the blocks from retaining the slider */
			control_on(sl, UIControlEventValueChanged, ^{ int nv = (int)(wsl.value + 0.5f); wvl.text = [NSString stringWithFormat:@"%d%%", nv]; });
			control_on(sl, UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel, ^{ touchpad_set_scale((int)(wsl.value + 0.5f)); });
			[sl release];
			y += row + 16;
		}
		{	/* Opacity: 10..90 */
			UILabel *l = panel_head(CGRectMake(inset, y + 8, vb.size.width - 2 * inset - 56, 18), @"Control opacity");
			l.font = bar_row_font(); l.textColor = rgba(234, 236, 244, 0.94f);
			UILabel *vl = [[UILabel alloc] initWithFrame:CGRectMake(vb.size.width - 56, y + 8, 44, 18)];
			vl.font = bar_row_font(); vl.textColor = rgba(150, 156, 172, 1.0f);
			int v = settings_int("touchpad_opacity", 42);
			vl.text = [NSString stringWithFormat:@"%d%%", v];
			[g_rows addSubview:vl]; [vl release];
			UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(inset, y + 26, vb.size.width - 2 * inset, 24)];
			sl.minimumValue = 10; sl.maximumValue = 90; sl.value = v;
			sl.minimumTrackTintColor = rgba(240, 192, 96, 1.0f);
			[g_rows addSubview:sl];
			__block UISlider *wsl = sl; __block UILabel *wvl = vl;   /* no ARC: keeps the blocks from retaining the slider */
			control_on(sl, UIControlEventValueChanged, ^{ int nv = (int)(wsl.value + 0.5f); wvl.text = [NSString stringWithFormat:@"%d%%", nv]; });
			control_on(sl, UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel, ^{ settings_set_int("touchpad_opacity", (int)(wsl.value + 0.5f)); settings_save(); });
			[sl release];
			y += row + 16;
		}
		{	bool lh = touchpad_mirror() != 0;
			UIButton *r = panel_button(CGRectMake(0, y, vb.size.width, row), @"Left-handed");
			UILabel *st = [[UILabel alloc] initWithFrame:CGRectMake(vb.size.width - 58, y + 8, 44, 18)];
			st.font = bar_row_font(); st.textColor = lh ? rgba(240, 192, 96, 1.0f) : rgba(150, 156, 172, 1.0f);
			st.text = lh ? @"On" : @"Off";
			[g_rows addSubview:st]; [st release];
			panel_fire_on_highlight(r, ^{ touchpad_set_mirror(touchpad_mirror() ? 0 : 1); bar_panel_rebuild(); });
			y += row;
		}
		panel_line(CGRectMake(0, y + 2, vb.size.width, 1)); y += 10;
		b = panel_button(CGRectMake(0, y, vb.size.width, row), @"Controls reference…");
		panel_fire_on_highlight(b, ^{ bar_up_close_all(); ios_ui_settings_open(3); });   /* the center's Controls page */
		y += row;
	}
	return y + 8;
}

static void bar_panel_rebuild(void) {
    if (g_panel_tab < 0) return;
    for (UIView *view in g_panel_content.subviews) [view removeFromSuperview];
    const CGRect safe = chrome_safe_rect();
    const CGFloat width = fmin(g_panel_tab == 2 ? 320 : 280, safe.size.width - 16);
    const CGRect tab = [g_bar_tab[g_panel_tab] convertRect:g_bar_tab[g_panel_tab].bounds toView:g_host];
    const CGFloat x = fmax(CGRectGetMinX(safe) + 8, fmin(tab.origin.x, CGRectGetMaxX(safe) - width - 8));
    const CGFloat y = CGRectGetMaxY(g_bar.frame) + 4;
    g_panel.frame = CGRectMake(x, y, width, 100);
    g_panel_scroll.frame = g_panel.bounds;
    g_panel_content.frame = CGRectMake(0, 0, width, 100);
    const CGFloat content = panel_rows(g_panel_tab);
    const CGFloat height = fmin(content, fmax(44, CGRectGetMaxY(safe) - y - 8));
    g_panel.frame = CGRectMake(x, y, width, height);
    g_panel_scroll.frame = g_panel.bounds;
    g_panel_scroll.contentSize = CGSizeMake(width, content);
    g_panel_content.frame = CGRectMake(0, 0, width, content);
    for (int i = 0; i < 3; i++) g_bar_tab[i].selected = i == g_panel_tab;
}
static void bar_panel_open(int tab) {
    g_panel_tab = tab; g_bar_last = chrome_now();
    bar_panel_rebuild(); g_panel.hidden = NO;
    ios_ui_haptic(0);
}
static void bar_panel_close(void) {
    g_panel_tab = -1; g_panel.hidden = YES;
    for (int i = 0; i < 3; i++) g_bar_tab[i].selected = NO;
}
static void bar_up_close_all(void) {
    if (!g_bar) return;
    bar_panel_close(); g_bar_shown = 0; g_shield.hidden = YES;
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        CGRect f = g_bar.frame; f.origin.y = -f.size.height; g_bar.frame = f;
    } completion:nil];
}
void ios_ui_bar_open(void) {
    if (!g_installed) return;
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ ios_ui_bar_open(); }); return; }
    if (overlay_is_open() || (overlay_pad_hidden() & 8)) return;
    if (!g_bar) bar_make();
    overlay_intro_dismiss(); touchpad_cancel_all(); ios_ui_chrome_cancel_controls();
    g_bar_last = chrome_now();
    if (!g_bar_shown) {
        g_bar_shown = 1; g_shield.hidden = NO;
        [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            CGRect f = g_bar.frame; f.origin.y = 0; g_bar.frame = f;
        } completion:nil];
        ios_ui_haptic(0);
    }
}
static void bar_tab_tapped(int tab) {
    if (overlay_is_open()) { bar_up_close_all(); return; }
    g_bar_last = chrome_now();
    if (g_panel_tab == tab) bar_panel_close(); else bar_panel_open(tab);
}
static void bar_make(void) {
    /* Layer order is deliberate: outside-tap shield, bar, scrollable panel. */
    g_shield = [[UIView alloc] initWithFrame:g_host.bounds];
    g_shield.backgroundColor = [UIColor colorWithWhite:0 alpha:0.15];
    g_shield.hidden = YES; tap_on(g_shield, ^{ bar_up_close_all(); });
    [g_host addSubview:g_shield]; [g_shield release];
    g_bar = [[UIView alloc] initWithFrame:CGRectMake(0, -44, g_host.bounds.size.width, 44)];
    blur_fill(g_bar, UIBlurEffectStyleSystemMaterialDark);
    [g_host addSubview:g_bar]; [g_bar release];
    const char *tabs[3] = {"Game", "Display", "Controls"};
    CGFloat x = g_win.safeAreaInsets.left + 8;
    for (int i = 0; i < 3; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(x, 0, 100, 44);
        button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        [button setTitle:[NSString stringWithUTF8String:tabs[i]] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
        [button setTitleColor:rgba(240, 192, 96, 1) forState:UIControlStateSelected];
        const int tab = i; control_on(button, UIControlEventTouchUpInside, ^{ bar_tab_tapped(tab); });
        [g_bar addSubview:button]; g_bar_tab[i] = button; x += 104;
    }
    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem]; done.tag = 700;
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    done.tintColor = rgba(240, 192, 96, 1);
    control_on(done, UIControlEventTouchUpInside, ^{ bar_up_close_all(); });
    [g_bar addSubview:done];
    g_panel = [[UIView alloc] initWithFrame:CGRectZero];
    blur_fill(g_panel, UIBlurEffectStyleSystemMaterialDark);
    g_panel.layer.cornerRadius = 12; g_panel.clipsToBounds = YES; g_panel.hidden = YES;
    [g_host addSubview:g_panel]; [g_panel release];
    g_panel_scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    g_panel_scroll.alwaysBounceVertical = NO; g_panel_scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [g_panel addSubview:g_panel_scroll]; [g_panel_scroll release];
    g_panel_content = [[UIView alloc] initWithFrame:CGRectZero];
    [g_panel_scroll addSubview:g_panel_content]; [g_panel_content release];
    chrome_layout();
}
static int bar_visible(void) { return g_bar_shown; }
int ios_ui_chrome_blocks_touch(void) { return g_installed && bar_visible(); }

/* ---- Step 39: what was left -- the stats OSD, the pause card, the intro strip, the full menu ------- */
/* All of it was the last ImGui drew on a phone. Each one here drives the same state via overlay.cpp's
 * handles (no new logic): the OSD's lines are the F1 overlay's own, the pause card reads the same
 * g_paused the banner did, the intro strip ends by overlay_intro_dismiss (its tap and 12-second rules
 * the tick below holds), and the settings center is the full menu's five pages as UIKit rows, opened
 * through the same overlay_open/overlay_close (pause, input routing and audio included) as before. */

/* the stats OSD (Off / FPS / Full): one label under the eye's corner, re-stringed by the tick */
static UILabel *g_osd_lbl;
static void osd_tick(void) {
	if (!g_installed || !g_host) return;
	static double last;
	static int lastLevel = -1;
	const int level = overlay_stats_level();
	const double now = chrome_now();
	if (g_osd_lbl && !g_osd_lbl.hidden && level == lastLevel && now - last < 0.25 && !bar_visible() && !overlay_is_open()) return;
	last = now; lastLevel = level;
	char lines[7][40];
	int n = 0;
	if (overlay_stats_level() > 0 && !bar_visible() && !overlay_is_open()) n = overlay_osd_lines(lines, 7);
	if (!g_osd_lbl) {
		if (!n) return;
		g_osd_lbl = [[UILabel alloc] initWithFrame:CGRectZero];
		g_osd_lbl.font = [UIFont fontWithName:@"Menlo-Bold" size:10.0f];
		g_osd_lbl.textColor = [UIColor whiteColor];
		g_osd_lbl.numberOfLines = 0;
		g_osd_lbl.backgroundColor = rgba(0, 0, 0, 0.66f);
		g_osd_lbl.layer.cornerRadius = 3.0f;
		g_osd_lbl.layer.masksToBounds = YES;
		[g_host addSubview:g_osd_lbl];
		[g_osd_lbl release];
		chrome_log("    chrome: osd label made (level %d)", overlay_stats_level());
	}
	if (!n) { g_osd_lbl.hidden = YES; return; }
	NSString *txt = @"";
	for (int i = 0; i < n; i++) txt = [txt stringByAppendingFormat:@"%s%s", i ? "\n" : "", lines[i]];
	g_osd_lbl.text = txt;
	const CGSize tz = [g_osd_lbl sizeThatFits:CGSizeMake(600.0f, 2000.0f)];
	CGFloat y = 42.0f;   /* under the eye's own slot */
	if (g_eye && !g_eye.hidden) { const CGFloat ey = CGRectGetMaxY(g_eye.frame) + 8.0f; if (ey > y) y = ey; }
	g_osd_lbl.frame = CGRectMake(chrome_safe_rect().origin.x + 8.0f, y, tz.width + 12.0f, tz.height + 10.0f);
	g_osd_lbl.hidden = NO;
}

/* the pause card: PAUSED, the same centered card the banner drew */
static UIView *g_pz_card; static UILabel *g_pz_t, *g_pz_s;
static void pause_tick(void) {
	if (!g_installed || !g_host) return;
	const int show = overlay_game_paused() && !overlay_is_open() && !overlay_intro_up() && !bar_visible();
	if (!show) { if (g_pz_card) g_pz_card.hidden = YES; return; }
	if (!g_pz_card) {
		g_pz_card = [[UIView alloc] initWithFrame:CGRectZero];
		g_pz_card.backgroundColor = [UIColor clearColor];
		blur_fill(g_pz_card, UIBlurEffectStyleSystemMaterialDark);
		g_pz_card.layer.cornerRadius = 14.0f;
		g_pz_card.layer.masksToBounds = YES;
		g_pz_card.userInteractionEnabled = YES;
        tap_on(g_pz_card, ^{ overlay_set_paused(0); });
        g_pz_card.accessibilityLabel = @"Resume game";
        g_pz_card.accessibilityTraits = UIAccessibilityTraitButton;
		g_pz_t = [[UILabel alloc] initWithFrame:CGRectZero];
		g_pz_t.text = @"PAUSED"; g_pz_t.font = [UIFont systemFontOfSize:24.0f weight:UIFontWeightBold];
		g_pz_t.textColor = [UIColor whiteColor]; g_pz_t.textAlignment = NSTextAlignmentCenter;
		[g_pz_card addSubview:g_pz_t]; [g_pz_t release];
		g_pz_s = [[UILabel alloc] initWithFrame:CGRectZero];
		g_pz_s.text = @"Tap to resume, or open Menu for settings";
		g_pz_s.font = [UIFont systemFontOfSize:13.0f];
		g_pz_s.textColor = rgba(205, 205, 215, 1.0f); g_pz_s.textAlignment = NSTextAlignmentCenter;
		[g_pz_card addSubview:g_pz_s]; [g_pz_s release];
		[g_host addSubview:g_pz_card];
		[g_pz_card release];
	}
	const CGSize sz = g_host.bounds.size;
	const CGFloat bw = 330.0f, bh = 84.0f;
	g_pz_card.frame = CGRectMake((sz.width - bw) * 0.5f, (sz.height - bh) * 0.5f, bw, bh);
	g_pz_t.frame = CGRectMake(0, 16, bw, 30);
	g_pz_s.frame = CGRectMake(0, 50, bw, 16);
	g_pz_card.hidden = NO;
}

/* the intro strip: the one-card lesson for the first launch, taps falling through it to the
 * running game (its own NoInputs), gone on the first touch anywhere or twelve seconds */
static UIView *g_intro_view;
static UILabel *g_intro_title, *g_intro_body;
static double g_intro_t0;
static void intro_tick(void) {
    if (!overlay_intro_up()) { g_intro_view.hidden = YES; g_intro_t0 = 0; return; }
    const double now = chrome_now();
    if (!g_intro_t0) g_intro_t0 = now;
    int keys[8], xs[8], ys[8];
    const int touched = window_touch_contacts(0, keys, xs, ys, 8) || window_touch_contacts(1, keys, xs, ys, 8);
    if (touched || now - g_intro_t0 >= 12 || bar_visible()) {
        overlay_intro_dismiss(); g_intro_view.hidden = YES; return;
    }
    if (!g_intro_view) {
        g_intro_view = [[UIView alloc] initWithFrame:CGRectZero];
        blur_fill(g_intro_view, UIBlurEffectStyleSystemMaterialDark);
        g_intro_view.layer.cornerRadius = 12; g_intro_view.clipsToBounds = YES;
        g_intro_view.userInteractionEnabled = NO;
        g_intro_title = [[UILabel alloc] init];
        g_intro_title.text = @"Playing on this phone";
        g_intro_title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        g_intro_title.textColor = [UIColor whiteColor];
        [g_intro_view addSubview:g_intro_title]; [g_intro_title release];
        g_intro_body = [[UILabel alloc] init]; g_intro_body.numberOfLines = 0;
        g_intro_body.font = [UIFont systemFontOfSize:13]; g_intro_body.textColor = rgba(220, 224, 234, 1);
        g_intro_body.text = @"Hold or drag the lower corners for the sticks. Quick taps touch the game. Tap Menu at the top centre for settings; the eye hides or shows the controls.";
        [g_intro_view addSubview:g_intro_body]; [g_intro_body release];
        [g_host addSubview:g_intro_view]; [g_intro_view release];
    }
    const CGRect safe = chrome_safe_rect();
    const CGFloat width = fmin(430, safe.size.width - 32);
    const CGSize body = [g_intro_body sizeThatFits:CGSizeMake(width - 28, CGFLOAT_MAX)];
    const CGFloat height = 50 + body.height;
    g_intro_view.frame = CGRectMake(CGRectGetMidX(safe) - width / 2, CGRectGetMaxY(safe) - height - 8, width, height);
    g_intro_title.frame = CGRectMake(14, 12, width - 28, 20);
    g_intro_body.frame = CGRectMake(14, 36, width - 28, body.height);
    g_intro_view.hidden = NO;
}

/* the settings center: the full menu as iOS's own settings look (Step 43) -- a real navigation bar
 * with Done, a real segmented control for the five pages, and a real UITableView (inset-grouped, the
 * Settings app's own style) fed by CfgRow models; every row drives the same handle the ImGui page
 * drove, no new state. The card is a blur material, the amber is the tint, the controls are the
 * system's own switch / slider / segmented -- nothing hand-drawn except the glyphs the system can't
 * give us here. */
static UIView *g_cfg_dim;         /* the dim over the game: a tap is Done */
static UIView *g_cfg_card;        /* the card: a blur material, rounded, masked */
static UINavigationBar *g_cfg_nav;
static UISegmentedControl *g_cfg_segs;
static UITableView *g_cfg_tbl;
static NSMutableArray *g_cfg_rows;   /* the open page's CfgRow models */
static int g_cfg_page = -1;         /* the open page (-1: closed) */
static int g_cfg_last_page;
static const char *const cfg_tab_names[5] = { "Display", "Performance", "Game", "Controls", "Help" };

/* the frosted material every native card wears, one helper (the host keeps it, it never takes a touch) */
static UIVisualEffectView *blur_fill(UIView *host, UIBlurEffectStyle st) {
	UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:st]];
	v.frame = host.bounds;
	v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	v.userInteractionEnabled = NO;
	[host addSubview:v];
	[v release];
	return v;
}

/* one row's model: a kind, its texts, and the block that applies it (the same call the ImGui row took).
 * No ARC: every string is born owned (alloc/init or a literal) and the row releases them all. */
enum { R_HEAD = 0, R_SWITCH, R_SEG, R_SLIDER, R_BUTTON, R_NOTE, R_PAIR, R_TEXT };
@interface CfgRow : NSObject {
@public
	NSString *title, *detail, *right;
	NSArray *seg;
	int kind, sel, on, integral;
	float vmin, vmax, val;
	void (^act)(void);
	void (^num)(double);
	void (^pick)(int);
	void (^flip)(int);
}
@end
@implementation CfgRow
- (void)dealloc {
	[title release]; [detail release]; [right release]; [seg release];
	[act release]; [num release]; [pick release]; [flip release];
	[super dealloc];
}
@end
static CfgRow *cfg_row(int kind) {
	CfgRow *r = [[CfgRow alloc] init];
	r->kind = kind;
	[g_cfg_rows addObject:r];
	[r release];
	return r;
}
static void cfg_row_title(CfgRow *r, const char *s) { r->title = [[NSString alloc] initWithUTF8String:s]; }
static CfgRow *cfg_head(const char *s) { CfgRow *r = cfg_row(R_HEAD); cfg_row_title(r, s); return r; }
static CfgRow *cfg_note(const char *s) { CfgRow *r = cfg_row(R_NOTE); cfg_row_title(r, s); return r; }
static CfgRow *cfg_switch(const char *s, int on, void (^flip)(int)) {
	CfgRow *r = cfg_row(R_SWITCH); cfg_row_title(r, s); r->on = on; r->flip = [flip copy];
	return r;
}
static CfgRow *cfg_segrow(const char *s, NSArray *items, int sel, void (^pick)(int)) {
	CfgRow *r = cfg_row(R_SEG); cfg_row_title(r, s); r->seg = [items retain]; r->sel = sel; r->pick = [pick copy];
	return r;
}
static CfgRow *cfg_slider(const char *s, float vmin, float vmax, float val, int integral, void (^num)(double)) {
	CfgRow *r = cfg_row(R_SLIDER); cfg_row_title(r, s);
	r->vmin = vmin; r->vmax = vmax; r->val = fmaxf(vmin, fminf(vmax, val)); r->integral = integral; r->num = [num copy];
	return r;
}
static CfgRow *cfg_button(const char *s, void (^act)(void)) {
	CfgRow *r = cfg_row(R_BUTTON); cfg_row_title(r, s); r->act = [act copy];
	return r;
}

/* the five pages as models (every block the call the ImGui page made) */
static void cfg_page_display(void) {
	cfg_head("Picture");
	{
		NSMutableArray *items = [NSMutableArray array];
		int mx = gfx_gpu_render_scale_max(); if (mx > 3) mx = 3; if (mx < 1) mx = 1;
		for (int n = 1; n <= mx; n++) [items addObject:[NSString stringWithFormat:@"%dx", n]];
		CfgRow *r = cfg_segrow("Resolution", items, gfx_gpu_render_scale_wanted() - 1, ^(int i) {
			gfx_gpu_render_scale_request(i + 1);
		});
		r->detail = @"The Vita's 960 x 544, drawn at a multiple";
	}
	if (overlay_capable("widescreen")) {
		char cur[16]; settings_str("aspect_ratio", "native", cur, sizeof cur);
		int v = strcmp(cur, "21:9") ? (strcmp(cur, "32:9") ? 0 : 2) : 1;
		CfgRow *r = cfg_segrow("Widescreen", @[@"Off", @"21:9", @"32:9"], v, ^(int i) {
			settings_set_str("aspect_ratio", i == 1 ? "21:9" : i == 2 ? "32:9" : "native"); settings_save();
		});
		r->detail = @"More of the game at the sides";
	}
	if (overlay_capable("hud") && overlay_capable("widescreen")) {
		char cur[16]; settings_str("hud_layout", "edges", cur, sizeof cur);
		int v = strcmp(cur, "16:9") ? (strcmp(cur, "stretch") ? 0 : 2) : 1;
		cfg_segrow("The HUD with widescreen on", @[@"Edges", @"16:9", @"Stretched"], v, ^(int i) {
			settings_set_str("hud_layout", i == 1 ? "16:9" : i == 2 ? "stretch" : "edges"); settings_save();
		});
	}
	cfg_head("Quality");
	if (overlay_capable("fullres")) {
		CfgRow *r = cfg_switch("Full-resolution world", settings_int("full_res_world", 1), ^(int to) {
			settings_set_int("full_res_world", to); settings_save();
		});
		r->detail = @"The 3D world drawn at the screen's own resolution. Sharper, at a GPU cost.";
	}
	if (overlay_capable("ssao")) {
		{
			CfgRow *r = cfg_switch("Ambient occlusion", settings_int("ssao", 1), ^(int to) {
				settings_set_int("ssao", to); settings_save();
			});
			r->detail = @"Soft shadows where surfaces meet";
		}
		cfg_slider("Occlusion strength", 0, 200, (float)(settings_float("ssao_strength", 1.0) * 100.0), 1, ^(double v) {
			settings_set_float("ssao_strength", v / 100.0); settings_save();
		});
	}
	if (overlay_capable("fsr")) {
		int v = settings_int("fsr", 0) ? 2 : settings_int("post_aa", 1) ? 1 : 0;
		CfgRow *r = cfg_segrow("Anti-aliasing", @[@"Off", @"FXAA", @"FSR 3.1"], v, ^(int i) {
			settings_set_int("fsr", i == 2); settings_set_int("post_aa", i == 1); settings_save();
		});
		r->detail = @"FSR 3.1 is experimental";
	} else
		cfg_switch("Anti-aliasing (FXAA)", settings_int("post_aa", 1), ^(int to) {
			settings_set_int("post_aa", to); settings_save();
		});
	cfg_slider("Sharpening", 0, 100, (float)(settings_float("sharpen", 0.35) * 100.0), 1, ^(double v) {
		settings_set_float("sharpen", v / 100.0); settings_save();
	});
	{
		CfgRow *r = cfg_switch("Frame generation", settings_int("frame_gen", 0), ^(int to) {
			settings_set_int("frame_gen", to); settings_save();
		});
		r->detail = @"A frame between each two of the game's, for smoother motion. Adds a little delay.";
	}
	{
		static const int an[] = { 1, 2, 4, 8, 16 };
		int cur = settings_int("anisotropy", 16), v = 4;
		for (int i = 0; i < 5; i++) if (an[i] == cur) v = i;
		CfgRow *r = cfg_segrow("Texture filtering", @[@"Off", @"2x", @"4x", @"8x", @"16x"], v, ^(int i) {
			settings_set_int("anisotropy", an[i]); settings_save();
		});
		r->detail = @"Keeps textures crisp at an angle";
	}
	cfg_segrow("Shadow edges", @[@"Original", @"Soft", @"Softer"], settings_int("shadow_filter", 1), ^(int i) {
		settings_set_int("shadow_filter", i); settings_save();
	});
}
static void cfg_page_performance(void) {
	cfg_head("Overlays");
	{
		CfgRow *r = cfg_segrow("On-screen stats", @[@"Off", @"FPS", @"Full"], overlay_stats_level(), ^(int i) {
			overlay_set_stats(i);
		});
		r->detail = @"Frame rate and timings drawn over the game";
	}
	cfg_head("Now");
	{
		CfgRow *r = cfg_row(R_PAIR);
		r->title = [[NSString alloc] initWithUTF8String:"Frame rate"];
		r->right = [[NSString alloc] initWithUTF8String:"--"];
	}
}
static void cfg_page_game(void) {
	if (overlay_frame_rate_offered()) {
		CfgRow *r = cfg_segrow("Frame rate", @[@"30", @"60"], overlay_frame_rate_wanted() >= 60 ? 1 : 0, ^(int i) {
			overlay_frame_rate_request(i == 1 ? 60 : 30);
		});
		r->detail = @"60 is experimental: fixed-step parts can run fast";
	}
	if (overlay_lang_count() > 1) {
		NSMutableArray *items = [NSMutableArray array];
		for (int i = 0; i < overlay_lang_count(); i++) [items addObject:[NSString stringWithUTF8String:overlay_lang_label(i)]];
		CfgRow *r = cfg_segrow("Language", items, overlay_lang_get(), ^(int i) {
			overlay_lang_set(i);
		});
		r->detail = @"Applies the next time the game starts";
	}
	cfg_slider("Volume", 0, 100, overlay_opt_get("volume") * 100.0f, 1, ^(double v) {
		overlay_set_volume((float)(v / 100.0));
	});
	if (overlay_game_has("fov")) {
		CfgRow *r = cfg_slider("Field of view", 0.75, 1.5, overlay_opt_get("fov"), 0, ^(double v) { overlay_opt_set("fov", (float)v); });
		r->detail = @"1.00x is the game's own";
	}
	if (overlay_game_has("view_distance"))
		cfg_slider("View distance", 1.0, 3.0, overlay_opt_get("view"), 0, ^(double v) { overlay_opt_set("view", (float)v); });
	if (overlay_game_has("scenery_detail"))
		cfg_slider("Scenery detail", 1.0, 8.0, overlay_opt_get("scen"), 0, ^(double v) { overlay_opt_set("scen", (float)v); });
	if (overlay_game_has("character_detail"))
		cfg_slider("Character detail", 1.0, 8.0, overlay_opt_get("chr"), 0, ^(double v) { overlay_opt_set("chr", (float)v); });
	if (overlay_game_has("online")) {
		cfg_head("Online");
		CfgRow *r = cfg_switch("Play online", settings_int("online", 1), ^(int to) {
			settings_set_int("online", to); settings_save();
		});
		r->detail = @"With other Project Nativ players. Applies the next time the game starts.";
	}
}
static void cfg_page_controls(void) {
	cfg_head("The on-screen pad");
	cfg_switch("On-screen controls", touchpad_on(), ^(int to) { touchpad_set_on(to); });
	{
		CfgRow *r = cfg_switch("Second stick", window_touchpad_rstick(), ^(int to) {
			settings_set_int("touchpad_rstick", to); settings_save();
		});
		r->detail = @"A floating stick in the lower right corner";
	}
	cfg_slider("Pad size", 60, 160, (float)touchpad_scale(), 1, ^(double v) { touchpad_set_scale((int)(v + 0.5)); });
	{
		CfgRow *r = cfg_switch("Left-handed", touchpad_mirror(), ^(int to) { touchpad_set_mirror(to); });
		r->detail = @"The stick on the right, the buttons on the left";
	}
	cfg_slider("Pad opacity", 10, 90, (float)settings_int("touchpad_opacity", 42), 1, ^(double v) {
		settings_set_int("touchpad_opacity", (int)(v + 0.5)); settings_save();
	});
	if (overlay_gyro_present()) {
		cfg_head("Motion");
		{
			CfgRow *r = cfg_switch("Gyro", overlay_gyro_get(), ^(int to) { overlay_gyro_set(to); });
			r->detail = @"The phone stands in for the Vita's motion sensor";
		}
		cfg_segrow("A level phone is a Vita held", @[@"Upright", @"Flat"], overlay_gyro_pose_get(), ^(int i) { overlay_gyro_pose_set(i == 1); });
		cfg_slider("Gyro sensitivity", 0.25, 3.0, overlay_opt_get("gyro_sens"), 0, ^(double v) { overlay_opt_set("gyro_sens", (float)v); });
		cfg_button("Recentre the gyro", ^{ overlay_gyro_recentre(); ios_ui_haptic(0); });
	}
	cfg_head("The game's controls");
	const int n = overlay_controls_count();
	for (int i = 0; i < n; i++) {
		const char *a = "", *p = "";
		overlay_controls_row(i, &a, &p);
		CfgRow *r = cfg_row(R_PAIR);
		r->title = [[NSString alloc] initWithUTF8String:a ? a : ""];
		r->right = [[NSString alloc] initWithUTF8String:(p && *p) ? p : ""];
	}
}
static void cfg_page_help(void) {
	cfg_head("The controls");
	cfg_note("Hold or drag the lower left for the movement stick, or the lower right for the camera stick. A quick tap still touches the game. Left-handed mode swaps the sides.");
	cfg_note("The picture itself is the Vita's touch screen: tap and drag it as you would the real thing.");
	cfg_note("Tap Menu at the top centre for the quick menu. Game > All settings opens these pages and pauses the game. Done resumes play.");
	cfg_head("About");
	{
		CfgRow *r = cfg_row(R_TEXT);
		r->title = [[NSString alloc] initWithUTF8String:"Project Nativ"];
		r->detail = [[NSString alloc] initWithUTF8String:"This PS Vita game, statically recompiled to native code, running on this phone's own CPU and GPU."];
	}
	cfg_note("The eye at the top left hides or shows the pad. The eye and Menu stay available when the pad is hidden.");
}

static void cfg_close(void);

static CGFloat text_height(NSString *text, CGFloat width, UIFont *font) {
    if (!text.length) return 0;
    return ceil([text boundingRectWithSize:CGSizeMake(fmax(40, width), CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
        attributes:@{NSFontAttributeName:font} context:nil].size.height);
}
static CGFloat cfg_height(CfgRow *row, CGFloat width) {
    const CGFloat inner = fmax(80, width - 32);
    const CGFloat titleWidth = row->kind == R_SWITCH ? inner - 64 : row->kind == R_PAIR ? inner * 0.52 : inner;
    const CGFloat title = text_height(row->title, titleWidth, [UIFont systemFontOfSize:15]);
    const CGFloat detail = text_height(row->detail, titleWidth, [UIFont systemFontOfSize:12]);
    if (row->kind == R_HEAD) return 36;
    if (row->kind == R_NOTE) return fmax(44, text_height(row->title, inner, [UIFont systemFontOfSize:13]) + 24);
    if (row->kind == R_PAIR) return fmax(48, fmax(title, text_height(row->right, inner * 0.45, [UIFont systemFontOfSize:13])) + 24);
    return fmax(row->kind == R_SWITCH ? 56 : 48, 24 + title + (detail ? detail + 4 : 0) +
        ((row->kind == R_SEG || row->kind == R_SLIDER) ? 42 : 0));
}

/* A reused cell owns its model and its control. No global target list, dangling FPS label,
 * stacked sliders, stale model values, or frames guessed before UITableView lays out the cell. */
@interface CfgCell : UITableViewCell {
@public
    CfgRow *model;
    UILabel *name, *note, *value;
    UIControl *control;
}
- (void)configure:(CfgRow *)row;
@end
@implementation CfgCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (self) {
        name = [[UILabel alloc] init]; note = [[UILabel alloc] init]; value = [[UILabel alloc] init];
        name.numberOfLines = note.numberOfLines = value.numberOfLines = 0;
        note.font = [UIFont systemFontOfSize:12]; note.textColor = [UIColor secondaryLabelColor];
        value.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
        value.textColor = [UIColor secondaryLabelColor]; value.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:name]; [self.contentView addSubview:note]; [self.contentView addSubview:value];
        [name release]; [note release]; [value release];
    }
    return self;
}
- (void)dealloc { [model release]; [super dealloc]; }
- (NSString *)formattedValue {
    return model->integral ? [NSString stringWithFormat:@"%.0f%%", model->val] : [NSString stringWithFormat:@"%.2fx", model->val];
}
- (void)changed:(UIControl *)sender {
    if (model->kind == R_SWITCH) {
        model->on = ((UISwitch *)sender).on; ios_ui_haptic(0);
        if (model->flip) model->flip(model->on);
    } else if (model->kind == R_SEG) {
        model->sel = (int)((UISegmentedControl *)sender).selectedSegmentIndex; ios_ui_haptic(0);
        if (model->pick) model->pick(model->sel);
    } else if (model->kind == R_SLIDER) {
        model->val = ((UISlider *)sender).value;
        if (model->integral) model->val = roundf(model->val);
        value.text = [self formattedValue];
    }
}
- (void)commit:(UISlider *)slider {
    [self changed:slider];
    if (model->num) model->num(model->val);
}
- (void)choose:(UIButton *)button {
    CfgRow *row = model;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:row->title message:row->detail preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSUInteger i = 0; i < row->seg.count; i++) {
        const int index = (int)i;
        [sheet addAction:[UIAlertAction actionWithTitle:row->seg[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action; row->sel = index; if (row->pick) row->pick(index);
            [button setTitle:row->seg[index] forState:UIControlStateNormal];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = button;
    sheet.popoverPresentationController.sourceRect = button.bounds;
    [g_win.rootViewController presentViewController:sheet animated:YES completion:nil];
}
- (void)configure:(CfgRow *)row {
    [control removeFromSuperview]; control = nil;
    [row retain]; [model release]; model = row;
    name.text = row->title; note.text = row->detail; value.text = nil;
    name.font = [UIFont systemFontOfSize:row->kind == R_HEAD ? 13 : row->kind == R_NOTE ? 13 : 15
        weight:row->kind == R_HEAD || row->kind == R_TEXT ? UIFontWeightSemibold : UIFontWeightRegular];
    name.textColor = row->kind == R_HEAD ? rgba(240, 192, 96, 1) : row->kind == R_NOTE ? [UIColor secondaryLabelColor] : [UIColor labelColor];
    self.selectionStyle = row->kind == R_BUTTON ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    self.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.accessoryType = row->kind == R_BUTTON ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    if (row->kind == R_SWITCH) {
        UISwitch *toggle = [[[UISwitch alloc] init] autorelease];
        toggle.on = row->on; toggle.onTintColor = rgba(240, 192, 96, 1); control = toggle;
    } else if (row->kind == R_SEG && row->seg.count <= 5) {
        UISegmentedControl *segments = [[[UISegmentedControl alloc] initWithItems:row->seg] autorelease];
        segments.selectedSegmentIndex = row->sel >= 0 && row->sel < (int)row->seg.count ? row->sel : UISegmentedControlNoSegment;
        segments.selectedSegmentTintColor = rgba(240, 192, 96, 1);
        [segments setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor blackColor]} forState:UIControlStateSelected];
        control = segments;
    } else if (row->kind == R_SEG) {
        UIButton *choice = [UIButton buttonWithType:UIButtonTypeSystem];
        const NSInteger selected = row->sel >= 0 && row->sel < (int)row->seg.count ? row->sel : 0;
        [choice setTitle:row->seg[selected] forState:UIControlStateNormal];
        choice.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [choice addTarget:self action:@selector(choose:) forControlEvents:UIControlEventTouchUpInside];
        control = choice;
    } else if (row->kind == R_SLIDER) {
        UISlider *slider = [[[UISlider alloc] init] autorelease];
        slider.minimumValue = row->vmin; slider.maximumValue = row->vmax; slider.value = row->val;
        slider.minimumTrackTintColor = rgba(240, 192, 96, 1);
        [slider addTarget:self action:@selector(commit:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        value.text = [self formattedValue]; control = slider;
    } else if (row->kind == R_PAIR) value.text = row->right;
    if (control) {
        [control addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
        control.accessibilityLabel = row->title; control.accessibilityHint = row->detail;
        [self.contentView addSubview:control];
    }
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!model) return;
    const CGFloat width = self.contentView.bounds.size.width, inner = width - 32;
    CGFloat titleWidth = inner;
    if (model->kind == R_SWITCH) titleWidth -= 64;
    if (model->kind == R_PAIR) titleWidth *= 0.52;
    if (model->kind == R_SLIDER) titleWidth -= 80;
    const CGFloat titleHeight = text_height(model->title, titleWidth, name.font);
    name.frame = CGRectMake(16, 12, titleWidth, titleHeight);
    const CGFloat noteHeight = text_height(model->detail, titleWidth, note.font);
    note.frame = CGRectMake(16, 16 + titleHeight, titleWidth, noteHeight);
    value.frame = CGRectZero;
    if (model->kind == R_SWITCH) control.frame = CGRectMake(width - 67, (self.contentView.bounds.size.height - 31) / 2, 51, 31);
    if (model->kind == R_SEG || model->kind == R_SLIDER) {
        const CGFloat y = 16 + titleHeight + (noteHeight ? noteHeight + 4 : 0);
        control.frame = CGRectMake(16, y, inner, 32);
    }
    if (model->kind == R_SLIDER) value.frame = CGRectMake(width - 92, 12, 76, titleHeight);
    if (model->kind == R_PAIR) value.frame = CGRectMake(16 + inner * 0.55, 12, inner * 0.45,
        fmax(titleHeight, text_height(value.text, inner * 0.45, value.font)));
}
@end

@interface CfgCenter : NSObject <UITableViewDataSource, UITableViewDelegate>
- (void)done;
@end
static CfgCenter *g_cfg_center;
@implementation CfgCenter
- (void)done { ios_ui_haptic(0); cfg_close(); }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table; (void)section; return g_cfg_rows.count;
}
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    return cfg_height(g_cfg_rows[path.row], table.bounds.size.width - 40);
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    CfgCell *cell = [table dequeueReusableCellWithIdentifier:@"setting"];
    if (!cell) cell = [[[CfgCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"setting"] autorelease];
    [cell configure:g_cfg_rows[path.row]];
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    CfgRow *row = [g_cfg_rows[path.row] retain];
    if (row->kind == R_BUTTON && row->act) { ios_ui_haptic(0); row->act(); }
    [row release]; [table deselectRowAtIndexPath:path animated:YES];
}
@end

static void cfg_close(void) {
	if (!g_cfg_dim) return;
	g_cfg_dim.hidden = YES; g_cfg_card.hidden = YES;
	g_cfg_page = -1;
	overlay_close();   /* resumes, exactly the close the ImGui menu's Resume took */
}
static void cfg_page_build(int tab) {
	[g_cfg_rows removeAllObjects];
	switch (tab) {
	case 0: cfg_page_display(); break;
	case 1: cfg_page_performance(); break;
	case 2: cfg_page_game(); break;
	case 3: cfg_page_controls(); break;
	default: cfg_page_help(); break;
	}
}
static void cfg_rebuild(void) {
	const int tab = g_cfg_page >= 0 && g_cfg_page < 5 ? g_cfg_page : 0;
	g_cfg_last_page = tab;
	cfg_page_build(tab);
	g_cfg_nav.topItem.title = [NSString stringWithUTF8String:cfg_tab_names[tab]];
	g_cfg_segs.selectedSegmentIndex = tab;
	[g_cfg_tbl reloadData];
	[g_cfg_tbl setContentOffset:CGPointZero animated:NO];
}
static void cfg_make(void) {
	if (g_cfg_dim) return;
	g_cfg_rows = [[NSMutableArray alloc] init];
	g_cfg_center = [[CfgCenter alloc] init];
	g_cfg_dim = [[UIView alloc] initWithFrame:g_host.bounds];
	g_cfg_dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	g_cfg_dim.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.55f];
	tap_on(g_cfg_dim, ^{ cfg_close(); });
	[g_host addSubview:g_cfg_dim];
	[g_cfg_dim release];
	const CGRect hb = g_host.bounds;
	g_cfg_card = [[UIView alloc] initWithFrame:CGRectInset(hb, 14, 14)];
	g_cfg_card.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	g_cfg_card.layer.cornerRadius = 16.0f;
	g_cfg_card.layer.masksToBounds = YES;
	blur_fill(g_cfg_card, UIBlurEffectStyleSystemMaterialDark);
	[g_host addSubview:g_cfg_card];
	[g_cfg_card release];
	/* the navigation bar: the page's name, Done at the right (the system's own button, the amber tint) */
	g_cfg_nav = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, g_cfg_card.bounds.size.width, 44)];
	g_cfg_nav.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	g_cfg_nav.barStyle = UIBarStyleBlack;
	g_cfg_nav.translucent = YES;
	g_cfg_nav.tintColor = rgba(240, 192, 96, 1.0f);
	{
		UIImage *empty = [UIImage new];
		[g_cfg_nav setBackgroundImage:empty forBarMetrics:UIBarMetricsDefault];
		g_cfg_nav.shadowImage = empty;
		[empty release];
	}
	UINavigationItem *it = [[UINavigationItem alloc] initWithTitle:@"Display"];
	it.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:g_cfg_center action:@selector(done)] autorelease];
	[g_cfg_nav pushNavigationItem:it animated:NO];
	[it release];
	[g_cfg_card addSubview:g_cfg_nav];
	[g_cfg_nav release];
	/* the five pages: a real segmented control */
	g_cfg_segs = [[UISegmentedControl alloc] initWithFrame:CGRectMake(14, 48, g_cfg_card.bounds.size.width - 28, 32)];
	g_cfg_segs.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	g_cfg_segs.backgroundColor = [UIColor tertiarySystemFillColor];
	g_cfg_segs.selectedSegmentTintColor = rgba(240, 192, 96, 0.92f);
	[g_cfg_segs setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor labelColor]} forState:UIControlStateNormal];
	[g_cfg_segs setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor blackColor]} forState:UIControlStateSelected];
	for (int i = 0; i < 5; i++) [g_cfg_segs insertSegmentWithTitle:[NSString stringWithUTF8String:cfg_tab_names[i]] atIndex:i animated:NO];
	__block UISegmentedControl *wsg = g_cfg_segs;
	control_on(g_cfg_segs, UIControlEventValueChanged, ^{ ios_ui_haptic(0); g_cfg_page = (int)wsg.selectedSegmentIndex; cfg_rebuild(); });
	[g_cfg_card addSubview:g_cfg_segs];
	[g_cfg_segs release];
	/* the page itself: a real table, inset-grouped (the Settings app's own look) */
	g_cfg_tbl = [[UITableView alloc] initWithFrame:CGRectMake(10, 86, g_cfg_card.bounds.size.width - 20, g_cfg_card.bounds.size.height - 96) style:UITableViewStyleInsetGrouped];
	g_cfg_tbl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	g_cfg_tbl.dataSource = g_cfg_center;
	g_cfg_tbl.delegate = g_cfg_center;
	g_cfg_tbl.backgroundColor = [UIColor clearColor];
	g_cfg_tbl.separatorColor = rgba(255, 255, 255, 0.08f);
	[g_cfg_card addSubview:g_cfg_tbl];
	[g_cfg_tbl release];
	chrome_log("    chrome: settings center made (%.0f x %.0f card)", g_cfg_card.bounds.size.width, g_cfg_card.bounds.size.height);
}
void ios_ui_settings_open(int tab) {
	if (!g_installed) return;
	if (![NSThread isMainThread]) { const int t = tab; dispatch_async(dispatch_get_main_queue(), ^{ ios_ui_settings_open(t); }); return; }
	bar_up_close_all(); touchpad_cancel_all(); ios_ui_chrome_cancel_controls();
	overlay_open();   /* the menu's own open state: the pause, the input routing, the audio mute */
	if (!g_cfg_dim) cfg_make();
	if (tab >= 0 && tab < 5) g_cfg_page = tab; else if (g_cfg_page < 0) g_cfg_page = g_cfg_last_page;
	chrome_layout();
	cfg_rebuild();
	[g_host bringSubviewToFront:g_cfg_dim];
	[g_host bringSubviewToFront:g_cfg_card];
	[g_host bringSubviewToFront:g_toast_host];   /* the toasts answer over it, as they always did */
	g_cfg_dim.hidden = NO; g_cfg_card.hidden = NO;
	ios_ui_haptic(0);
	chrome_log("    chrome: settings center open (page %d)", g_cfg_page);
}

/* window.c's tp_layout hands its own numbers here (the same TpVisual both pictures read): each
 * button's touch area set to its control's shape -- a pill's box, or a 1.18-radius circle -- and
 * shown while the pad is on, hidden the moment it isn't */
void ios_ui_pad_layout(void) {
	if (!g_installed || !g_win) return;
	if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ ios_ui_pad_layout(); }); return; }
	const TpVisual *tv = touchpad_visuals();
	if (g_pad_disabled) {   /* theImGui pad is drawing: nothing of ours may take a touch or a pixel */
		g_pad_layer.hidden = YES;
		for (int i = 0; i < 8; i++) if (g_pad_hits[i]) g_pad_hits[i].hidden = YES;
		return;
	}
	g_pad_layer.hidden = !tv->on;   /* (its drawing checks the same flag: this hides the canvas itself) */
	chrome_log("    chrome: pad layout (%s) %d buttons, canvas %.0fx%.0f at (%.0f, %.0f)", tv->on ? "on" : "off", tv->nb,
	           g_pad_layer.bounds.size.width, g_pad_layer.bounds.size.height, g_pad_layer.frame.origin.x, g_pad_layer.frame.origin.y);
	for (int i = 0; i < 8; i++) {
		PadBtn *v = g_pad_hits[i];
		if (!v) {
			if (!tv->on || i >= tv->nb) continue;
			v = [[PadBtn alloc] initWithFrame:CGRectZero];
			v->idx = i;
            v.opaque = NO;
			[g_host addSubview:v];
			[v release];   /* the host owns it */
			g_pad_hits[i] = v;
		}
		if (!tv->on || i >= tv->nb) { if (v->down) touchpad_native_release(10 + i); v.hidden = YES; v->down = 0; continue; }
		const TpButton *b = &tv->b[i];
		v->down = 0; /* a geometry change has released the old layout's fingers */
		v->pill = b->pill;
		if (b->pill) v.frame = CGRectMake(b->x - b->hw, b->y - b->hh, 2 * b->hw, 2 * b->hh);
		else { const float e = b->r * 1.18f; v.frame = CGRectMake(b->x - e, b->y - e, 2 * e, 2 * e); }
		v.hidden = NO;
        v.isAccessibilityElement = YES;
        static NSString *const names[8] = {@"Triangle", @"Circle", @"Cross", @"Square", @"Left shoulder", @"Right shoulder", @"Start", @"Select"};
        v.accessibilityLabel = names[i]; v.accessibilityTraits = UIAccessibilityTraitButton;
		chrome_log("    chrome:   btn %d -> (%.0f, %.0f, %.0f x %.0f) %s", i, v.frame.origin.x, v.frame.origin.y, v.frame.size.width, v.frame.size.height, b->pill ? "pill" : "round");
	}
}

/* the one object that holds the actions (target-action wants an NSObject; installed once, never
 * released: UIKit's targets and delegates are unretained, so this stays for the app's own life) */
@interface ChromeCenter : NSObject
@end
static ChromeCenter *g_center;

@implementation ChromeCenter
- (void)eye:(id)sender {
	(void)sender;
	overlay_intro_dismiss();
	const int on = touchpad_on();
	touchpad_set_on(on ? 0 : 1);
	overlay_toast_titled(on ? "Controls off" : "Controls on", on ? "The eye brings them back." : "", 2.4);
	ios_ui_haptic(0);   /* the taptic engine answers the flip, as a native switch would */
	g_eye_on = -1; eye_look();   /* the menu's own wording: the toast routes back here, natively */
}
- (void)pill:(id)sender { (void)sender; ios_ui_bar_open(); }
- (void)pulled:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateChanged && [pan translationInView:g_host].y > 10) ios_ui_bar_open();
}
- (void)tick:(CADisplayLink *)link {
    (void)link;
    if (!g_installed || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    if (!g_win.rootViewController.presentedViewController && g_win.subviews.lastObject != g_host) [g_win bringSubviewToFront:g_host];
    chrome_layout();
    if (g_eye) eye_look();
    const int reasons = overlay_pad_hidden();
    const BOOL hideChrome = overlay_is_open() || bar_visible() || (reasons & 8);
    g_eye.hidden = hideChrome; g_pull_pill.hidden = hideChrome;
    const BOOL hidePad = !touchpad_on() || reasons || bar_visible();
    for (int i = 0; i < 8; i++) if (g_pad_hits[i]) {
        if (hidePad && g_pad_hits[i]->down) { g_pad_hits[i]->down = 0; touchpad_native_release(10 + i); }
        g_pad_hits[i].hidden = hidePad || g_pad_disabled;
    }
    if (g_pad_layer && !g_pad_disabled) [g_pad_layer sync];
    /* A controller or keyboard can open/close the same settings state. Special game cards remain ImGui. */
    const BOOL wantsSettings = overlay_native_settings_wanted();
    if (wantsSettings && (!g_cfg_card || g_cfg_card.hidden)) ios_ui_settings_open(overlay_native_settings_page());
    if (!wantsSettings && g_cfg_card && !g_cfg_card.hidden) {
        g_cfg_card.hidden = YES; g_cfg_dim.hidden = YES; g_cfg_page = -1;
    }
    if (overlay_is_open() && bar_visible()) bar_up_close_all();
    if (g_bar_shown && g_panel_tab < 0 && chrome_now() - g_bar_last > 4) bar_up_close_all();
    osd_tick(); pause_tick(); intro_tick();
    static double lastStats;
    const double now = chrome_now();
    if (now - lastStats > 0.25) {
        lastStats = now;
        if (g_cfg_card && !g_cfg_card.hidden && g_cfg_page == 1) {
            for (CfgCell *cell in g_cfg_tbl.visibleCells) if ([cell->model->title isEqualToString:@"Frame rate"]) {
                cell->value.text = [NSString stringWithFormat:@"%.0f fps", overlay_fps()];
            }
        }
    }
}

@end

/* ---- the toasts: ImGui's cards, UIKit's own drawing ---------------------------------------- */
static void toast_show(NSString *title, NSString *body, double seconds) {
	if (!g_toast_stack) return;
	if (g_toast_stack.arrangedSubviews.count >= 3) {   /* three at most, the oldest goes (overlay.cpp's rule) */
		UIView *old = g_toast_stack.arrangedSubviews[0];
		[g_toast_stack removeArrangedSubview:old]; [old removeFromSuperview];
	}
	UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
	card.backgroundColor = [UIColor colorWithRed:18/255.0 green:20/255.0 blue:26/255.0 alpha:0.94f];
	card.layer.cornerRadius = 8.0f;
	card.clipsToBounds = YES;
	card.userInteractionEnabled = NO;
	UIView *edge = [[UIView alloc] initWithFrame:CGRectZero];   /* the amber bar down the left, as the ImGui card had */
	edge.backgroundColor = [UIColor colorWithRed:255/255.0 green:186/255.0 blue:72/255.0 alpha:1.0f];
	UILabel *t = [[UILabel alloc] initWithFrame:CGRectZero];
	t.text = title; t.hidden = title.length == 0;
	t.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
	t.textColor = [UIColor colorWithRed:255/255.0 green:196/255.0 blue:92/255.0 alpha:1.0f];
	UILabel *b = [[UILabel alloc] initWithFrame:CGRectZero];
	b.text = body; b.hidden = body.length == 0;
	b.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
	b.textColor = [UIColor colorWithRed:232/255.0 green:234/255.0 blue:240/255.0 alpha:1.0f];
	b.numberOfLines = 0;
	UIStackView *in = [[UIStackView alloc] initWithFrame:CGRectZero];
	in.axis = UILayoutConstraintAxisVertical; in.spacing = 2.0f;
	[in addArrangedSubview:t]; [in addArrangedSubview:b];
	[card addSubview:edge]; [card addSubview:in];
	edge.translatesAutoresizingMaskIntoConstraints = NO; in.translatesAutoresizingMaskIntoConstraints = NO; card.translatesAutoresizingMaskIntoConstraints = NO;
	[edge.leadingAnchor constraintEqualToAnchor:card.leadingAnchor].active = YES;
	[edge.topAnchor constraintEqualToAnchor:card.topAnchor].active = YES;
	[edge.bottomAnchor constraintEqualToAnchor:card.bottomAnchor].active = YES;
	[edge.widthAnchor constraintEqualToConstant:3.0f].active = YES;
	[in.leadingAnchor constraintEqualToAnchor:edge.trailingAnchor constant:8.0f].active = YES;
	[in.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10.0f].active = YES;
	[in.topAnchor constraintEqualToAnchor:card.topAnchor constant:8.0f].active = YES;
	[in.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-8.0f].active = YES;
	[g_toast_stack addArrangedSubview:card];
	[card release]; [edge release]; [in release]; [t release]; [b release];   /* the hierarchy owns them all */
	card.alpha = 0.0f;
	[UIView animateWithDuration:0.18 animations:^{ card.alpha = 1.0f; }];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[UIView animateWithDuration:0.30 animations:^{ card.alpha = 0.0f; } completion:^(BOOL done) {
			(void)done;
			[g_toast_stack removeArrangedSubview:card]; [card removeFromSuperview];
		}];
	});
}

/* called from overlay.cpp's overlay_toast_titled, any thread: the text is copied here and now
 * (the caller's storage isn't ours to keep), the card built on the main thread */
void ios_ui_chrome_toast(const char *title, const char *body, double seconds) {
	if (!g_installed) return;
	NSString *t = [[NSString alloc] initWithUTF8String:(title ? title : "")];
	NSString *b = [[NSString alloc] initWithUTF8String:(body ? body : "")];
	dispatch_async(dispatch_get_main_queue(), ^{
		toast_show(t, b, seconds);
		[t release]; [b release];
	});
}

/* ---- install / placement ------------------------------------------------------------------ */
/* Called before each present on the UI thread, including while menus are open. SDL's logical
 * size can remain unchanged while its Metal UIView/drawable returns in portrait after resume. */
int ios_ui_chrome_sync_window(int *width, int *height) {
    if (!g_win || ![NSThread isMainThread]) return 0;
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return 0;
    const CGRect bounds = g_win.bounds;
    if (bounds.size.width <= 0 || bounds.size.height <= 0) return 0;
    UIView *game = g_win.rootViewController.view;
    if (!game || !game.superview || g_win.rootViewController.transitionCoordinator) return 0;
    /* All supported orientations are landscape. Wait for UIKit to finish its window transition. */
    if (bounds.size.height > bounds.size.width) return 0;
    const CGRect frame = [game.superview convertRect:bounds fromView:g_win];
    BOOL repaired = NO;
    if (!CGRectEqualToRect(game.frame, frame)) {
        game.frame = frame; [game setNeedsLayout]; repaired = YES;
    }
    [game layoutIfNeeded];
    if ([game.layer isKindOfClass:[CAMetalLayer class]]) {
        CAMetalLayer *metal = (CAMetalLayer *)game.layer;
        const CGFloat scale = g_win.screen.nativeScale;
        const CGSize drawable = CGSizeMake(round(game.bounds.size.width * scale), round(game.bounds.size.height * scale));
        if (!CGSizeEqualToSize(metal.drawableSize, drawable)) {
            metal.drawableSize = drawable; repaired = YES;
        }
    }
    *width = (int)round(bounds.size.width); *height = (int)round(bounds.size.height);
    if (g_host) {
        g_host.frame = bounds;
        if (!g_win.rootViewController.presentedViewController && g_win.subviews.lastObject != g_host) [g_win bringSubviewToFront:g_host];
    }
    if (repaired) chrome_log("    chrome: repaired game view to %.0fx%.0f points, %.1fx drawable", bounds.size.width, bounds.size.height, g_win.screen.nativeScale);
    return 1;
}

void ios_ui_chrome_install(void *native_window) {
    if (g_installed || !native_window || ![NSThread isMainThread]) return;
    g_win = (UIWindow *)native_window;
    const char *off = getenv("RECOMP_NATIVE_CHROME");
    if (off && off[0] == '0' && off[1] == '\0') return;
    UIWindow *win = g_win;
    g_host = [[ChromeHost alloc] initWithFrame:win.bounds];
    g_host.backgroundColor = [UIColor clearColor];
    g_host.opaque = NO; g_host.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    g_host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [win addSubview:g_host]; [g_host release];

	{
		const char *np = getenv("RECOMP_NATIVE_PAD");   /* =0: the native pad never comes up (the ImGui pad and the finger path again) */
		g_pad_disabled = np && np[0] == '0' && np[1] == '\0';
	}
	chrome_log("    chrome: install (window %p, %.0fx%.0f bounds; host %p (%s); pad %s)", win, win.bounds.size.width, win.bounds.size.height,
	           g_host, "chrome container", g_pad_disabled ? "OFF (RECOMP_NATIVE_PAD=0)" : "on");

	g_center = [[ChromeCenter alloc] init];   /* kept: UIKit's targets and delegates don't retain */
	g_eye = [[ChromeButton buttonWithType:UIButtonTypeCustom] retain];   /* +1 (buttonType autoreleases): the window's, after addSubview */
	g_eye.frame = CGRectMake(8, 8, 46, 32);   /* tp_layout's own call moves it to the corner's margin */
	g_eye.layer.cornerRadius = 11.0f;
	g_eye.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.40f].CGColor;   /* the chip's hairline (40%: findable on a black scene too -- test30's 24% vanished into the game's letterbox) */
	g_eye.layer.borderWidth = 0.75f;
	[g_eye addTarget:g_center action:@selector(eye:) forControlEvents:UIControlEventTouchUpInside];
	[g_host addSubview:g_eye];
	[g_host bringSubviewToFront:g_eye];
	[g_eye release];   /* the host owns it from here */
	g_eye_on = -1; eye_look();

	{	/* the pull's pill: the old ImGui tab asked for a tap, and the top edge's swipe is iOS's own
		 * (notifications). A small handle at the top centre, tappable, gone while the strip is down */
		g_pull_pill = [[ChromeButton buttonWithType:UIButtonTypeCustom] retain];
		g_pull_pill.frame = CGRectMake(win.bounds.size.width * 0.5f - 32, 5, 64, 32);
		g_pull_pill.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
		g_pull_pill.layer.cornerRadius = 12.0f;
        [g_pull_pill setTitle:@"Menu" forState:UIControlStateNormal];
        g_pull_pill.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        g_pull_pill.accessibilityLabel = @"Open quick menu";
		g_pull_pill.backgroundColor = rgba(16, 18, 24, 0.78f);   /* readable over both dark and bright scenes */
		g_pull_pill.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.35f].CGColor;
		g_pull_pill.layer.borderWidth = 0.5f;
		[g_pull_pill addTarget:g_center action:@selector(pill:) forControlEvents:UIControlEventTouchUpInside];
		[g_host addSubview:g_pull_pill];
		[g_host bringSubviewToFront:g_pull_pill];
		[g_pull_pill release];
		chrome_log("    chrome: pull pill made (%.0f x %.0f at (%.0f, %.0f), window %.0f x %.0f)",
		           g_pull_pill.frame.size.width, g_pull_pill.frame.size.height, g_pull_pill.frame.origin.x, g_pull_pill.frame.origin.y,
		           win.bounds.size.width, win.bounds.size.height);
	}

    UIPanGestureRecognizer *pull = [[UIPanGestureRecognizer alloc] initWithTarget:g_center action:@selector(pulled:)];
    [g_pull_pill addGestureRecognizer:pull]; [pull release];

	{	/* the pad: cached control artwork, synced by the display link, and its touch
		 * areas (picked up by tp_layout's own call, ios_ui_pad_layout, as its numbers change) */
		memset(g_pad_hits, 0, sizeof g_pad_hits);
		g_pad_layer = [[PadLayer alloc] initWithFrame:g_host.bounds];
		g_pad_layer.opaque = NO;
		g_pad_layer.userInteractionEnabled = NO;   /* touches fall through to the game, always */
		g_pad_layer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		g_pad_layer.hidden = YES;   /* until tp_layout says the pad is on */
		[g_host insertSubview:g_pad_layer atIndex:0];
		[g_pad_layer release];   /* the host owns it */
	}

	g_toast_host = [[UIView alloc] initWithFrame:CGRectZero];
	g_toast_host.userInteractionEnabled = NO;   /* toasts never take a touch */
	g_toast_host.translatesAutoresizingMaskIntoConstraints = NO;
	[g_host addSubview:g_toast_host];
	[g_toast_host.topAnchor constraintEqualToAnchor:g_host.safeAreaLayoutGuide.topAnchor constant:8.0f].active = YES;
	[g_toast_host.trailingAnchor constraintEqualToAnchor:g_host.safeAreaLayoutGuide.trailingAnchor constant:-10.0f].active = YES;
	[g_toast_host.widthAnchor constraintEqualToConstant:300.0f].active = YES;
	[g_toast_host.bottomAnchor constraintLessThanOrEqualToAnchor:g_host.safeAreaLayoutGuide.bottomAnchor constant:-8].active = YES;
	[g_toast_host release];   /* as above: the host owns it */

	g_toast_stack = [[UIStackView alloc] initWithFrame:CGRectZero];
	g_toast_stack.axis = UILayoutConstraintAxisVertical;
	g_toast_stack.alignment = UIStackViewAlignmentFill;
	g_toast_stack.spacing = 6.0f;
	g_toast_stack.userInteractionEnabled = NO;
	g_toast_stack.translatesAutoresizingMaskIntoConstraints = NO;
	[g_toast_host addSubview:g_toast_stack];
	[g_toast_stack.topAnchor constraintEqualToAnchor:g_toast_host.topAnchor].active = YES;
	[g_toast_stack.leadingAnchor constraintEqualToAnchor:g_toast_host.leadingAnchor].active = YES;
	[g_toast_stack.trailingAnchor constraintEqualToAnchor:g_toast_host.trailingAnchor].active = YES;
	[g_toast_stack.bottomAnchor constraintEqualToAnchor:g_toast_host.bottomAnchor].active = YES;
	[g_toast_stack release];

	CADisplayLink *dl = [CADisplayLink displayLinkWithTarget:g_center selector:@selector(tick:)];
	[dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];   /* the menu's toggle reaches the eye */

	g_installed = 1;
	chrome_layout();
	chrome_log("    chrome: test34 installed above SDL Metal view (%.0fx%.0f points)", win.bounds.size.width, win.bounds.size.height);
}

/* tp_layout calls this with the eye's own x (the leftmost margin) -- the eye and the shoulder pill
 * can never drift apart, the same place ImGui's chip derived (overlay.cpp) while it held the slot */
void ios_ui_chrome_place(float x) {
    if (!g_eye || ![NSThread isMainThread]) return;
    CGRect frame = g_eye.frame; frame.origin.x = x; g_eye.frame = frame;
}

static void chrome_layout(void) {
    if (!g_host) return;
    const CGRect bounds = g_host.bounds, safe = chrome_safe_rect();
    const CGFloat top = 5 + g_win.safeAreaInsets.top;
    const CGFloat margin = bounds.size.height * 0.025 + fmin(g_win.safeAreaInsets.left, bounds.size.height * 0.03);
    g_eye.frame = CGRectMake(margin, top, 46, 32);
    g_pull_pill.frame = CGRectMake(bounds.size.width / 2 - 32, top, 64, 32);
    g_pad_layer.frame = bounds;
    if (g_shield) g_shield.frame = bounds;
    if (g_bar) {
        const CGFloat height = 44 + g_win.safeAreaInsets.top;
        g_bar.frame = CGRectMake(0, g_bar_shown ? 0 : -height, bounds.size.width, height);
        CGFloat x = safe.origin.x + 8;
        for (int i = 0; i < 3; i++) { g_bar_tab[i].frame = CGRectMake(x, height - 44, 100, 44); x += 104; }
        [g_bar viewWithTag:700].frame = CGRectMake(CGRectGetMaxX(safe) - 68, height - 44, 60, 44);
    }
    if (g_cfg_card) {
        const CGRect frame = CGRectInset(safe, 8, 8);
        const BOOL changed = !CGRectEqualToRect(g_cfg_card.frame, frame);
        g_cfg_dim.frame = bounds; g_cfg_card.frame = frame;
        const CGFloat width = g_cfg_card.bounds.size.width;
        g_cfg_nav.frame = CGRectMake(0, 0, width, 44);
        g_cfg_segs.frame = CGRectMake(12, 48, width - 24, 32);
        g_cfg_tbl.frame = CGRectMake(0, 86, width, fmax(0, frame.size.height - 86));
        if (changed) { [g_cfg_tbl beginUpdates]; [g_cfg_tbl endUpdates]; }
    }
    /* Menus remain on-screen when the window/safe area changes. Avoid rebuilding their controls
     * every frame (which would cancel a slider drag). */
    static CGSize lastSize; static UIEdgeInsets lastInsets;
    const UIEdgeInsets insets = g_win.safeAreaInsets;
    if (!CGSizeEqualToSize(lastSize, bounds.size) || !UIEdgeInsetsEqualToEdgeInsets(lastInsets, insets)) {
        lastSize = bounds.size; lastInsets = insets;
        if (g_panel_tab >= 0) bar_panel_rebuild();
    }
}
