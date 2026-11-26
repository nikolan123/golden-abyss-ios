/* ios_ui_chrome.m -- the phone's chrome as UIKit's own: the controls eye at the top-left corner
 * (its slot exactly window.c's tp_layout: the leftmost margin, beside the shoulder pill the layout
 * stands off by its 46 points + the 8-point gap -- "always at that leftmost spot"), a pull from the
 * top edge that brings the menu bar down (a real recognizer over the same touches: the game's own
 * keep flowing, only the pull is ours), and the toasts, the little cards at the top right.
 *
 * Why UIKit and not SwiftUI: this build cross-compiles from Windows with a C/C++/Objective-C
 * toolchain -- no Swift frontend travels with it (no swiftc, and a SwiftUI app wants a Swift
 * runtime under it). Objective-C is UIKit's own language anyway: the eye is a UIButton, the pull
 * a UIGestureRecognizer, the toasts animated UIViews, every one of them a native path that never
 * touches the game's frame. The host loop in build.py compiles this with no -fobjc-arc, so every
 * view here is born alloc'd and released once its superview owns it (manual memory, ARC's rules
 * spelled out by hand); the two objects that live on (ChromeCenter, the display link's target)
 * are installed once and never torn down -- the app's own lifetime is their pool.
 * The escape hatch: RECOMP_NATIVE_CHROME=0 installs nothing; the ImGui-built eye, pull and toasts
 * (overlay.cpp) keep the phone as it was. */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <QuartzCore/QuartzCore.h>
#include <stdlib.h>
#include <math.h>
#include "../ui/touchpad.h"   /* runtime/ui/touchpad.h: the one true layout -- tp_layout's own TpVisual */

/* the game's own (window.c / overlay.cpp) */
extern int  touchpad_on(void); extern void touchpad_set_on(int on);   /* (touchpad.h has the layout structs; these two here read as actions) */
extern void overlay_toast_titled(const char *title, const char *body, double seconds);
extern void overlay_bar_open(void);
extern int  overlay_is_open(void);
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
static UIView        *g_host;        /* where the chrome lives: the root view controller's view (the same view SDL's Metal content lives in; added after, composited and hit-tested above) */
static UIButton     *g_eye;          /* owned by the window (installed once, never removed) */
static UIButton     *g_pull_pill;    /* the top-centre handle: a tap brings the strip down (a swipe belongs to iOS's own top edge) */
static UIView       *g_toast_host;   /* the corner the toasts stack into, owned the same way */
static UIStackView  *g_toast_stack;  /* the toasts, newest on top, the oldest past three */
static int           g_installed;    /* ios_ui_chrome_install ran: everything's in place */
static int           g_eye_on = -1;  /* what the eye last drew: the menu's toggle must reach it too */
static int           g_pad_hidden = -1;   /* what the pad last showed under: 0 over the game, 1 under a menu, set hidden to match */
static int           g_pad_disabled;      /* RECOMP_NATIVE_PAD=0: the native pad stands down (the ImGui pad draws, the finger path owns the taps) */
int g_pad_draws;                          /* how many times the canvas has actually drawn (the tick's line says it) */
static CALayer       *g_top_layer;        /* the same pad image as a raw CALayer above every view layer: the most primitive display iOS has (Step 34's differential) */

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
static double chrome_now(void) { return (double)(int64_t)(CFAbsoluteTimeGetCurrent() + 978307200.0); }   /* the game's own clock: unix seconds */
static UIColor *rgba(int r, int g, int b, float a);   /* defined below the pad section: the glyphs ask for it first */
static UIVisualEffectView *blur_fill(UIView *host, UIBlurEffectStyle st);   /* the frosted material (the settings center defines it) */

/* ---- the eye ---------------------------------------------------------------------------- */
/* the chrome's glyphs, drawn by hand: SF Symbols never showed here (the eye rendered as a bare dark
 * chip -- "the circle thing that does absolutely nothing", and test30's pill had no chevron in it), so
 * nothing depends on them anymore: an eye is two arcs and a dot, a chevron two lines, our own paths */
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
		} else if ([kind isEqualToString:@"check"]) {   /* the system's own mark, drawn (SF Symbols never rendered here) */
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
	[g_eye setImage:img forState:UIControlStateNormal];
	g_eye.backgroundColor = [UIColor colorWithWhite:0.13f alpha:(on ? 0.72f : 0.52f)];
}

/* ---- the pad: UIKit's own buttons, and the picture drawn ---------------------------------- */
static int bar_visible(void);   /* the native strip's own state, asked by the pad's gates below */
/* Two halves, one layout (tp_layout's TpVisual, the same numbers window.c hit-tests with):
 *
 * PadBtn -- the invisible touch area of one control. It draws nothing (the layer below holds the
 * pixels); it *is* the touch: pointInside: answers the exact test tp_hit makes (a pill's box, a
 * button's 1.18-radius circle), stepping aside wherever ImGui owns the point (the bar's menus, the
 * game's dialogs -- the finger falls through to SDL and the menu behaves exactly as before). A touch
 * begins the press (window.c's own bit and down flag, its native path), ends it, and the taptic
 * engine answers both; a finger that slides off keeps its press, as it always had.
 *
 * PadLayer -- the pad's whole picture, Core Graphics drawing the same shapes and colours the ImGui
 * card drew (the same fills, rings, glyphs and weights), dirty-rect synced per frame by the display
 * link: the controls' boxes while the pad is on, a wider box around a live stick so the knob can
 * slide, all empty the moment the pad (or the picture under a menu) goes. */
@interface PadBtn : UIView {
 @public
	int idx;              /* TpButton's index: window.c speaks `which - 10` */
	float hw, hh, rb;     /* the shape: a pill's half-size, or rb = a circle's 1.18 box */
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
		 * And the window's low 14 points are navigation's own, always: a pull or a tap there is never a button */
		const CGPoint wp = [self convertPoint:p toView:nil];
		if (wp.y < 14.0f) return NO;
		if (overlay_owns_point(wp.x, wp.y)) return NO;
	}
	if (pill) return CGRectContainsPoint(self.bounds, p);   /* UIKit asks this one question and trusts it: a YES outside the bounds is a YES for the whole window -- test17's whole-glass swallow */
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

/* the pad's picture, as one painter's function: everything tp_layout laid out, the very shapes and
 * weights the ImGui card drew. The canvas question of Step 30 (drawRect never ran once, however
 * many rects were marked) is answered by not asking it anything: this paints into an offscreen
 * image whenever the pad's state actually changed, and a plain UIImageView carries the pixels --
 * the same delivery as every other UIKit control on the screen, no drawRect in the path at all. */
