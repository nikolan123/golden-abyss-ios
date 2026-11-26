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
#include <stdlib.h>
#include <math.h>
#include "../ui/touchpad.h"   /* runtime/ui/touchpad.h: the one true layout -- tp_layout's own TpVisual */

/* the game's own (window.c / overlay.cpp) */
extern int  touchpad_on(void);
extern void touchpad_set_on(int on);
extern void overlay_toast_titled(const char *title, const char *body, double seconds);
extern void overlay_bar_open(void);
extern int  overlay_is_open(void);
extern int  overlay_owns_point(float x, float y);
extern int  overlay_pad_hidden(void);   /* overlay.cpp: the bar/menus/a dialog over the picture -- the pad draws no pixels then */
extern void touchpad_native_press(int which);    /* window.c: the same state a finger on the glass would set */
extern void touchpad_native_release(int which);
void ios_ui_haptic(int kind);                    /* this file's own: 0 light, 1 medium, 2 soft */

static UIWindow      *g_win;
static UIView        *g_host;        /* where the chrome lives: the root view controller's view (the same view SDL's Metal content lives in; added after, composited and hit-tested above) */
static UIButton     *g_eye;          /* owned by the window (installed once, never removed) */
static UIView       *g_toast_host;   /* the corner the toasts stack into, owned the same way */
static UIStackView  *g_toast_stack;  /* the toasts, newest on top, the oldest past three */
static int           g_installed;    /* ios_ui_chrome_install ran: everything's in place */
static int           g_eye_on = -1;  /* what the eye last drew: the menu's toggle must reach it too */
static int           g_pad_hidden = -1;   /* what the pad last showed under: 0 over the game, 1 under a menu, set hidden to match */
static int           g_pad_disabled;      /* RECOMP_NATIVE_PAD=0: the native pad stands down (the ImGui pad draws, the finger path owns the taps) */
int g_pad_draws;                          /* how many times the canvas has actually drawn (the tick's line says it) */

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

/* ---- the eye ---------------------------------------------------------------------------- */
static void eye_look(void) {
	const int on = touchpad_on();
	if (on == g_eye_on) return;
	g_eye_on = on;
	UIImage *img = [UIImage systemImageNamed:(on ? @"eye" : @"eye.slash")];
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14.0 weight:UIImageSymbolWeightMedium];
	img = [img imageByApplyingSymbolConfiguration:cfg];   /* nil-safe: same name, same size, or the plain glyph */
	[g_eye setImage:img forState:UIControlStateNormal];
	g_eye.tintColor = on ? [UIColor colorWithRed:0.92f green:0.94f blue:1.00f alpha:0.88f]
	                     : [UIColor colorWithRed:0.59f green:0.61f blue:0.67f alpha:0.78f];
	g_eye.backgroundColor = [UIColor colorWithWhite:0.118f alpha:(on ? 0.62f : 0.44f)];
}

