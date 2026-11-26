
### Step 19 — a phone's UI at the right size, and the touch it broke

Tested on a 15 Pro Max (3x), the phone UI collapsed: text the size of a
thumb, the touch card taller than the screen, the controls bunched in the
middle of the display far from the fingers, and touches "barely working".
Four real bugs, one design pass:

1. **The text was sized in pixels and drawn in points.** `phone_em()` read
   `window_pixel_size()` (1290 px on that phone) while ImGui draws in the
   window's *point* size (430). Every screen of text drew 2x too big on an
   iPhone 11, 3x on the Pro Max. `phone_em()` now reads ImGui's
   `DisplaySize`, and the theme rebuilds itself on the first frame, when
   that size first exists (17 pt, floored: iOS's own body text).
2. **The safe-area insets were pixels too** (`ios_shims.m` multiplied
   UIKit's points by the screen scale), fed into a layout in points: the
   stick rode 177 pt in from the edge on the Pro Max -- a third of the way
   to the middle. The shim now reports points, and `tp_layout` clamps
   them where they don't bite (the notch and the home indicator sit at the
   *centre* of their edges; every control sits in a *corner*).
3. **Taps on the menu bar leaked into the game.** A finger landing on the
   bar (or the pull tab, or one of its menus) was a screen touch to the
   game *and* a tap to the menu at once -- and the bar, which on a phone
   has no hover, pinned itself over the shoulders forever after the first
   tap. `overlay_owns_point()` now answers for a *landing* finger whether
   it is over the overlay's own controls (a finger already down keeps its
   owner: dragging off a control is still that control's); the bar's
   "pointer over it" is true only while a finger is actually on the glass
   (a real mouse, in `RECOMP_UI_PHONE=1` desktop runs, still hovers), and
   it slides away a second after the finger leaves. With a menu open,
   every tap closes it, none reaches the game.
4. **The shoulder pills never drew their outlines** (an ImGui 1.92.8
   argument-order change: 1.5 in `flags`, 0 thickness), and the face
   buttons were labelled with a keyboard's "X", "O", "[]" and "/\". The
   Vita's own symbols are drawn as shapes now (a stencil line weight that
   scales with the button), start/select are a play mark and menu bars.