static void pad_paint_cg(CGContextRef c, const TpVisual *tv, CGSize size) {
	{	/* RECOMP_PAD_CANVAS_DEBUG=1 turns the old amber probe back on; test24 proved the pixels ride,
	 * so it stays off unless asked */
		static int want = -1;
		if (want < 0) { const char *e = getenv("RECOMP_PAD_CANVAS_DEBUG"); want = e && e[0] == '1' && e[1] == '\0'; }
		if (want) {
			CGContextSetFillColorWithColor(c, [UIColor colorWithRed:1.0f green:0.73f blue:0.28f alpha:0.85f].CGColor);
			CGContextFillRect(c, CGRectMake(size.width * 0.5f - 16.0f, 44.0f, 32.0f, 32.0f));
		}
	}
	const float a = (tv->opacity < 0 ? 0 : tv->opacity > 100 ? 100 : tv->opacity) / 100.0f;
	UIColor *fill = rgba(12, 14, 18, 0.55f * a), *ring = rgba(235, 240, 255, 0.75f * a);
	UIColor *text = rgba(235, 240, 255, 0.90f * a), *hot = rgba(255, 255, 255, a);
	UIColor *base = rgba(10, 12, 16, 0.30f * a), *knob_fill = rgba(235, 240, 255, 0.22f * a);

	const int hidden = overlay_pad_hidden() != 0;
	if (!hidden && (tv->sl_active || tv->sr_active)) {   /* the sticks, only while a thumb is on one */
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
	if (hidden) return;
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

/* what the picture must repaint for: every number of the layout and state a pixel depends on */
struct PadSig {
	int nb, opacity, hidden, down[8];
	int sl_a; float sl_x, sl_y, sl_kx, sl_ky, sl_r;
	int sr_a; float sr_x, sr_y, sr_kx, sr_ky, sr_r;
	float w, h;
};

@interface PadLayer : UIView {
 @public
	UIImageView *imgv;      /* the picture's carrier: a plain image view, no drawRect anywhere */
	struct PadSig sig;      /* what was painted last: equal means nothing to do */
	BOOL made;
}
@end

@implementation PadLayer
- (void)sync {
	/* test25: sync runs every tick, hidden or not. The tick's own `hidden` gate is what kept test24's
	 * screenshot honest by accident: a menu opened, sync stopped, and the raw layer went on showing the
	 * last full-pad paint -- one made at the torn moment right after tp_layout's re-write of the pad
	 * struct, all mis-shaped shapes, never healed. The signature decides whether anything repaints;
	 * a bad read heals one tick later, and the hidden bit is part of the signature, so opening the
	 * menu repaints (empty) at once. */
	const TpVisual *tv = touchpad_visuals();
	if (!self.window) return;
	const int show = tv->on && tv->nb;
	if (!show) {   /* the pad itself off: both carriers down at once (the raw layer is nobody's subview -- it hides here too) */
		sig = (struct PadSig){0};
		if (made) imgv.hidden = YES;
		if (g_top_layer) g_top_layer.hidden = YES;
		return;
	}
	if (!made) {   /* the carrier itself: full-size, locked to our bounds, never a touch */
		imgv = [[UIImageView alloc] initWithFrame:self.bounds];
		imgv.userInteractionEnabled = NO;
		imgv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		[self addSubview:imgv];
		[imgv release];
		made = YES;
		chrome_log("    chrome: canvas made (%.0fx%.0f on the window, scale %.1fx)", self.bounds.size.width, self.bounds.size.height, self.window.screen.scale);
	}
	struct PadSig s;
	memset(&s, 0, sizeof s);
	s.nb = tv->nb; s.opacity = tv->opacity; s.hidden = overlay_pad_hidden() != 0 || bar_visible() != 0;
	s.w = self.bounds.size.width; s.h = self.bounds.size.height;
	for (int i = 0; i < tv->nb && i < 8; i++) s.down[i] = tv->b[i].down;
	s.sl_a = tv->sl_active; s.sl_x = tv->sl_x; s.sl_y = tv->sl_y; s.sl_kx = tv->sl_kx; s.sl_ky = tv->sl_ky; s.sl_r = tv->sl_r;
	s.sr_a = tv->sr_active; s.sr_x = tv->sr_x; s.sr_y = tv->sr_y; s.sr_kx = tv->sr_kx; s.sr_ky = tv->sr_ky; s.sr_r = tv->sr_r;
	if (!memcmp(&s, &sig, sizeof s)) return;   /* nothing the least pixel depends on has changed */
	sig = s;
	const CGSize sz = self.bounds.size;
	UIGraphicsImageRendererFormat *fmt = [[UIGraphicsImageRendererFormat alloc] init];
	const float scale = self.window.screen.scale > 0 ? self.window.screen.scale : 3.0f;
	fmt.scale = scale;
	UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:sz format:fmt];
	UIImage *im = [r imageWithActions:^(UIGraphicsImageRendererContext *rc) { pad_paint_cg(rc.CGContext, tv, sz); }];
	[fmt release]; [r release];
	imgv.image = im;
	if (!g_top_layer) {   /* the raw layer, placed after every subview's layer: over everything, no view machinery at all */
		g_top_layer = [CALayer new];
		g_top_layer.frame = g_host.bounds;
		[g_host.layer addSublayer:g_top_layer];
		[g_top_layer release];   /* the window's layer owns it */
	}
	g_top_layer.frame = self.bounds;
	g_top_layer.contents = (__bridge id)im.CGImage;
	imgv.hidden = s.hidden != 0;
	g_top_layer.hidden = s.hidden != 0;
	g_pad_draws++;
	if (g_pad_draws == 1) chrome_log("    chrome: canvas painted (%.0fx%.0f, scale %.1f, opacity %.2f)", sz.width, sz.height, scale, tv->opacity / 100.0f);
}
@end

static PadLayer *g_pad_layer;        /* the pad's picture, one full-screen canvas in sync with tp_layout */
static PadBtn   *g_pad_hits[8];       /* its touch areas, positioned from the same TpVisual */
static UIImpactFeedbackGenerator *g_hap[3];   /* light / medium / soft, prepared as they're first asked */

/* the taptic engine's answer: 0 light (a button, the eye, a pull), 1 medium (the shoulders), 2 soft
 * (a thumb's hold becoming a stick). Thread-safe: whatever calls it, the tap happens on the main */
void ios_ui_haptic(int kind) {
	if (!g_installed) return;
	if (kind < 0 || kind > 2) kind = 0;
	if (![NSThread isMainThread]) { const int k = kind; dispatch_async(dispatch_get_main_queue(), ^{ ios_ui_haptic(k); }); return; }
	chrome_log("    chrome: haptic %d (%s)", kind, kind == 2 ? "a stick spawned" : kind == 1 ? "a shoulder" : "a button, the eye, a pull");
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
static UIView *g_panel;              /* the open panel (its rows rebuilt per state change) */
static int g_panel_tab = -1;         /* which panel is open (-1: none) */
static NSMutableArray *g_panel_keep;   /* the panel's action holders, swept on each rebuild */
static int g_bar_shown;              /* the strip is down (its own slide state) */
static double g_bar_last;            /* the last moment the strip was touched */
static UIView *g_rows;               /* where panel primitives add (the strip's panel, or the settings center's page) */
static NSMutableArray *g_keep;       /* the array BN drops its holders into (the strip's, or the center's) */

@interface BN : NSObject { @public void (^b)(void); }
+ (id)act:(void (^)(void))blk;
- (void)fire;
@end
@implementation BN
- (void)dealloc { [b release]; [super dealloc]; }
+ (id)act:(void (^)(void))blk { BN *n = [[BN alloc] init]; n->b = [blk copy]; [g_keep addObject:n]; return [n autorelease]; }
- (void)fire { self->b(); }
@end

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
static UIView *panel_dot(CGRect f) {   /* the row's mark: the system's own check, drawn (SF Symbols never rendered here) */
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
			hi = [tile resizableImageWithCapInsets:UIEdgeInsetsMake(6, 6, 6, 6)];
		}
		[b setBackgroundImage:hi forState:UIControlStateHighlighted];
	}
	[g_rows addSubview:b];
	return b;
}
static void panel_fire_on_highlight(UIButton *b, void (^blk)(void)) {   /* the row's press: the block retires with g_panel_keep */
	BN *n = [BN act:blk];
	[b addTarget:n action:@selector(fire) forControlEvents:UIControlEventTouchUpInside];
}

