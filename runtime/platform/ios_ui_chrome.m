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

/* the game's own (window.c / overlay.cpp) */
extern int  touchpad_on(void);
extern void touchpad_set_on(int on);
extern void overlay_toast_titled(const char *title, const char *body, double seconds);
extern void overlay_bar_open(void);

static UIButton    *g_eye;          /* owned by the window (installed once, never removed) */
static UIView      *g_toast_host;   /* the corner the toasts stack into, owned the same way */
static UIStackView *g_toast_stack;  /* the toasts, newest on top, the oldest past three */
static int          g_installed;    /* ios_ui_chrome_install ran: everything's in place */
static int          g_eye_on = -1;  /* what the eye last drew: the menu's toggle must reach it too */

int ios_ui_chrome_active(void) { return g_installed; }

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

/* ---- the pull: a pan that only ever means "the menu comes down" --------------------------- */
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
	g_eye_on = -1; eye_look();   /* the menu's own wording: the toast routes back here, natively */
}
- (void)pulled:(UIPanGestureRecognizer *)p { if (p.state == UIGestureRecognizerStateBegan) overlay_bar_open(); }
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g { return [(TopPull *)g shouldPull]; }
- (void)tick:(CADisplayLink *)l { (void)l; if (g_eye) eye_look(); }   /* the menu's toggle reaches the eye */
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
	if (!win) return;   /* nothing to hang from yet: the ImGui chrome keeps the slot */

	g_center = [[ChromeCenter alloc] init];   /* kept: UIKit's targets and delegates don't retain */
	g_eye = [[UIButton buttonWithType:UIButtonTypeCustom] retain];   /* +1 (buttonType autoreleases): the window's, after addSubview */
	g_eye.frame = CGRectMake(8.0f, 1.0f, 46.0f, 26.0f);   /* tp_layout's own call moves it to the corner's margin */
	g_eye.layer.cornerRadius = 11.0f;
	g_eye.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.24f].CGColor;   /* the chip's hairline */
	g_eye.layer.borderWidth = 0.5f;
	[g_eye addTarget:g_center action:@selector(eye:) forControlEvents:UIControlEventTouchUpInside];
	[win addSubview:g_eye];
	[win bringSubviewToFront:g_eye];
	[g_eye release];   /* the window owns it from here */
	g_eye_on = -1; eye_look();

	TopPull *pull = [[TopPull alloc] initWithTarget:g_center action:@selector(pulled:)];
	pull.delegate = (id)g_center;
	[win addGestureRecognizer:pull];
	[pull release];

	g_toast_host = [[UIView alloc] initWithFrame:CGRectZero];
	g_toast_host.userInteractionEnabled = NO;   /* the corner they stack in never takes a touch */
	g_toast_host.translatesAutoresizingMaskIntoConstraints = NO;
	[win addSubview:g_toast_host];
	[g_toast_host.topAnchor constraintEqualToAnchor:win.safeAreaLayoutGuide.topAnchor constant:8.0f].active = YES;
	[g_toast_host.trailingAnchor constraintEqualToAnchor:win.safeAreaLayoutGuide.trailingAnchor constant:-10.0f].active = YES;
	[g_toast_host.widthAnchor constraintEqualToConstant:300.0f].active = YES;
	[g_toast_host.bottomAnchor constraintLessThanOrEqualToAnchor:win.centerYAnchor].active = YES;
	[g_toast_host release];   /* as above: the window owns it */

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