/* ---- the pad: UIKit's own buttons, and the picture drawn ---------------------------------- */
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
	{	/* wherever ImGui owns the point, the finger is its (a menu over the shoulders, a dialog):
		 * fall through as though this control were not here -- the exact behaviour the tap used to have */
		const CGPoint wp = [self convertPoint:p toView:nil];
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

/* the pad's picture: everything tp_layout laid out, drawn once per dirty rect the display link asks
 * for (a button's box while it can change, a wider box around a live stick so the knob can slide) */
@interface PadLayer : UIView {
 @public
	BOOL sl_was, sr_was;   /* a stick that just ended paints its own last box once, and its clearing */
}
@end

@implementation PadLayer
- (instancetype)initWithFrame:(CGRect)f {
	if ((self = [super initWithFrame:f])) { sl_was = sr_was = NO; }
	return self;
}
- (void)sync {
	const TpVisual *tv = touchpad_visuals();
	if (!tv->on || !tv->nb) return;
	for (int i = 0; i < tv->nb; i++) {   /* the buttons: their boxes, a little grown, held dirty while the pad is on */
		const TpButton *b = &tv->b[i];
		if (b->pill) [self setNeedsDisplayInRect:CGRectMake(b->x - b->hw - 4.0f, b->y - b->hh - 4.0f, 2 * b->hw + 8.0f, 2 * b->hh + 8.0f)];
		else { const float e = b->r * 1.18f;
			[self setNeedsDisplayInRect:CGRectMake(b->x - e - 4.0f, b->y - e - 4.0f, 2 * e + 8.0f, 2 * e + 8.0f)]; }
	}
	const float pr = tv->sl_r * 1.45f + 4.0f;   /* a live stick's box: base and knob, wherever it slides */
	if (tv->sl_active) { [self setNeedsDisplayInRect:CGRectMake(tv->sl_x - pr, tv->sl_y - pr, 2 * pr, 2 * pr)]; self->sl_was = YES; }
	if (tv->sr_active) { const float qr = tv->sr_r * 1.45f + 4.0f; [self setNeedsDisplayInRect:CGRectMake(tv->sr_x - qr, tv->sr_y - qr, 2 * qr, 2 * qr)]; self->sr_was = YES; }
}
- (void)drawRect:(CGRect)rect {
	(void)rect;
	const TpVisual *tv = touchpad_visuals();
	if (!tv->on) return;
	{
		g_pad_draws++;
		static int said;
		if (!said) { said = 1; chrome_log("    chrome: canvas drew (bounds %.0fx%.0f, opacity %.2f)", self.bounds.size.width, self.bounds.size.height, tv->opacity / 100.0f); }
	}
	CGContextRef c = UIGraphicsGetCurrentContext();
	{	/* RECOMP_PAD_CANVAS_DEBUG (default this round; =0 takes it off): an amber square under the
	 * top bar's centre, pure UIKit, none of the pad's state -- seeing it says the canvas composites;
	 * not seeing it says compositing, before anything about shapes or paths */
		static int want = -1;
		if (want < 0) { const char *e = getenv("RECOMP_PAD_CANVAS_DEBUG"); want = !(e && e[0] == '0' && e[1] == '\0'); }
		if (want) {
			CGContextSetFillColorWithColor(c, [UIColor colorWithRed:1.0f green:0.73f blue:0.28f alpha:0.85f].CGColor);
			CGContextFillRect(c, CGRectMake(self.bounds.size.width * 0.5f - 16.0f, 44.0f, 32.0f, 32.0f));
		}
	}
	if (!tv->nb || overlay_pad_hidden()) return;
	const float a = (tv->opacity < 0 ? 0 : tv->opacity > 100 ? 100 : tv->opacity) / 100.0f;
	UIColor *fill = rgba(12, 14, 18, 0.55f * a), *ring = rgba(235, 240, 255, 0.75f * a);
	UIColor *text = rgba(235, 240, 255, 0.90f * a), *hot = rgba(255, 255, 255, a);
	UIColor *base = rgba(10, 12, 16, 0.30f * a), *knob_fill = rgba(235, 240, 255, 0.22f * a);

	if (tv->sl_active || self->sl_was || tv->sr_active || self->sr_was) {   /* the sticks, only while a thumb is on one */
		CGContextSetLineWidth(c, 1.5f);
		CGContextSetStrokeColorWithColor(c, ring.CGColor);
		if (tv->sl_active) {
			CGContextSetFillColorWithColor(c, base.CGColor);
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
		self->sl_was = tv->sl_active;
		self->sr_was = tv->sr_active;
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
				NSMutableParagraphStyle *st = [[NSMutableParagraphStyle new] autorelease];
				st.alignment = NSTextAlignmentCenter;
				NSDictionary *at = @{NSFontAttributeName: f, NSForegroundColorAttributeName: ct, NSParagraphStyleAttributeName: st};
				[l drawInRect:CGRectMake(b->x - b->hw, b->y - b->hh, 2 * b->hw, 2 * b->hh) withAttributes:at];
			} else pad_glyph_cg(c, b->label, b->x, b->y, b->hh * 1.1f, ct);
		} else {
			CGContextSetStrokeColorWithColor(c, co.CGColor); CGContextSetLineWidth(c, 1.5f);
			CGContextFillEllipseInRect(c, CGRectMake(b->x - b->r, b->y - b->r, 2 * b->r, 2 * b->r));
			CGContextStrokeEllipseInRect(c, CGRectMake(b->x - b->r, b->y - b->r, 2 * b->r, 2 * b->r));
			pad_glyph_cg(c, b->label, b->x, b->y, b->r * 1.55f, ct);
		}
	}
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

/* ---- the pull: a pan that only ever means "the menu comes down" ---------------------------- */
/* A finger that begins within 16 points of the top edge, not on the eye (its square is the
 * button's own), and moves down, not along. The recognizer sits on the window itself, so it sees
 * every touch without being the hit-test target of any: the game's fingers are the game's until
 * the moment the pull actually recognizes (cancelsTouchesInView then does the one handoff). */
@interface TopPull : UIPanGestureRecognizer
@property CGFloat startX, startY;   /* where touch 0 landed, in the window's points */
- (BOOL)shouldPull;
@end

@implementation TopPull
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	self.startX = 1e9; self.startY = 1e9;
	UITouch *t = touches.anyObject;
	if (t && self.view) { const CGPoint p = [t locationInView:self.view]; self.startX = p.x; self.startY = p.y; }
	[super touchesBegan:touches withEvent:event];
}
- (BOOL)shouldPull {
	if (self.startY > 16.0f) return NO;
	if (g_eye && self.startY <= CGRectGetMaxY(g_eye.frame) && self.startX <= CGRectGetMaxX(g_eye.frame)) return NO;
	const CGPoint tr = [self translationInView:self.view];
	return tr.y > 3.0f;
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
- (void)pulled:(UIPanGestureRecognizer *)p { if (p.state == UIGestureRecognizerStateBegan) { TopPull *tp = (TopPull *)p; chrome_log("    chrome: pull began, start (%.0f, %.0f), now (%.0f, %.0f)", tp.startX, tp.startY, [p locationInView:nil].x, [p locationInView:nil].y); overlay_bar_open(); ios_ui_haptic(0); } }
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { return [(TopPull *)g shouldPull]; }
- (void)tick:(CADisplayLink *)l { (void)l;
	const int on = touchpad_on();
	if (g_eye) eye_look();   /* the menu's toggle reaches the eye */
	{
		/* the bar, its menus, a dialog: whatever ImGui holds over the picture gets the pixels, and
		 * the pad's controls (their drawing: the layer; their taps: the buttons under it) stand down */
		const int hide = overlay_pad_hidden() != 0;   /* (bitmask of its reasons: the once-a-second line tells) */
		if (hide != g_pad_hidden) {
			g_pad_hidden = hide;
			g_eye.hidden = hide;
			if (g_pad_layer) { g_pad_layer.hidden = hide || !on; [g_pad_layer setNeedsDisplay]; }
		}
	}
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
	if (g_pad_layer && !g_pad_layer.hidden) [g_pad_layer sync];   /* the buttons' boxes, a live stick's reach */
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
	{	/* where the chrome lives: inside SDL's own root view (the view its Metal content lives in --
	 * a sibling added after the game, so above it in both compositing and hit-testing). The window
	 * itself also carries the pull recognizer: it sees every touch without being anyone's target. */
		g_host = win.rootViewController.view;
		if (!g_host) g_host = win;
	}
	{
		const char *np = getenv("RECOMP_NATIVE_PAD");   /* =0: the native pad never comes up (the ImGui pad and the finger path again) */
		g_pad_disabled = np && np[0] == '0' && np[1] == '\0';
	}
	chrome_log("    chrome: install (window %p, %.0fx%.0f bounds; host %p (%s), %d subviews; pad %s)", win, win.bounds.size.width, win.bounds.size.height,
	           g_host, g_host == win ? "the window itself" : "the root view", (int)g_host.subviews.count, g_pad_disabled ? "OFF (RECOMP_NATIVE_PAD=0)" : "on");

	g_center = [[ChromeCenter alloc] init];   /* kept: UIKit's targets and delegates don't retain */
	g_eye = [[UIButton buttonWithType:UIButtonTypeCustom] retain];   /* +1 (buttonType autoreleases): the window's, after addSubview */
	g_eye.frame = CGRectMake(8.0f, 1.0f, 46.0f, 26.0f);   /* tp_layout's own call moves it to the corner's margin */
	g_eye.layer.cornerRadius = 11.0f;
	g_eye.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.24f].CGColor;   /* the chip's hairline */
	g_eye.layer.borderWidth = 0.5f;
	[g_eye addTarget:g_center action:@selector(eye:) forControlEvents:UIControlEventTouchUpInside];
	[g_host addSubview:g_eye];
	[g_host bringSubviewToFront:g_eye];
	[g_eye release];   /* the host owns it from here */
	g_eye_on = -1; eye_look();

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