/* the panel's three contents -- the phone's own rows, the same actions the ImGui menus took */
static void bar_panel_rebuild(void);
static void bar_up_close_all(void);
static void bar_make(void);
void ios_ui_settings_open(int tab);   /* the full menu, native (below) */
static CGFloat panel_rows(int tab) {
	g_rows = g_panel; g_keep = g_panel_keep;
	CGFloat y = 6;
	const CGFloat row = 34.0f, inset = 14.0f;
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
			[g_panel addSubview:l]; [l release];
			UILabel *vl = [[UILabel alloc] initWithFrame:CGRectMake(vb.size.width - 56, y + 7, 44, 19)];
			vl.font = bar_row_font(); vl.textColor = rgba(150, 156, 172, 1.0f); vl.text = [NSString stringWithFormat:@"%.0f%%", overlay_volume() * 100.0f];
			[g_panel addSubview:vl]; [vl release];
			UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(inset + 70, y + 3, vb.size.width - inset - 74 - 56, 28)];
			sl.minimumValue = 0.0f; sl.maximumValue = 1.0f; sl.value = overlay_volume();
			sl.minimumTrackTintColor = rgba(240, 192, 96, 1.0f);
			[g_panel addSubview:sl];
			/* no ARC: __block keeps the slider's blocks from retaining the slider that targets them */
	__block UISlider *wsl = sl; __block UILabel *wvl = vl;
	[sl addTarget:[BN act:^{ overlay_set_volume(wsl.value); wvl.text = [NSString stringWithFormat:@"%.0f%%", wsl.value * 100.0f]; }] action:@selector(fire) forControlEvents:UIControlEventValueChanged];
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
		panel_fire_on_highlight(b, ^{ overlay_request_quit(); });
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
			[g_panel addSubview:st]; [st release];
			panel_fire_on_highlight(r, ^{ touchpad_set_on(touchpad_on() ? 0 : 1); bar_panel_rebuild(); });
			y += row;
		}
		{	int on = window_touchpad_rstick() != 0;
			UIButton *r = panel_button(CGRectMake(0, y, vb.size.width, row), @"Second stick (the lower right corner)");
			UILabel *st = [[UILabel alloc] initWithFrame:CGRectMake(vb.size.width - 58, y + 8, 44, 18)];
			st.font = bar_row_font(); st.textColor = on ? rgba(240, 192, 96, 1.0f) : rgba(150, 156, 172, 1.0f);
			st.text = on ? @"On" : @"Off";
			[g_panel addSubview:st]; [st release];
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
			[g_panel addSubview:vl]; [vl release];
			UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(inset, y + 26, vb.size.width - 2 * inset, 24)];
			sl.minimumValue = 60; sl.maximumValue = 160; sl.value = v;
			sl.minimumTrackTintColor = rgba(240, 192, 96, 1.0f);
			[g_panel addSubview:sl];
			__block UISlider *wsl = sl; __block UILabel *wvl = vl;   /* no ARC: keeps the blocks from retaining the slider */
			[sl addTarget:[BN act:^{ int nv = (int)(wsl.value + 0.5f); wvl.text = [NSString stringWithFormat:@"%d%%", nv]; }] action:@selector(fire) forControlEvents:UIControlEventValueChanged];
			[sl addTarget:[BN act:^{ touchpad_set_scale((int)(wsl.value + 0.5f)); }] action:@selector(fire) forControlEvents:UIControlEventTouchUpInside];
			[sl release];
			y += row + 16;
		}
		{	/* Opacity: 10..90 */
			UILabel *l = panel_head(CGRectMake(inset, y + 8, vb.size.width - 2 * inset - 56, 18), @"See-through controls");
			l.font = bar_row_font(); l.textColor = rgba(234, 236, 244, 0.94f);
			UILabel *vl = [[UILabel alloc] initWithFrame:CGRectMake(vb.size.width - 56, y + 8, 44, 18)];
			vl.font = bar_row_font(); vl.textColor = rgba(150, 156, 172, 1.0f);
			int v = settings_int("touchpad_opacity", 42);
			vl.text = [NSString stringWithFormat:@"%d%%", v];
			[g_panel addSubview:vl]; [vl release];
			UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(inset, y + 26, vb.size.width - 2 * inset, 24)];
			sl.minimumValue = 10; sl.maximumValue = 90; sl.value = v;
			sl.minimumTrackTintColor = rgba(240, 192, 96, 1.0f);
			[g_panel addSubview:sl];
			__block UISlider *wsl = sl; __block UILabel *wvl = vl;   /* no ARC: keeps the blocks from retaining the slider */
			[sl addTarget:[BN act:^{ int nv = (int)(wsl.value + 0.5f); wvl.text = [NSString stringWithFormat:@"%d%%", nv]; }] action:@selector(fire) forControlEvents:UIControlEventValueChanged];
			[sl addTarget:[BN act:^{ settings_set_int("touchpad_opacity", (int)(wsl.value + 0.5f)); settings_save(); }] action:@selector(fire) forControlEvents:UIControlEventTouchUpInside];
			[sl release];
			y += row + 16;
		}
		{	bool lh = touchpad_mirror() != 0;
			UIButton *r = panel_button(CGRectMake(0, y, vb.size.width, row), @"Left-handed (swap sides)");
			UILabel *st = [[UILabel alloc] initWithFrame:CGRectMake(vb.size.width - 58, y + 8, 44, 18)];
			st.font = bar_row_font(); st.textColor = lh ? rgba(240, 192, 96, 1.0f) : rgba(150, 156, 172, 1.0f);
			st.text = lh ? @"On" : @"Off";
			[g_panel addSubview:st]; [st release];
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
	[g_panel_keep removeAllObjects];   /* the BN blocks retire with their rows; the panel's blur stays (Step 43) */
	for (UIView *v in [g_panel subviews]) if (![v isKindOfClass:[UIVisualEffectView class]]) [v removeFromSuperview];
	const int tab = g_panel_tab;
	const CGFloat widths[3] = { 250.0f, 250.0f, 300.0f };
	const CGFloat w = widths[tab];
	const CGPoint at = g_panel.frame.origin;   /* captured before any size change: setting bounds (as test29 did) slides the top up by half the size delta -- the panel opened at y -10, its header cut by the screen's edge */
	g_panel.frame = CGRectMake(at.x, at.y, w, 100.0f);   /* frame, never bounds: the top stays at the strip's bottom */
	const CGFloat h = panel_rows(tab);
	g_panel.frame = CGRectMake(at.x, at.y, w, h);
}