The phone's quick menu (the top bar) has Game / Display / Controls:
Metal HUD and On-screen controls toggles, control size and
see-throughness, the stats and the resolution, "All settings…"
(findable -- the reason the Metal HUD row was unfound was the 3x text
pushing it off the screen), a bigger pull tab (110x20), finger-height
rows, and no keyboard hints anywhere (Help's shortcuts page is the
phone's own controls story). The touch card is rebuilt: small title,
two demo cards, one line each. The menu header scales its game name
down to the space the Resume button leaves and ellipsises, instead of
running under it.

The game's touch panel is what "touch behind the controls" means, so
`RECOMP_PAD_DEBUG=1` logs where every landing finger went now: a named
control, "the game's touch panel -- no control was touched", or "the
overlay's own tap"; `RECOMP_FINGER_SCRIPT` scripts them without a
touchscreen (a window is needed -- the phone build being a cross build
on this box, the script is exercised on the device).

Open: none of this was render-verified (no Windows toolchain on this
box for the dump loop; the pack's `--smoke` boots the runtime only).
The first run on the phone is the verification.

### Step 20 — the pad's one scale, a toggle that obeyed, and no injected HUDs

test9's device report (a 15 Pro Max, with its session.log):

- **"The on-screen controls toggle does nothing."** True:
  `touchpad_want()` cached the setting in a static on first read, and
  `touchpad_set_on()` never told it -- on the phone you could only
  change the pad by restarting. The cache now invalidates on write.
- **"Touch not working in random places; with 'it' disabled and a
  restart, works."** Two causes. (a) The pad was laid out twice a
  frame in two different coordinate systems: the overlay thread in
  the display's points, the game thread -- per input read -- in
  swapchain pixels (3x on this phone), each relayout a memset of the
  shared struct mid-event. Intermittent half-cleared hit tests are
  "random places" exactly; one layout path now exists, the overlay's,
  in points. (b) The floating second stick claimed 55% x 70% of the
  picture, the middle of the screen where this game aims its camera
  by swipes. It claims the lower right *corner* now, and it's a
  setting ("Second stick", the bar's Controls menu and the Controls
  page).
- **"HUD related."** The Metal HUD on a phone is not Apple's drawn
  overlay but a third-party dylib injection (libMTLHud answers
  MTL_HUD_ENABLED -- its own hooks logged in the session): with it
  on, touches died in places and the orientation broke on an
  app-switcher re-entry; off and restarted, both worked. The toggle
  and the env var are gone on iOS (kept on macOS, where it is
  Apple's); a phone's stats are the overlay's own drawn HUD. The
  setting in an old file is ignored.
- **"First screen useless and doesn't fit."** Replaced: the touch
  card that filled the screen over a paused game is a small strip at
  the bottom centre now, over the *running* game, no pause, taps
  falling through it (NoInputs), dismissed by the first touch
  anywhere or twelve seconds.
- The plist gained UIApplicationSupportsIndirectInputEvents (SDL's
  own iOS warning in the log).

Unchecked, for the device: the app-switcher orientation break with
the injection now impossible (the report correlated it with the HUD
being on); and the joystick, whose "not working" fits the racing
layouts -- same fix, first test will tell.


### Step 21 — the HUD chip, the pack's own corner, and re-entry healed

test10's device round (a 15 Pro Max):

- **"The screenshot swipe squashes the game into a corner."**
  Re-entering the foreground can leave SDL believing a stale, small
  window (the whole picture shrunk against the lower-left corner, the
  on-screen controls huge in the upper-left, until the app restarted).
  Every time focus returns the window's size is re-asserted from the
  display's own mode (points; portrait flipped -- this app is
  landscape-only), a reshape only when it actually drifted, one log
  line each time. The plist also gained CADisableMinimumFrameDurationOnPhone
  (SDL's own advice for 120 Hz phones).
- **"The HUD blocks the game's touchable icons."** Golden Abyss keeps
  its actions along the right edge (the icon bar) and aims its camera
  by swipes -- exactly the lower-right corner the floating second
  stick claimed. The zone is a pack's choice now
  (RECOMP_TOUCHPAD_RSTICK in RUN_ENV); this pack takes it *off*, the
  menu's "Second stick" toggle overrules for a player, and the toggle
  reads the effective value.
- **"The pull tab was fine as it was."** The always-faint tab idea was
  reverted: the tab fades in near the top, as before.
- **The controls chip** (the phone's own request): a small stick-icon
  chip at the top, beside the pull tab, always drawn -- even with the
  pad off, that being its point -- a tap flips the on-screen pad live
  (the toggle obeys since Step 20), a toast says which way, a slash
  through the icon when off. The first-run strip teaches it.

### Step 22 — the top strip no longer trusts a synthesized mouse

test11's report finished the picture: the chip drew but a tap on it did
nothing, and the pull tab never showed at all. The whole top strip
hung off one fragile chain -- SDL synthesizing "mouse from touch"
events for ImGui -- and it died with Step 20's plist key
(UIApplicationSupportsIndirectInputEvents, added to silence SDL's own
warning; with it, UIKit changes how the view is delivered pointer
input, and on this device the synthesized mouse never arrived again,
taking every ImGui tap with it: the chip, the tab, the bar's hot zone).

Two changes:

- **UIApplicationSupportsIndirectInputEvents removed** (SDL's
  warning line returns; it is a warning about trackpads and pencils,
  which this game has no use for on a phone).
- **The chip, the pull tab and the bar's opening all answer the
  finger event itself now** (overlay_finger_nav, straight from
  window.c's FINGER_DOWN, before anything else claims it): the chip
  flips the pad live, the tab (while it shows) brings the bar, and a
  pull from the bare top edge -- the ~9 points above every control --
  opens the bar directly. ImGui still handles the bar's own menus;
  nothing else on the glass needs SDL's synthesized mouse.

The fingers' full routing, with RECOMP_PAD_DEBUG=1 logging each: the
overlay's own gesture (chip/tab/pull) > the overlay's own tap (bar
and menus, dialogs) > a named pad control > the game's touch panel.

### Step 23 — the eye in the corner, and one tap per tap

test12's report was the confirmation the plist theory needed: the pull
worked again (the synthesized mouse was back the moment its Step 20
killer left the plist), and the chip's single tap fired *twice* --
"controls off" and "controls on" in one flick, the pad flashing -- the
native handler and the ImGui button both answering the same finger.

The chip is ImGui's one button now (the native twin is gone; only the
pull tab and the bare top-edge pull still answer finger events
natively). It also moved, per the phone's own design eye: out of the
top centre (the pull tab's place, and the banners') and into the top
left corner, beside the shoulder pill (the side flips with the
left-handed layout's), as a small, dim eye -- open while the controls
show, slashed when they don't -- half the size, most of the showiness
gone: "small opaque eye".

### Step 24 — both sticks dynamic; a tap is always the game's

The phone's own control design, replacing the hybrid the pad began
with (a fixed left circle to find, a corner zone that claimed whole
regions of the right):

- **Both sticks are dynamic.** Neither claims a finger as it lands
  (tp_hit answers buttons only now). Touch and hold (~a sixth of a
  second) or drag (past ~12 points) in the lower-left pocket and the
  movement stick spawns under the thumb, base where it landed, knob
  following; the right pocket the second stick, and only where the
  pack keeps one. The left-handed layout flips the pockets.
- **A tap is always the game's.** A landing finger in a pocket is the
  game's touch first; when it becomes a stick, that brief touch ends
  with the panel's own release path -- the game saw a tap, as on the
  Vita, never a stolen swipe.
- The fixed left-stick circle is gone from the picture: like the
  right's, it is nothing until a thumb is on it (pad_draw), and the
  first-run strip and the Controls page teach "hold or drag".

Thresholds chosen with Uncharted in mind: its camera swipes and
charcoal rubs begin mid-screen, outside both pockets, and its quick
taps -- wherever they land -- always reach the game.

### Step 25 — the eye owns the corner

The phone's placement, final: the eye always sits at the top-left
corner's very slot, and whichever shoulder pill is physically left
stands off 54 points to its right. The pill's own left edge is what
the eye draws its slot from (and window.c's layout shifts the pill
for), so the two cannot drift. Left-handed flips the pills, never the
eye.

### Step 26 — the chrome becomes UIKit's own

The fix round first (test16): `tp_clear` also forgets the pockets'
waiting fingers; the stick thresholds read RECOMP_STICK_DRAG and
RECOMP_STICK_HOLD; Game grows a Frame rate 30/60 toggle; the pad's
debug line prints the eye's slot and the pockets' bounds.

Then the part the phone kept asking for: native chrome. The toolchain
has no Swift (no swiftc, and SwiftUI wants a Swift runtime), so
"native" here means Objective-C UIKit -- `runtime/platform/ios_ui_chrome.m`,
compiled into the iOS host set and installed once, right after the
SDL window exists:

- **The eye is a UIButton** now, in the same corner slot (tp_layout
  hands its leftmost margin to `ios_ui_chrome_place`, so pill and eye
  still cannot drift). SF Symbols `eye`/`eye.slash`, the same dim
  rounded chip, and taps route through the same `touchpad_set_on` +
  the same toast text as before. A CADisplayLink keeps the icon in
  step with the menu's own toggle.
- **The pull is a UIPanGestureRecognizer** on the window itself: it
  sees every touch while being the hit-test target of none, begins
  only for a finger that lands within 16 points of the top edge and
  moves down, and its Began posts `overlay_bar_open` -- an atomic
  request the next ImGui frame takes in. The ImGui pull tab, its tap
  and the old top-edge path all remain.
- **The toasts are UIViews**, stacked at the top right inside the
  safe area: the same dark card, amber edge and amber title, three at
  most, fading in and out with Core Animation. overlay_toast_titled
  routes there while the chrome is active.

While it's installed, the ImGui twins stand down (build_pad_toggle
returns; toasts skip the queue), and `RECOMP_NATIVE_CHROME=0` installs
nothing at all -- the ImGui eye, pull and toasts carry the phone as
they did. The chip's pad-off bug went with it: the eye's x is its own
number now (touchpad_eye_x), not a pill's left edge (a pad-off layout
has no pill, and the chip sat at -54, off the glass).

### Step 27 — the pad itself: UIKit's pixels, touches, and the taptic engine

The controls stop being an ImGui card traced over the game. Two halves,
one layout (tp_layout's TpVisual, the same numbers window.c hit-tests
with -- neither picture nor touch can drift from it):

- **PadLayer** (ios_ui_chrome.m) is the pad's whole picture: a
  full-screen canvas drawing the very shapes and colours pad_draw drew
  -- the fills, rings, the Vita's glyphs as Core Graphics paths, the
  same weights -- dirty-rect synced per frame by the display link (a
  button's box while it can change, a wider box around a live stick so
  the knob can slide). While the native chrome is on, pad_draw stands
  down entirely; RECOMP_NATIVE_CHROME=0 brings the ImGui pad back.
- **PadBtn** is each control's touch area: invisible, pointInside the
  exact test tp_hit makes (a pill's box, a 1.18-radius circle), and
  stepping aside wherever overlay_owns_point says ImGui owns the
  point -- a bar menu over the shoulders or a dialog behaves exactly
  as before, the finger falling through to SDL. A touch presses
  through window.c's own native path (touchpad_native_press: tp_bits
  and the down flag, tp_release letting go), so the game's input and
  the pressed visuals are identical to the finger path's.
- **Haptics everywhere**: a button taps light, the shoulders medium, a
  thumb's hold becoming a stick taps soft (fired from the very line
  tp_zone_hold spawns it at), the eye and a pull from the top edge tap
  light. UIImpactFeedbackGenerator, prepared as first asked.
- While overlay_pad_hidden (our menu, the intro, the bar, a popup) is
  up, the native picture stands down -- it draws over everything
  UIKit-side, so it must mind what the ImGui pad never had to.

The dynamic sticks' logic -- pockets, tap-pass-through, hold and drag
thresholds -- is untouched in window.c; only what the pad *looks like*
and *answers with at the glass* went native.

### Step 28 — the broken pad round: instrument, and give the pad a floor

test17 came back from the phone wrong all over: a haptic on every
touch, no controls drawn, the game's own touches and the pull dead.
The session.log had nothing to say about any of it -- nothing of the
chrome had ever learned to speak -- so this round makes the phone able
to tell the story itself:

- Every chrome event logs (the `chrome:` lines, into session.log):
  the install (which window, what bounds, whether RECOMP_NATIVE_PAD
  turned the pad off), every pad layout (each button's frame and
  shape), each button's press/release/cancel with its point, every
  pull's start, every haptic with its cause, and -- once a second --
  one state line: overlay_pad_hidden's *bitmask of reasons* (1 the
  menu, 2 the intro, 4 the bar, 8 a popup -- it used to be a blind
  yes/no), the pad on/off, which sticks live, which buttons think
  they're held.
- RECOMP_PAD_DEBUG=1 rides in the pack this round, so the log also
  shows each finger's routing (whose touch went where, one line per
  finger event) -- the one thing the chrome's own lines can't see:
  whether SDL sees the fingers at all.
- RECOMP_NATIVE_PAD=0 (env.txt, no rebuild needed) stands the whole
  native pad down into exactly the old behaviour: pad_draw returns
  only while the native pad actually draws (its own ios_ui_chrome_
  pad_on, not the chrome's blanket word), so ImGui's pad and the
  finger path own the glass again. RECOMP_NATIVE_CHROME=0 still
  takes the eye, the pull and the toasts with it.

### Step 29 — the whole-glass swallow: pointInside was the whole hit test

test18's log named it in one read: every touch, anywhere on the
screen, was delivered to button 7 -- points like (533, 353) landing
on a view whose logged frame is (369, 11, 61 x 25) -- and SDL saw
exactly one finger the whole session (one pull, before the pad's
views even existed). Root cause: UIKit asks `pointInside:` as *the
entire* hit test -- it does not pre-check the frame on its own --
and the pill branch answered YES unconditionally, so the last-added
pill (the window's reverse hit-test walk finds it first) swallowed
every touch on the glass: the haptic on every tap, the game's own
touch panel dead, the intro card open and undismissable (all its
taps eaten too, which is why "hidden bits 2" stayed on to the end).

The fix is the one honest line: `CGRectContainsPoint(self.bounds, p)`
-- a pill takes its own box and nothing else. The circle buttons
already had the bounds-relative math; only the pills lied.

The finger-routing debug stays in the pack this one round: its
presence is the proof -- test18's log never once said "the game's
touch panel", and test19's must say it everywhere the controls
aren't.

### Step 30 — the canvas that drew nothing: where the chrome lived

test19's log cleared the machine: every finger routed itself
correctly (the panel got its taps by the dozen, buttons taken only
inside their frames, sticks spawning with their soft haptic), the
pad's hidden-bits were 0 -- and still the buttons drew nothing, while
the ImGui bar over the very same glass did. Touches proved the
window live and the views on top; nothing proved any native pixel
had ever reached the screen (the eye was never confirmed either,
in three rounds of chrome).

The one difference from every working overlay app: the chrome hung
off the *window*, a sibling of SDL's root view -- so test20 moves it
inside `rootViewController.view`, the same view the game's Metal
content lives in, added after it (above in both compositing and
hit-testing, the way any overlay view over a game is actually
built). And the round is self-proving either way: the canvas logs
its first draw, the tick's line carries a running draw count, and an
amber square -- pure UIKit, none of the pad's state -- sits under
the top bar's centre (RECOMP_PAD_CANVAS_DEBUG=0 takes it off).
Seeing the square with buttons painted says the move fixed it;
seeing nothing with the draw count climbing would say compositing
still, and the next move is written from that.

### Step 31 — %@ is not a C format specifier

test20 insta-crashed, and its log caught the killer mid-sentence:
"chrome: install (... host 0x11ec04000 @," -- chrome_log formats
with plain vfprintf, and `%@` is Foundation's, not C's: vfprintf
took a Class object where it wanted an NSString and died in place.
The fix is a string literal where the class went ("the root view" /
"the window itself") -- and the dying line, usefully, had already
confirmed the real prize: the root view controller's view exists and
is not the window, so the chrome's new home from Step 30 is exactly
where it was meant to live.

### Step 32 — the canvas stops asking drawRect for anything

test21's log's one number decided it: `drew 0`, all session, with
eight buttons laid out and nine dirty rects marked every tick --
drawRect never ran once, so the missing buttons were never a
compositing question; the canvas never painted a pixel for UIKit to
composite. Rather than keep researching why a scheduled drawRect
wouldn't fire under SDL's run of the main runloop, the canvas now
skips that path entirely: `pad_paint_cg` (the same Core Graphics
shapes, fills, rings and glyphs) paints into an offscreen
UIGraphicsImageRenderer image whenever the pad's state actually
changed (a signature of every number a pixel depends on -- nothing
changed, nothing rendered), and a plain UIImageView carries the
pixels. That is the same delivery as every other UIKit control on
the screen, no drawRect in the path anywhere.

The amber square moved into the painted image (still
RECOMP_PAD_CANVAS_DEBUG=0 to take it off), the counter keeps its
name -- `drew N` in the once-a-second line is paints now -- and the
first paint of the session says its size and scale.

### Step 33 — back to the window: the root view was never the tree the glass talks to

test22's log made two eras legible: from Step 30 on (the chrome inside
`rootViewController.view`) not one button touch and not one pull
arrived -- yet test19's window-hosted views took touches
dead-precisely (btn 2 at (834, 359) inside (805, 358, 56 x 56)).
Whatever that root-view object is at install time (one subview, the
metal view, by every appearance live), it is not part of the tree
iOS delivers to -- the window is. So the chrome returns to the
window, and the drawing question that first sent it hunting for a
new home is already answered by Step 32's canvas: no drawRect
anywhere in the path, the picture painted into an image and a plain
UIImageView carrying it, state-changes only.

Window-hosted + image-carried is the combination never tried
before: test19 had the window but a drawRect that never ran; test22
had the image but a host that took no touches. This is both halves
of the answer in one build.

### Step 34 — the pull becomes an observer; the picture gains a raw layer

test23's log ended two arguments at once. The menu that "doesn't
always open": `pull began` had never once appeared in any session's
log -- the delegate-consulted pan never began under SDL's run of
the runloop, and the menu that did open rode the old 9-point strip
alone -- while five of the user's taps at (165, 14), (181, 20)...
were the L shoulder pill eating their pulls. So:

- The pull is no longer a recogniser's decision. It observes: any
  touch that begins in the window's low 16 points (off the eye's
  square) and moves 12 points down opens the bar once, logged
  (`pull fired`). The recogniser itself never formally begins
  (its delegate always answers no), so the game's own contact under
  the same finger goes on untouched.
- The top strip's low 14 points are navigation's, always: the pad's
  native touch areas step out of the band (a pull or a tap there
  never presses a button), and overlay_finger_nav's own strip
  widens from 9 to 14 to match.
- The invisible picture gets a second, primitive carrier: the same
  painted image now also lands on a raw CALayer placed after every
  subview's layer -- over everything, no view machinery in the
  path. Whichever of picture and pixel story is true, one build
  now carries both.