static void bar_panel_open(int tab) {
	g_panel_tab = tab;
	g_bar_last = chrome_now();
	UIButton *t = g_bar_tab[tab];
	CGFloat x = t.frame.origin.x - 4; if (x < 4) x = 4;
	const CGFloat widths[3] = { 250.0f, 250.0f, 300.0f };
	if (x + widths[tab] > g_bar.bounds.size.width - 4) x = g_bar.bounds.size.width - widths[tab] - 4;
	[g_panel setFrame:CGRectMake(x, g_bar.bounds.size.height + 1, widths[tab], 10)];
	bar_panel_rebuild();
	g_shield.hidden = NO;
	g_panel.hidden = NO;
	ios_ui_haptic(0);   /* the panel's little tick */
}
static void bar_panel_close(void) {
	g_panel_tab = -1;
	g_panel.hidden = YES;
	g_shield.hidden = YES;
}
static void bar_up_close_all(void) {
	if (!g_bar) return;
	bar_panel_close();
	g_bar_shown = 0;
	[UIView animateWithDuration:0.20 animations:^{ CGRect f = g_bar.frame; f.origin.y = -f.size.height; g_bar.frame = f; }];
}
void ios_ui_bar_open(void) {
	if (!g_installed) return;
	if (overlay_is_open()) return;   /* the menu is up (the settings center or a card): the strip stays out of its way */
	if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ ios_ui_bar_open(); }); return; }
	if (!g_bar) bar_make();   /* built the first time it's ever pulled */
	if (!g_bar) return;
	g_bar_last = chrome_now();
	if (!g_bar_shown) {
		g_bar_shown = 1;
		[UIView animateWithDuration:0.22 animations:^{ CGRect f = g_bar.frame; f.origin.y = 0; g_bar.frame = f; }];
		ios_ui_haptic(0);
	}
}
static void bar_tab_tapped(int tab) {
	if (overlay_is_open()) { bar_up_close_all(); return; }   /* the full menu is up: the strip steps out of its way */
	g_bar_last = chrome_now();
	if (g_panel_tab == tab) { bar_panel_close(); return; }
	bar_panel_open(tab);
}
static void bar_make(void) {
	const CGFloat bh = 34.0f;
	g_panel_keep = [[NSMutableArray alloc] init];   /* the tab buttons use it before anything else exists */
	g_keep = g_panel_keep;
	/* the strip: full width, 34 tall, parked above the top until opened; the frosted material (Step 43) */
	g_bar = [[UIView alloc] initWithFrame:CGRectMake(0, -bh, g_host.bounds.size.width, bh)];
	g_bar.backgroundColor = [UIColor clearColor];
	blur_fill(g_bar, UIBlurEffectStyleSystemMaterialDark);
	g_bar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
	[g_host addSubview:g_bar];
	[g_bar release];
	/* its bottom hairline, the card's one edge */
	{	UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, bh - 1, g_bar.bounds.size.width, 1)];
		line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		line.backgroundColor = rgba(255, 255, 255, 0.10f);
		[g_bar addSubview:line];
		[line release];
	}

	/* the tab buttons: Game / Display / Controls, off the eye's corner (Step 25's slot) */
	const CGFloat ty = 3;
	static const char *const tabs[3] = { "Game", "Display", "Controls" };
	CGFloat tx = 82;   /* the eye's own slot ends at ~70 */
	for (int i = 0; i < 3; i++) {
		UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
		b.frame = CGRectMake(tx, ty, 0, 0);   /* sized below, once the titles are set */
		[b setTitle:[NSString stringWithUTF8String:tabs[i]] forState:UIControlStateNormal];
		b.titleLabel.font = [UIFont systemFontOfSize:14.5f weight:UIFontWeightMedium];
		[b setTitleColor:rgba(226, 230, 240, 0.75f) forState:UIControlStateNormal];
		[b setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted | UIControlStateSelected];
		[b sizeToFit];
		CGRect f = b.frame; f.size.width += 22; f.size.height = bh - 6; f.origin.y = ty;
		b.frame = f;
		const int ti = i;
		[b addTarget:[BN act:^{ bar_tab_tapped(ti); }] action:@selector(fire) forControlEvents:UIControlEventTouchUpInside];
		[g_bar addSubview:b];
		g_bar_tab[i] = b;
		tx += f.size.width + 8;
	}
	/* the shield: a tap anywhere closes the panel (the game never sees that one tap -- the ImGui menus behaved the same) */
	g_shield = [[UIView alloc] initWithFrame:g_host.bounds];
	g_shield.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	g_shield.backgroundColor = [UIColor clearColor];
	g_shield.hidden = YES;
	[g_shield addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:[BN act:^{ bar_up_close_all(); }] action:@selector(fire)]];
	[g_host addSubview:g_shield];
	[g_shield release];
	/* the panel: the rounded card under the open tab, the same frosted material */
	g_panel = [[UIView alloc] initWithFrame:CGRectZero];
	g_panel.backgroundColor = [UIColor clearColor];
	blur_fill(g_panel, UIBlurEffectStyleSystemMaterialDark);
	g_panel.layer.cornerRadius = 10.0f;
	g_panel.layer.masksToBounds = YES;
	g_panel.layer.borderColor = rgba(255, 255, 255, 0.10f).CGColor;
	g_panel.layer.borderWidth = 0.5f;
	g_panel.hidden = YES;
	g_panel.userInteractionEnabled = YES;
	[g_host addSubview:g_panel];
	[g_panel release];
}
static int bar_visible(void) { return g_bar && g_bar.frame.origin.y > -20.0f ? 1 : 0; }

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
	char lines[7][40];
	int n = 0;
	if (overlay_stats_level() > 0 && !bar_visible() && !overlay_is_open()) n = overlay_osd_lines(lines, 7);
	if (!g_osd_lbl) {
		if (!n) return;
		g_osd_lbl = [[UILabel alloc] initWithFrame:CGRectZero];
		g_osd_lbl.font = [UIFont fontWithName:@"Menlo-Bold" size:10.0f];
		g_osd_lbl.textColor = [UIColor whiteColor];
		g_osd_lbl.numberOfLines = 0;
		g_osd_lbl.layer.backgroundColor = rgba(0, 0, 0, 0.66f).CGColor;
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
	g_osd_lbl.frame = CGRectMake(8.0f, y, tz.width + 12.0f, tz.height + 10.0f);
	g_osd_lbl.hidden = NO;
}

/* the pause card: PAUSED, the same centered card the banner drew */
static UIView *g_pz_card; static UILabel *g_pz_t, *g_pz_s;
static void pause_tick(void) {
	if (!g_installed || !g_host) return;
	const int show = overlay_game_paused() && !overlay_is_open() && !overlay_intro_up();
	if (!show) { if (g_pz_card) g_pz_card.hidden = YES; return; }
	if (!g_pz_card) {
		g_pz_card = [[UIView alloc] initWithFrame:CGRectZero];
		g_pz_card.backgroundColor = [UIColor clearColor];
		blur_fill(g_pz_card, UIBlurEffectStyleSystemMaterialDark);
		g_pz_card.layer.cornerRadius = 14.0f;
		g_pz_card.layer.masksToBounds = YES;
		g_pz_card.userInteractionEnabled = NO;
		g_pz_t = [[UILabel alloc] initWithFrame:CGRectZero];
		g_pz_t.text = @"PAUSED"; g_pz_t.font = [UIFont systemFontOfSize:24.0f weight:UIFontWeightBold];
		g_pz_t.textColor = [UIColor whiteColor]; g_pz_t.textAlignment = NSTextAlignmentCenter;
		[g_pz_card addSubview:g_pz_t]; [g_pz_t release];
		g_pz_s = [[UILabel alloc] initWithFrame:CGRectZero];
		g_pz_s.text = @"Pull down from the top of the screen, then Game > Resume";
		g_pz_s.font = [UIFont systemFontOfSize:11.0f];
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
static double g_intro_t0, g_intro_tap;
static void intro_tick(void) {
	if (!g_installed || !g_host) return;
	if (!overlay_intro_up()) {
		if (g_intro_view) g_intro_view.hidden = YES;
		g_intro_t0 = 0; g_intro_tap = 0;
		return;
	}
	const double now = chrome_now();
	if (!g_intro_t0) g_intro_t0 = now;
	int touched = g_intro_tap > 0;
	if (!touched) {   /* the first touch anywhere (the gamepad path the ImGui card watched for) */
		int ks[8], xs[8], ys[8];
		for (int port = 0; port < 2 && !touched; port++) if (window_touch_contacts(port, ks, xs, ys, 8) > 0) touched = 1;
		if (touched) g_intro_tap = now;
	}
	if (!touched && now - g_intro_t0 > 12.0) { overlay_intro_dismiss(); return; }
	if (touched && now - g_intro_tap > 1.2) { overlay_intro_dismiss(); return; }   /* a moment, then the game */
	if (!g_intro_view && !touched) {
		g_intro_view = [[UIView alloc] initWithFrame:CGRectZero];
		g_intro_view.backgroundColor = [UIColor clearColor];
		blur_fill(g_intro_view, UIBlurEffectStyleSystemMaterialDark);
		g_intro_view.layer.cornerRadius = 12.0f;
		g_intro_view.layer.masksToBounds = YES;
		g_intro_view.userInteractionEnabled = NO;   /* the game's own touches, as the strip always let them */
		UILabel *t = [[UILabel alloc] initWithFrame:CGRectZero];
		t.text = @"Playing on this phone"; t.font = [UIFont systemFontOfSize:13.0f weight:UIFontWeightSemibold];
		t.textColor = [UIColor whiteColor];
		[g_intro_view addSubview:t]; [t release];
		UILabel *b = [[UILabel alloc] initWithFrame:CGRectZero];
		b.text = @"Buttons and shoulders at the edges. Hold or drag the lower left and the movement stick spawns under your thumb there; a quick tap anywhere always touches the game's screen.";
		b.font = [UIFont systemFontOfSize:10.5f]; b.textColor = rgba(150, 156, 172, 1.0f);
		b.numberOfLines = 0;
		[g_intro_view addSubview:b]; [b release];
		UILabel *a = [[UILabel alloc] initWithFrame:CGRectZero];
		a.text = @"Pull down from the top for the menu. The little eye at the top left turns these controls off and on.";
		a.font = [UIFont systemFontOfSize:10.5f]; a.textColor = rgba(240, 192, 96, 1.0f);
		a.numberOfLines = 0;
		[g_intro_view addSubview:a]; [a release];
		[g_host addSubview:g_intro_view];
		[g_intro_view release];
		UILabel *tl = [g_intro_view.subviews objectAtIndex:1], *bl = [g_intro_view.subviews objectAtIndex:2], *al = [g_intro_view.subviews objectAtIndex:3];   /* (0: the blur) */
		const CGSize sz = g_host.bounds.size;
		const CGFloat cw = fminf(sz.width * 0.52f, 430.0f), in = 14.0f;
		const CGSize bs = [bl sizeThatFits:CGSizeMake(cw - 2 * in, 2000.0f)];
		const CGSize as = [al sizeThatFits:CGSizeMake(cw - 2 * in, 2000.0f)];
		const CGFloat ch = 14 + 18 + 6 + bs.height + 8 + as.height + 12;
		g_intro_view.frame = CGRectMake((sz.width - cw) * 0.5f, sz.height - ch - 12.0f, cw, ch);
		tl.frame = CGRectMake(in, 12, cw - 2 * in, 18);
		bl.frame = CGRectMake(in, 36, cw - 2 * in, bs.height);
		al.frame = CGRectMake(in, 36 + bs.height + 8, cw - 2 * in, as.height);
		chrome_log("    chrome: intro strip up (%.0f x %.0f)", cw, ch);
	}
	if (g_intro_view) g_intro_view.hidden = touched != 0;   /* the first touch: it simply goes */
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
static NSMutableArray *g_cfg_keep;
static int g_cfg_page = -1;         /* the open page (-1: closed) */
static UILabel *g_cfg_fps;          /* the Performance page's live number (its cell's own label) */
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
	r->vmin = vmin; r->vmax = vmax; r->val = val; r->integral = integral; r->num = [num copy];
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
	cfg_slider("Volume", 0, 100, overlay_opt_get("volume") * 100.0f, 0, ^(double v) {
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
	cfg_note("Your thumbs: the stick at the left edge, the face buttons at the right, the shoulders at the top corners. Touch anywhere else in the lower right for the second stick.");
	cfg_note("The picture itself is the Vita's touch screen: tap and drag it as you would the real thing.");
	cfg_note("Pull down from the top of the screen for the quick menu; Game > All settings opens this one, and pauses the game while it is up.");
	cfg_head("About");
	{
		CfgRow *r = cfg_row(R_TEXT);
		r->title = [[NSString alloc] initWithUTF8String:"Project Nativ"];
		r->detail = [[NSString alloc] initWithUTF8String:"This PS Vita game, statically recompiled to native code, running on this phone's own CPU and GPU."];
	}
	cfg_note("The quick menu pulls down from the top of the screen. The little eye at the top left turns the on-screen controls off and on.");
}

static void cfg_close(void);
/* the table's host: the datasource and the delegate, one object for the app's life */
@interface CfgCenter : NSObject <UITableViewDataSource, UITableViewDelegate>
- (void)done;
@end
static CfgCenter *g_cfg_center;
@implementation CfgCenter
- (void)done { ios_ui_haptic(0); cfg_close(); }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { (void)tv; (void)s; return (NSInteger)[g_cfg_rows count]; }
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
	CfgRow *r = [g_cfg_rows objectAtIndex:[ip row]];
	switch (r->kind) {
	case R_SLIDER: return 64.0f;
	case R_HEAD: return 34.0f;
	case R_TEXT: return 76.0f;
	case R_NOTE: {
		static UILabel *m;
		if (!m) { m = [[UILabel alloc] initWithFrame:CGRectZero]; m.font = [UIFont systemFontOfSize:13.0f]; m.numberOfLines = 0; [m retain]; }
		m.text = r->title;
		const CGSize sz = [m sizeThatFits:CGSizeMake(tv.bounds.size.width - 76.0f, 2000.0f)];
		return sz.height + 16.0f;
	}
	case R_SWITCH: case R_SEG:
		return r->detail ? 56.0f : 44.0f;
	default:
		return 44.0f;
	}
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	static NSString *const ids[8] = { @"h", @"s", @"g", @"l", @"b", @"n", @"p", @"t" };
	CfgRow *r = [g_cfg_rows objectAtIndex:[ip row]];
	NSString *id = ids[r->kind < 8 ? r->kind : 0];
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:id];
	if (!cell) {
		cell = [[[UITableViewCell alloc] initWithStyle:((r->kind == R_SWITCH || r->kind == R_SEG) ? UITableViewCellStyleSubtitle : UITableViewCellStyleDefault) reuseIdentifier:id] autorelease];
		if (r->kind == R_HEAD) { cell.separatorInset = UIEdgeInsetsMake(0, 0, 0, CGFLOAT_MAX); cell.selectionStyle = UITableViewCellSelectionStyleNone; }
		if (r->kind == R_NOTE || r->kind == R_TEXT) { cell.selectionStyle = UITableViewCellSelectionStyleNone; cell.separatorInset = UIEdgeInsetsMake(0, 0, 0, CGFLOAT_MAX); }
	}
	g_keep = g_cfg_keep;
	switch (r->kind) {
	case R_HEAD:
		cell.textLabel.text = r->title;
		cell.textLabel.font = [UIFont systemFontOfSize:13.0f weight:UIFontWeightSemibold];
		cell.textLabel.textColor = rgba(240, 192, 96, 0.85f);
		break;
	case R_SWITCH: {
		cell.textLabel.text = r->title;
		cell.textLabel.font = [UIFont systemFontOfSize:15.5f];
		cell.textLabel.textColor = [UIColor labelColor];
		cell.detailTextLabel.text = r->detail;
		cell.detailTextLabel.font = [UIFont systemFontOfSize:11.5f];
		cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
		cell.detailTextLabel.numberOfLines = 0;
		UISwitch *sw = [[UISwitch alloc] init];
		sw.on = r->on != 0;
		sw.onTintColor = rgba(240, 192, 96, 0.92f);
		__block UISwitch *wsw = sw;
		[sw addTarget:[BN act:^{ ios_ui_haptic(0); r->flip(wsw.on); }] action:@selector(fire) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;   /* the cell owns it from here */
		[sw release];
		break;
	}
	case R_SEG: {
		cell.textLabel.text = r->title;
		cell.textLabel.font = [UIFont systemFontOfSize:15.5f];
		cell.textLabel.textColor = [UIColor labelColor];
		cell.detailTextLabel.text = r->detail;
		cell.detailTextLabel.font = [UIFont systemFontOfSize:11.5f];
		cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
		cell.detailTextLabel.numberOfLines = 0;
		UISegmentedControl *sg = [[UISegmentedControl alloc] initWithItems:r->seg];
		sg.selectedSegmentIndex = r->sel;
		sg.backgroundColor = [UIColor tertiarySystemFillColor];
		sg.selectedSegmentTintColor = rgba(240, 192, 96, 0.92f);
		[sg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor labelColor]} forState:UIControlStateNormal];
		[sg setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor blackColor]} forState:UIControlStateSelected];
		__block UISegmentedControl *wsg = sg;
		[sg addTarget:[BN act:^{ ios_ui_haptic(0); r->pick((int)wsg.selectedSegmentIndex); }] action:@selector(fire) forControlEvents:UIControlEventValueChanged];
		[sg sizeToFit];
		cell.accessoryView = sg;
		[sg release];
		break;
	}
	case R_SLIDER: {
		const CGFloat cw = cell.contentView.bounds.size.width;
		cell.textLabel.text = r->title;
		cell.textLabel.font = [UIFont systemFontOfSize:15.5f];
		cell.textLabel.textColor = [UIColor labelColor];
		UILabel *vl = [[UILabel alloc] initWithFrame:CGRectMake(cw - 92.0f, 13.0f, 76.0f, 19.0f)];
		vl.font = [UIFont monospacedDigitSystemFontOfSize:12.0f weight:UIFontWeightRegular];
		vl.textColor = [UIColor secondaryLabelColor];
		vl.textAlignment = NSTextAlignmentRight;
		NSString *(^fmt)(double) = ^(double v) { return r->integral ? [NSString stringWithFormat:@"%.0f", v] : [NSString stringWithFormat:@"%.2fx", v]; };
		vl.text = fmt(r->val);
		[cell.contentView addSubview:vl];
		[vl release];
		UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(16.0f, 34.0f, cw - 32.0f, 28.0f)];
		sl.minimumValue = r->vmin; sl.maximumValue = r->vmax; sl.value = r->val;
		sl.minimumTrackTintColor = rgba(240, 192, 96, 1.0f);
		__block UISlider *wsl = sl; __block UILabel *wvl = vl;
		[sl addTarget:[BN act:^{ wvl.text = fmt(wsl.value); if (r->num) r->num(wsl.value); }] action:@selector(fire) forControlEvents:UIControlEventValueChanged];
		[sl addTarget:[BN act:^{ if (r->num) r->num(wsl.value); }] action:@selector(fire) forControlEvents:UIControlEventTouchUpInside];
		[cell.contentView addSubview:sl];
		[sl release];
		break;
	}
	case R_BUTTON:
		cell.textLabel.text = r->title;
		cell.textLabel.font = [UIFont systemFontOfSize:15.5f];
		cell.textLabel.textColor = [UIColor labelColor];
		cell.accessoryView = nil;
		break;
	case R_NOTE:
		cell.textLabel.text = r->title;
		cell.textLabel.font = [UIFont systemFontOfSize:13.0f];
		cell.textLabel.textColor = [UIColor secondaryLabelColor];
		cell.textLabel.numberOfLines = 0;
		break;
	case R_PAIR: {
		const CGFloat cw = cell.contentView.bounds.size.width;
		cell.textLabel.text = r->title;
		cell.textLabel.font = [UIFont systemFontOfSize:14.5f];
		cell.textLabel.textColor = [UIColor labelColor];
		UILabel *rl = nil;
		for (UIView *v in cell.contentView.subviews) if ([v isKindOfClass:[UILabel class]] && v != cell.textLabel) { rl = (UILabel *)v; break; }
		if (!rl) {
			rl = [[UILabel alloc] initWithFrame:CGRectMake(cw - 150.0f, 13.0f, 136.0f, 19.0f)];
			rl.font = [UIFont systemFontOfSize:12.5f];
			rl.textColor = [UIColor secondaryLabelColor];
			rl.textAlignment = NSTextAlignmentRight;
			rl.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
			[cell.contentView addSubview:rl];
			[rl release];
		}
		rl.text = r->right;
		if ([r->title isEqualToString:@"Frame rate"]) g_cfg_fps = rl;   /* the tick writes it live (set at configure: the reload is lazy) */
		break;
	}
	case R_TEXT:
		cell.textLabel.text = r->title;
		cell.textLabel.font = [UIFont systemFontOfSize:19.0f weight:UIFontWeightSemibold];
		cell.textLabel.textColor = [UIColor whiteColor];
		{
			UILabel *dl = nil;
			for (UIView *v in cell.contentView.subviews) if ([v isKindOfClass:[UILabel class]] && v != cell.textLabel) { dl = (UILabel *)v; break; }
			if (!dl) {
				dl = [[UILabel alloc] initWithFrame:CGRectMake(16.0f, 42.0f, cell.contentView.bounds.size.width - 32.0f, 28.0f)];
				dl.font = [UIFont systemFontOfSize:12.5f];
				dl.textColor = [UIColor secondaryLabelColor];
				dl.numberOfLines = 2;
				[cell.contentView addSubview:dl];
				[dl release];
			}
			dl.text = r->detail;
		}
		break;
	}
	return cell;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	CfgRow *r = [g_cfg_rows objectAtIndex:[ip row]];
	if (r->kind == R_BUTTON) { ios_ui_haptic(0); if (r->act) r->act(); }
	[tv deselectRowAtIndexPath:ip animated:YES];
}
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)ip { (void)tv; (void)ip; cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor]; }
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
	g_keep = g_cfg_keep;
	const int tab = g_cfg_page >= 0 && g_cfg_page < 5 ? g_cfg_page : 0;
	cfg_page_build(tab);
	g_cfg_nav.topItem.title = [NSString stringWithUTF8String:cfg_tab_names[tab]];
	g_cfg_segs.selectedSegmentIndex = tab;
	g_cfg_fps = nil;
	[g_cfg_tbl reloadData];
	[g_cfg_tbl setContentOffset:CGPointZero animated:NO];
	/* the Performance page's live number: its row's own right label (weakly ours; the tick writes it) */
	for (NSUInteger i = 0; i < [g_cfg_rows count]; i++) {
		CfgRow *r = [g_cfg_rows objectAtIndex:i];
		if (r->kind == R_PAIR && [r->title isEqualToString:@"Frame rate"]) {
			UITableViewCell *c = [g_cfg_tbl cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
			if (c) {
				for (UIView *v in c.contentView.subviews) if ([v isKindOfClass:[UILabel class]] && v != c.textLabel) { g_cfg_fps = (UILabel *)v; break; }
			}
		}
	}
}
static void cfg_make(void) {
	if (g_cfg_dim) return;
	g_cfg_keep = [[NSMutableArray alloc] init];
	g_keep = g_cfg_keep;
	g_cfg_rows = [[NSMutableArray alloc] init];
	g_cfg_center = [[CfgCenter alloc] init];
	g_cfg_dim = [[UIView alloc] initWithFrame:g_host.bounds];
	g_cfg_dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	g_cfg_dim.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.55f];
	[g_cfg_dim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:[BN act:^{ cfg_close(); }] action:@selector(fire)]];
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
	[g_cfg_segs addTarget:[BN act:^{ ios_ui_haptic(0); g_cfg_page = (int)wsg.selectedSegmentIndex; cfg_rebuild(); }] action:@selector(fire) forControlEvents:UIControlEventValueChanged];
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
	overlay_open();   /* the menu's own open state: the pause, the input routing, the audio mute */
	if (!g_cfg_dim) cfg_make();
	if (tab >= 0) g_cfg_page = tab; else if (g_cfg_page < 0) g_cfg_page = 0;
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
			[g_host addSubview:v];
			[v release];   /* the host owns it */
			g_pad_hits[i] = v;
		}
		if (!tv->on || i >= tv->nb) { v.hidden = YES; v->down = 0; continue; }
		const TpButton *b = &tv->b[i];
		v->pill = b->pill;
		if (b->pill) v.frame = CGRectMake(b->x - b->hw, b->y - b->hh, 2 * b->hw, 2 * b->hh);
		else { const float e = b->r * 1.18f; v.frame = CGRectMake(b->x - e, b->y - e, 2 * e, 2 * e); }
		v.hidden = NO;
		chrome_log("    chrome:   btn %d -> (%.0f, %.0f, %.0f x %.0f) %s", i, v.frame.origin.x, v.frame.origin.y, v.frame.size.width, v.frame.size.height, b->pill ? "pill" : "round");
	}
}

/* ---- the pull: an observer that never fails ----------------------------------------------- */
/* test23's log ended the recogniser debate: `pull began` had never once appeared in any session --
 * the delegate-consulted pan, under whatever SDL and UIKit disagree about here, simply never began.
 * So it isn't a recogniser's decision anymore: it *observes*. A finger that begins within 16 points
 * of the top edge (off the eye's square) and moves 12 points down fires the bar once per touch, and
 * the recogniser itself never transitions at all -- the delegate always says no -- so the game's
 * own contact under the same finger goes on untouched (the bar's strip takes its own taps anyway). */
@interface TopPull : UIPanGestureRecognizer
@property CGFloat startX, startY;   /* where touch 0 landed, in the window's points */
@property int fired;               /* this touch has already opened the bar */
@end

@implementation TopPull
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	self.startX = 1e9; self.startY = 1e9; self.fired = 0;
	UITouch *t = touches.anyObject;
	if (t && self.view) { const CGPoint p = [t locationInView:self.view]; self.startX = p.x; self.startY = p.y; }
	[super touchesBegan:touches withEvent:event];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	{
		/* only the strip's own middle band pulls (overlay.cpp's own gate, mirrored here): the
		 * shoulders L and R live at the top corners and must never misstrigger the menu */
		const CGFloat w = self.view ? self.view.bounds.size.width : 0;
		if (self.startX < w * 0.5f - 140.0f || self.startX > w * 0.5f + 140.0f) self.fired = 1;
	}
	if (!self.fired && self.startY <= 16.0f && !(g_eye && self.startY <= CGRectGetMaxY(g_eye.frame) && self.startX <= CGRectGetMaxX(g_eye.frame))) {
		UITouch *t = touches.anyObject;
		if (t && self.view) {
			const CGPoint p = [t locationInView:self.view];
			if (p.y - self.startY > 12.0f) {
				self.fired = 1;
				ios_ui_bar_open();
				ios_ui_haptic(0);
				chrome_log("    chrome: pull fired, start (%.0f, %.0f)", self.startX, self.startY);
			}
		}
	}
	[super touchesMoved:touches withEvent:event];
}
@end

/* the one object that holds the actions (target-action wants an NSObject; installed once, never
 * released: UIKit's targets and delegates are unretained, so this stays for the app's own life) */
@interface ChromeCenter : NSObject
@end
static ChromeCenter *g_center;

@implementation ChromeCenter
- (void)eye:(id)sender {
	(void)sender;
	const int on = touchpad_on();
	touchpad_set_on(on ? 0 : 1);
	overlay_toast_titled(on ? "Controls off" : "Controls on", on ? "The eye brings them back." : "", 2.4);
	ios_ui_haptic(0);   /* the taptic engine answers the flip, as a native switch would */
	g_eye_on = -1; eye_look();   /* the menu's own wording: the toast routes back here, natively */
}
- (void)pill:(id)sender {   /* the handle's tap: the strip, without a gesture from iOS's own edge */
	(void)sender;
	ios_ui_bar_open();
	ios_ui_haptic(0);
}
- (void)pulled:(UIPanGestureRecognizer *)p { (void)p; }   /* the observer fires the pull itself; this recogniser never begins */
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { (void)g; return NO; }   /* so it never takes a touch from the game */
- (void)tick:(CADisplayLink *)l { (void)l;
	const int on = touchpad_on();
	if (g_eye) eye_look();   /* the menu's toggle reaches the eye */
	{
		/* the bar, its menus, a dialog: whatever ImGui holds over the picture gets the pixels, and
		 * the pad's controls (their drawing: the layer; their taps: the buttons under it) stand down;
		 * the native strip says the same with bar_visible() */
		const int hide = overlay_pad_hidden() != 0 || bar_visible() != 0;   /* (bitmask of its reasons: the once-a-second line tells) */
		if (hide != g_pad_hidden) {
			g_pad_hidden = hide;
			g_eye.hidden = hide;
			if (g_pull_pill) g_pull_pill.hidden = hide;   /* the handle stands down with the pad, over the strip too */
			if (g_pad_layer) { g_pad_layer.hidden = hide || !on; [g_pad_layer setNeedsDisplay]; }
		}
	}
	{	/* the strip alone slides back up when nobody has touched it for a moment (an open panel holds it) */
		if (g_bar && g_bar_shown && g_panel_tab < 0 && chrome_now() - g_bar_last > 2.5 && !overlay_is_open()) bar_up_close_all();
	}
	{	/* once, the whole chrome's own answers: the pill and the eye, their frames and their tree (test30's pill never painted -- this line says which piece of that was true) */
		static int said = 0;
		if (!said && g_pull_pill && g_eye) {
			said = 1;
			chrome_log("    chrome: chrome check: pill (%.0f, %.0f, %.0f x %.0f) hidden %d in-window %d, eye (%.0f, %.0f, %.0f x %.0f) hidden %d in-window %d",
			           g_pull_pill.frame.origin.x, g_pull_pill.frame.origin.y, g_pull_pill.frame.size.width, g_pull_pill.frame.size.height,
			           g_pull_pill.hidden, g_pull_pill.window != nil,
			           g_eye.frame.origin.x, g_eye.frame.origin.y, g_eye.frame.size.width, g_eye.frame.size.height,
			           g_eye.hidden, g_eye.window != nil);
		}
	}
	osd_tick();     /* the stats overlay's own label (Off: nothing, ever) */
	pause_tick();   /* the PAUSED card while Game > Pause, never over a menu */
	intro_tick();   /* the first-launch strip: its twelve-second and first-touch rules live here */
	if (g_cfg_dim && !g_cfg_dim.hidden && g_cfg_page == 1 && g_cfg_fps)
		g_cfg_fps.text = [NSString stringWithFormat:@"%.0f fps", overlay_fps()];   /* the live number, while it shows */
	{
		/* once a second, the chrome's whole state in one line: the hidden bits (why the pad stood
		 * down: 1 the menu, 2 the intro, 4 the bar down, 8 a popup), what the pads and sticks are
		 * doing, and which buttons think they have a thumb */
		static double said; static int said_on = -1, said_eye = -1;
		const double now = chrome_now();
		if (on != said_on) { said = 0; said_on = on; said_eye = -1; }   /* a pad flip says itself at once */
		if (now - said >= 1.0) {
			said = now;
			const TpVisual *tv = touchpad_visuals();
			char held[16]; int n = 0;
			for (int i = 0; tv->on && i < tv->nb && i < 8; i++) held[n++] = g_pad_hits[i] && g_pad_hits[i]->down ? '0' + i : '.';
			held[n] = 0;
			chrome_log("    chrome: hidden bits %d, pad %s, sticks %s%s, held [%s], drew %d", overlay_pad_hidden(), on ? "on" : "off",
			           tv->sl_active ? "L" : "-", tv->sr_active ? "R" : "-", tv->on ? held : "-", g_pad_draws);
			(void)said_eye;
		}
	}
	if (g_pad_layer) [g_pad_layer sync];   /* every tick: the signature inside decides whether anything repaints */
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
static UIWindow *chrome_window(void) {
	for (UIScene *s in [UIApplication sharedApplication].connectedScenes)   /* the scene API: iOS 13's own way */
		if ([s isKindOfClass:[UIWindowScene class]]) { UIWindow *w = ((UIWindowScene *)s).keyWindow; if (w) return w; }
	return [UIApplication sharedApplication].keyWindow;   /* a scene still coming up, or none at all */
}

void ios_ui_chrome_install(void) {
	if (g_installed) return;
	const char *off = getenv("RECOMP_NATIVE_CHROME");   /* =0: the ImGui chrome keeps the phone instead */
	if (off && off[0] == '0' && off[1] == '\0') return;
	if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ ios_ui_chrome_install(); }); return; }
	UIWindow *win = chrome_window();
	if (!win) { chrome_log("    chrome: no window to install into (the ImGui chrome keeps the phone)"); return;   /* nothing to hang from yet */ }
	g_win = win;
	{	/* where the chrome lives: on the window itself, beside the game's root view. Step 30 tried the
	 * root view controller's view (the one SDL's Metal content sits in) -- and it went dark: not one
	 * touch, not one paint, all session, while the very same views on the window had taken touches
	 * dead-precisely in test19 (Step 31's numbers, then nothing from Step 30 on). Whatever that
	 * view is at install time, it is not the tree the glass talks to; the window is. */
		g_host = win;
	}
	{
		const char *np = getenv("RECOMP_NATIVE_PAD");   /* =0: the native pad never comes up (the ImGui pad and the finger path again) */
		g_pad_disabled = np && np[0] == '0' && np[1] == '\0';
	}
	chrome_log("    chrome: install (window %p, %.0fx%.0f bounds; host %p (%s); pad %s)", win, win.bounds.size.width, win.bounds.size.height,
	           g_host, g_host == win ? "the window" : "the root view", g_pad_disabled ? "OFF (RECOMP_NATIVE_PAD=0)" : "on");

	g_center = [[ChromeCenter alloc] init];   /* kept: UIKit's targets and delegates don't retain */
	g_eye = [[UIButton buttonWithType:UIButtonTypeCustom] retain];   /* +1 (buttonType autoreleases): the window's, after addSubview */
	g_eye.frame = CGRectMake(8.0f, 1.0f, 46.0f, 26.0f);   /* tp_layout's own call moves it to the corner's margin */
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
		g_pull_pill = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
		g_pull_pill.frame = CGRectMake(win.bounds.size.width * 0.5f - 24.0f, 5.0f, 48.0f, 18.0f);
		g_pull_pill.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
		g_pull_pill.layer.cornerRadius = 9.0f;
		g_pull_pill.backgroundColor = rgba(16, 18, 24, 0.78f);   /* the view's own property, the eye's proven path (test30's layer.backgroundColor never painted) */
		g_pull_pill.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.35f].CGColor;
		g_pull_pill.layer.borderWidth = 0.5f;
		UIImage *chev = glyph(@"chevron", 13.0f, 9.0f, [UIColor colorWithWhite:1.0f alpha:0.80f]);
		[g_pull_pill setImage:chev forState:UIControlStateNormal];
		g_pull_pill.imageView.contentMode = UIViewContentModeCenter;
		[g_pull_pill addTarget:g_center action:@selector(pill:) forControlEvents:UIControlEventTouchUpInside];
		[g_host addSubview:g_pull_pill];
		[g_host bringSubviewToFront:g_pull_pill];
		[g_pull_pill release];
		chrome_log("    chrome: pull pill made (%.0f x %.0f at (%.0f, %.0f), window %.0f x %.0f)",
		           g_pull_pill.frame.size.width, g_pull_pill.frame.size.height, g_pull_pill.frame.origin.x, g_pull_pill.frame.origin.y,
		           win.bounds.size.width, win.bounds.size.height);
	}

	TopPull *pull = [[TopPull alloc] initWithTarget:g_center action:@selector(pulled:)];
	pull.delegate = (id)g_center;
	[win addGestureRecognizer:pull];
	[pull release];

	{	/* the pad: its picture (a full-screen canvas, synced by the display link) and its touch
		 * areas (picked up by tp_layout's own call, ios_ui_pad_layout, as its numbers change) */
		memset(g_pad_hits, 0, sizeof g_pad_hits);
		g_pad_layer = [[PadLayer alloc] initWithFrame:g_host.bounds];
		g_pad_layer.userInteractionEnabled = NO;   /* touches fall through to the game, always */
		g_pad_layer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		g_pad_layer.hidden = YES;   /* until tp_layout says the pad is on */
		[g_host addSubview:g_pad_layer];
		[g_pad_layer release];   /* the host owns it */
	}

	g_toast_host = [[UIView alloc] initWithFrame:CGRectZero];
	g_toast_host.userInteractionEnabled = NO;   /* the corner they stack in never takes a touch */
	g_toast_host.translatesAutoresizingMaskIntoConstraints = NO;
	[g_host addSubview:g_toast_host];
	[g_toast_host.topAnchor constraintEqualToAnchor:g_host.safeAreaLayoutGuide.topAnchor constant:8.0f].active = YES;
	[g_toast_host.trailingAnchor constraintEqualToAnchor:g_host.safeAreaLayoutGuide.trailingAnchor constant:-10.0f].active = YES;
	[g_toast_host.widthAnchor constraintEqualToConstant:300.0f].active = YES;
	[g_toast_host.bottomAnchor constraintLessThanOrEqualToAnchor:g_host.centerYAnchor].active = YES;
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
	[g_toast_stack release];

	CADisplayLink *dl = [CADisplayLink displayLinkWithTarget:g_center selector:@selector(tick:)];
	[dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];   /* the menu's toggle reaches the eye */

	g_installed = 1;
}

/* tp_layout calls this with the eye's own x (the leftmost margin) -- the eye and the shoulder pill
 * can never drift apart, the same place ImGui's chip derived (overlay.cpp) while it held the slot */
void ios_ui_chrome_place(float x) {
	if (!g_eye) return;
	if (![NSThread isMainThread]) { const float v = x; dispatch_async(dispatch_get_main_queue(), ^{ ios_ui_chrome_place(v); }); return; }
	CGRect f = g_eye.frame;
	if (f.origin.x != x) { f.origin.x = x; g_eye.frame = f; }
}
