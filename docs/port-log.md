
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

### Step 35 — the stale picture: sync stopped, and the torn paint stayed

test24 delivered the pixels, and its screenshots + the log told the
rest. The amber square measured *exactly* where the painter drew
it (466, 60, 32 x 32 -- to the pixel), so the raw layer rides
perfect. But the buttons over the pause menu measured 102 x 77
points where the layout says 121 x 32 -- mis-shaped, oversized,
over a menu where the pad must be invisible. The mechanics: the
tick stopped calling sync the moment a menu opened (the layer
counted as hidden), so the raw layer went on carrying the *last*
full-pad paint -- the one made in the torn instant when tp_layout
was mid-rewrite of the pad struct, garbage shapes that never
healed. The amber-only "hidden paint" ran at the same time and
proved, by being exact, that the compositor was never the problem.

So sync runs every tick now, hidden or not: the signature decides
whether anything repaints (torn reads heal one tick later; the
hidden bit is part of the signature, so a menu opening repaints
empty at once; the pad turning off takes both carriers down, the
raw layer included -- it is nobody's subview and hid by nobody
else). The amber probe comes out (RECOMP_PAD_CANVAS_DEBUG=1 brings
it back), and RECOMP_PAD_DEBUG leaves the pack: the finger routing
it printed is verified, and the log needs the quiet.

The pads' *intended* proportions have never actually been seen on
the glass yet -- every native picture so far was the torn one.
What test25 shows is the first honest look at the painter's shapes.

### Step 36 — the menu gets its taps, the letters their centre, the glyphs their size

Three from the phone's report, all clean:

- **A bar down stands the pad's touches down, not just its pixels.**
  The bar's tabs sit exactly in the shoulder pills' zone; tapping
  "Controls" was landing on the L pill underneath. PadBtn now
  consults overlay_pad_hidden alongside the picture -- whatever
  made the pixels stand down stands the hit areas down too, so a
  menu is pressable everywhere it appears.
- **L and R centre their letters by measurement**: drawInRect
  hangs a line from the top of its rect, never the middle -- the
  letters sat visibly low in their pills. sizeWithAttributes now
  places them on the button's own centre.
- **The face buttons paint at 0.66 of their hit radius** -- the
  thumb keeps the generous invisible box, the eye gets the modest
  circle it asked for, the glyphs scaled with them.

### Step 37 — the glyphs inside, no farewell, both sticks

- The face buttons paint at their own size again (Step 36's shrink
  went too far -- "the xyba are too small"); the glyphs inside are
  the small ones now: drawn at 1.05 r where the old proportions
  passed 1.55 -- a mark in its circle, not a badge on it.
- The intro hint's dismissal no longer says anything: the "That's
  it -- back to the game." strip is gone; the first touch just
  works and the game goes on.
- RECOMP_TOUCHPAD_RSTICK=1 in the pack: both stick pockets live by
  default (the menu's "Second stick" toggle still overrules it).
  The old rationale -- the game's icon bar lives where the pocket
  is -- mattered less once taps through pockets became true taps;
  the phone asked for both, and both it has.

### Step 38 — the bar itself, native (UIKit)

- The whole pull-down surface is the phone's own now: a 34-point
  strip (Game / Display / Controls tabs) that slides down from the
  top and back up, built the first time it's ever pulled. Each tab
  opens a rounded panel of UIKit rows driving the exact handles
  the ImGui menus drove (overlay.cpp's extern "C" set -- no new
  state was invented):
  - Game: Resume/Pause, All settings..., Volume (live slider),
    Frame rate 30/60 when the game offers it, Quit game.
  - Display: On-screen stats (Off/FPS/Full), Resolution 1x..3x.
  - Controls: the controls toggle, the second stick, Control size
    (60-160), See-through (10-90), Left-handed, Controls
    reference... (the full menu, which stays ImGui for now).
- The strip pulls only from its middle band (overlay.cpp's own
  gate, mirrored in the recognizer: |x - w/2| <= 140) -- L and R
  at the top corners never misstrigger it.
- While the strip is down the pad stands down entirely (pixels,
  touches, haptics), as the ImGui bar's bit always made it; a tap
  anywhere outside the panel (a shield view) closes both; the
  strip alone slides back up after 2.5 s idle.
- The ImGui bar and its pull tab never build while the native
  chrome is installed; RECOMP_NATIVE_CHROME=0 restores all of it.
- Manual memory kept honest: the panel's actions live in BN
  holders swept on each rebuild, and the sliders' blocks use
  __block pointers so they never retain the slider that targets
  them (no ARC here; what leaks at all, leaks nothing).

### Step 39 — the leftovers, native (UIKit)

- The last four ImGui surfaces on a phone are the phone's own:
  - the stats OSD (Off/FPS/Full) -- a monospaced label under the
    eye's corner, re-stringed from metrics_osd_lines by the tick;
  - the pause card -- PAUSED with the Resume hint, reading the same
    overlay_game_paused the banner did;
  - the intro strip -- the first-launch lesson at the bottom
    centre, taps falling through it, its twelve-second and
    first-touch rules now in the chrome's own tick
    (window_touch_contacts watched there, as the ImGui card had);
  - the settings center: the full menu's five pages (Display,
    Performance, Game, Controls, Help) as UIKit rows in a dimmed
    card -- switches, segmented controls, sliders, the game's own
    controls list, live FPS -- every one driving the same handles
    the ImGui pages drove (overlay.cpp's new extern "C" set:
    opt/capable/language/controls/gyro probes; no new state).
- Opening it goes through the same overlay_open/overlay_close as
  the ImGui menu (pause, input routing, audio, the pad's stand-down
  bits all as they were): the strip's "All settings..." and
  "Controls reference..." rows and the ImGui twins' own ways in all
  land on the same state machine.
- While the native chrome is installed: build_ui, the pause
  banner, the intro card and the OSD panel build never (overlay.cpp
  gates them); RECOMP_NATIVE_CHROME=0 restores all of it.
- Still ImGui on a phone: the save-data dialogs, the message/IME
  dialogs, and the rare prep/layout/quit cards -- game- or
  host-driven popups, the next round's work if wanted.

### Step 40 — the crash, the pill back

- test29's crash found in its log: panel_button called
  setBackgroundColor:forState:, which is not UIButton API -- the
  first row built by any menu's open died at once
  (NSInvalidArgumentException). The highlight is a stretchable
  tile now, its corners capped so the rounding survives the
  stretch; the bogus selector is gone.
- The pull's pill is back, native: a small handle at the top
  centre, tappable, bringing the strip down (the top edge's swipe
  is iOS's own -- notifications -- and a tap was the old tab's own
  way in). It stands down with the pad: while the strip is down,
  a menu is open, or the intro is up, it hides with the eye.

### Step 41 — the panel's top, the eye's glyph

- test30's panel opened at y -10, its header cut by the screen's
  edge ("the new menu is out of bounds"): bar_panel_rebuild set
  the panel's BOUNDS, and a bounds-set keeps the centre -- the
  origin slid up by half the size delta. The rebuild sizes by
  FRAME now, the origin captured first; the panel's top sits at
  the strip's bottom where it was drawn to be.
- The eye's glyph never drew: UIImage's SF Symbols don't render
  in this environment (the eye chip was the "circle thing that
  does absolutely nothing" of the earlier rounds, and test30's
  pill had no chevron in it -- both glyphs come from
  systemImageNamed). Nothing depends on them now: the eye is two
  arcs and a dot, the pill's chevron two lines, drawn by hand
  into images at install; the eye chip's hairline and fill
  stepped up too (40% border, 0.72 fill) so it is findable on a
  black scene as well as a bright one.

### Step 42 — the pill that never painted

- test30/31's pull pill showed nothing at all: measured against
  its background in the screenshot, the chip never darkened a
  pixel. Its background was set on the raw layer
  (layer.backgroundColor) -- the eye, which does paint, sets the
  view's own backgroundColor property; the pill now takes the
  eye's proven path (a view property, stronger fill 0.78, a
  48 x 18 chip, the hand-drawn chevron at 80%).
- The tick logs the chrome's own answers once, the first time it
  runs: the pill's and the eye's frames, hidden flags and
  in-window bits -- if the pill still refuses to paint, the next
  session's log says exactly which piece of that is true.

### Step 43 — actually native (the look, not just the plumbing)

- The settings center is a real iOS settings screen now: a
  UINavigationBar with the system Done button (amber tint), a real
  UISegmentedControl for the five pages, and a UITableView in the
  inset-grouped style (the Settings app's own) -- system cells,
  separators, selection highlight, semantic colors (label /
  secondaryLabel / grouped backgrounds). Rows are CfgRow models
  built per page; every row's block is still the same call the
  ImGui page made. Switches, sliders and segmented controls are
  the system's own, tinted amber.
- The chrome's cards wear the frosted material (UIVisualEffectView,
  SystemMaterialDark): the settings card, the menu strip, its
  panels, the pause card, the intro strip.
- The strip panels' radio dots became the system's own checkmark
  mark (drawn by hand -- SF Symbols never rendered here).

### Step 44 — test34 lifecycle, input and usability review

The missing eye was explained by installation before SDL's GPU claim: SDL
replaces its root UIView afterward and covers the early window children.
Install now uses SDL's exact UIWindow after that replacement, with one
pass-through chrome container above the game. Earlier symbol/background
changes did not fix this ordering.

The portrait-shaped surface visible in IMG_6209 is reconciled against the
actual landscape window at the UIView and CAMetalLayer level, before and
after event pumping, including while settings are open. Pad artwork rejects
mismatched dimensions instead of stretching them.

The full changes, findings, validation and device-test limit are recorded
in `docs/ios-ui-test34-review.md`. They include complete layout publication,
atomic pad input, stationary holds, cancellation, scrolling menus, corrected
action lifetimes, reusable settings cells, native settings state integration,
dialog ownership and small cached control images instead of full-screen
Retina repaints. Sanitized tests cover 96 layouts and 200,000 concurrent
input publications. This Windows host cannot verify real UIKit rendering.

### Step 45 — test35 lifecycle follow-up

The continued review found that test34's geometry repair could fight SDL's
deliberate keyboard displacement, and that SDL_SetWindowSize cannot repair
the cached logical size on iOS (UIKit_SetWindowSize is a no-op there).
Reconciliation now defers during text entry, transforms and presentations,
and asks UIKit for a fresh layout when only SDL's logical dimensions are stale.

Native choice sheets now close with their settings page and reject callbacks
for retired rows. Focus loss clears physical axes, virtual gestures, keyboard
state and queued mouse motion; all game input APIs suppress background input.
Foreground entry resamples the controller, and disconnect/focus loss resets
the Back/Start shortcut state. Details and verification limits are in
`docs/ios-ui-test35-followup.md`.

### Step 46 — test37 Metal HUD, compact gear and native host dialogs

Restored the optional Metal HUD with saved startup configuration and restart
guidance, and placed a gear beneath the eye. Those changes are isolated in
commit `1780cbb`, following the pre-change checkpoint `ca52ae8`.

Completed the iOS host UI migration: native save tables/questions, messages,
text entry, wait/progress cards, shader preparation, controller-layout choice,
quit confirmation and Core Animation touch markers. The normal native path
no longer initializes ImGui rendering backends or constructs ImGui frames.
Shared state and the explicit desktop/headless/legacy fallback remain.

Revision-checked answers, borrowed-data copying, dialog polling, text drafts,
UTF-16 limits and keyboard/controller routing were reviewed. Sanitized state,
lifecycle, touch-input and viewport tests passed, as did the 184-check system
dialog suite, iOS build, native Clang analysis and packaged IPA validation.
See `docs/ios-ui-test37-native.md` for details, artifact identity and the
remaining physical-device checks.

### Step 47 — the 2x measurement build, Metal HUD on by default

- The Metal HUD is on by default now: a fresh install shows Apple's
  own overlay unless a player turns it off (a saved choice always
  wins, and RECOMP_METAL_HUD still overrides everything; an
  externally supplied MTL_HUD_ENABLED is respected).
- This pack is the 2x-upscaling measurement round: RECOMP_GPU_FENCE_
  STATS=1 (a one-per-second GPU-busy summary in the session log:
  ms/frame busy, present latency, frames in flight) and
  RECOMP_FSR_RENDER=1 (FSR, when the Display page's anti-aliasing
  picks FSR 3.1, renders at 1x and upscales to the chosen
  resolution -- the sharp-at-less-cost candidate to measure
  against plain 2x). Both leave with the measurement; the fence
  stats are the "where does 15 fps go" question answered.

### Step 48 — MetalFX at present: the 1x frame upscaled by Apple's own scaler

- The 2x measurements said the cost is linear in pixels: 1x costs
  7.2 ms GPU busy, 2x 28.3 ms -- the whole frame at 4x pixels, so
  no shader trick inside the frame changes the bill. FSR rendered
  at 1x but its own passes plus the still-2x composite measured
  slower (16-18 fps). The one upscale that costs almost nothing
  extra is the one at present, on the final picture, once.
- Apple ships exactly that: MetalFX spatial upscaling (the
  iPhone's own silicon path, A15+). The game renders 960x544 and
  [MTLFXSpatialScaler](https://developer.apple.com/documentation/metalfx/mtlfxspatialscaler)
  turns it into the 2796x1290 drawable in one pass at present
  time -- expected back at (or near) the 1x frame cost, which the
  fence stats will now show.
- SDL's GPU API wraps its Metal objects opaquely, so the port's
  libSDL3.a is rebuilt from the SDL tree with three small exports
  added to its Metal backend (SDL_METAL_TextureHandle, _Device-
  Handle, _CommandBufferHandle -- /d/work/ios/SDL, not in this
  repo; the toolchain's libSDL3.a is that build). The scaler rides
  SDL's own command buffer, so ordering with the rest of the frame
  is the encoder's, not ours.
- runtime/gfx/gfx_metalfx.m creates the scaler per input/output
  size (rotation and render-scale changes rebuild it), feeds it
  the frame, and blits its output into the same letterbox rect the
  plain path uses. The formats needed no conversion: frames are
  RGBA8Unorm and the SDR swapchain BGRA8Unorm, both on the
  scaler's supported list; Perceptual colour mode, since those
  unorm bytes hold display-ready sRGB values. FXAA/sharpen are
  skipped when MetalFX runs -- the scaler sharpens on its own.
- RECOMP_METALFX=1 in this pack's RUN_ENV (the FSR render gate
  left with the measurement). Anything unsupported -- pre-16 iOS,
  no MetalFX, an odd source rect, framegen's already-full-size
  frames -- falls back to the plain present path without a word.
  Expected in the log: "metalfx: on (present-time spatial
  upscale)", then 960x544 -> 2796x1290 with the fence stats
  carrying the round's settings.

### Step 49 — the MetalFX toggle in the settings center

- Display -> Quality now opens with "MetalFX upscaling", a native
  switch: RECOMP_METALFX (the pack's RUN_ENV) is its default, a
  saved flip wins over it, and it takes effect the same frame --
  the scaler rebuilds itself whenever its input or output size
  changes, so there is nothing to restart. The plain present path
  is one frame away whenever it is off.

### Step 50 — touch look: the drag itself pans the camera

- The phone's own ask, Minecraft's own scheme: with touch look on
  there is no right joystick at all -- a drag anywhere on the screen
  (everywhere the buttons, the menu and the movement stick's pocket
  didn't take) pans the camera. The finger's speed is the turn, a
  finger at rest is no turn, and the thumb never runs out of reach
  the way a sprung stick's rim does. A quick tap stays the game's
  own touch exactly as before (the same hold/drag threshold that
  spawned the sticks decides), and a rear touch (RB held as the
  finger lands) never becomes a look.
- Underneath it is still the second stick's bytes the game reads:
  the drag's velocity (window points a second, lowpassed) feeds
  them, the per-loop tick ends the turn 60 ms after the last motion
  (event coalescing's gaps never stutter a slow drag), and the lift
  zeroes it. No ring, no knob -- the screen itself is the control.
- Controls gets "Touch look" (the pack's RECOMP_TOUCH_LOOK is its
  default, a saved flip wins, effect the same drag) and "Look
  sensitivity" (30-300%); off returns the floating sprung stick the
  "Second stick" toggle governs. The overlay's menus and the game's
  taps are untouched: the zone path refuses to run while any menu is
  open.

### Step 51 — test44 direct touch-camera displacement

Replaced the velocity-filtered right-stick emulation from test43 with direct
camera displacement through Uncharted's existing camera hooks. Look gestures
use a 3-point movement threshold, preserve the initial and final movement, and
have no smoothing timer or start haptic. A resting look finger retains ownership
without turning; a second finger cannot take over it. Movement, button, rear
touch and known swipe/twist-prompt routing remain separate.

Touch sensitivity is independent of mouse preferences. The production input and
camera hooks are exercised together under sanitizers, including matching turns
at 30/60 fps and 100,000 concurrent direct-look updates. The existing touch/pad
regressions and iOS build pass. See `docs/ios-touch-look-test44.md` for the cause,
behavior, validation and remaining device checks.

### Step 52 — test45 Uncharted defaults

Uncharted now defaults to experimental 60 fps and direct touch-camera input.
The optional second stick defaults off. Saved choices still apply, and the
frame-rate menu can switch between 30 and 60 during play.

`RECOMP_FRAME_RATE_DEFAULT` supplies the pack's fallback through one shared
settings getter used by the renderer and menu. It does not force the frame
rate like `RECOMP_FRAME_RATE`; unsupported games retain their 30 fps fallback.
Checks exercise the actual settings and display selection code under sanitizers
for the new default, saved/menu choices, unsupported games, explicit overrides,
forced capture rates and scheduled test changes. Pack configuration validation
also passes. Touch displacement and sensitivity are unchanged from test44;
the game's final 30/60 fps camera-response comparison still requires a device.

The arm64 iOS build and IPA validation passed, including the embedded defaults,
exact executable equality and HTTP download length. Artifact:
`NativUncharted-test45-unsigned.ipa`, 42,305,194 bytes; SHA-256
`3355d204b3faa0d8aa4925c1d23ce9123b6167b49a7ac2e71f71a4b95b271508`.
Check/build/package records are under `C:/ProgramData/t3/nativ-test45-*`.

### Step 53 — test46 iOS presentation and interaction passes

Replaced the custom quick-menu strip with a system menu. Native checked options,
submenus and destructive styling now manage quick actions. Added real Liquid
Glass on supported iOS versions with system-material and accessibility fallbacks.

Save slots now use selectable inset cards with concise metadata and an explicit
Save/Load/Delete action. Dialog cards adapt to content, keyboard space and larger
text; compact text entry puts Done in the navigation bar. Transitions retain a
stable surface while save steps advance, and callbacks preserve revision checks.

Settings now opens a category list with Back/Done navigation and actual grouped
sections. Long choices open a native navigation sheet with checkmarks rather
than an alert action sheet. The final review includes stale callbacks, scroll
stability, reduced motion/transparency, text composition and safe dismissal.

The iOS build, full native Clang analysis, sanitized overlay/input suites and
184-check dialog API suite pass. Device access is disabled here, so visual and
interaction approval still needs a phone. See `docs/ios-ui-test46-polish.md`.
These UI passes are committed locally and have not been pushed to GitHub.

### Step 54 — test47 chapter-menu gestures and dialog fixes

Uncharted now gates floating sticks and touch look on eligible gameplay updates,
so chapter/difficulty screens keep their original touch gestures. Sensitivity
defaults to 400% with a 30–1000% slider; saved choices still apply. The gear uses
an explicit tap target and native navigation popover. Floating chrome uses
neutral tint, and notifications are darker with no blue accent stripe.

Save questions and simple confirmations use system alerts. Save selection has
one compact grouped list with one available new slot, reduced spacing and
original backend row indices preserved. See `docs/ios-ui-test47-fixes.md`.

Regenerated guest code includes the gameplay hook. The iOS build, Clang analysis,
sanitized touch/camera and native-overlay suites, 184 dialog API checks, pack
validation and secret scan pass. IPA checks confirm fresh code, arm64/plist/ZIP
integrity, exact executable equality and HTTP length. Final appearance and
chapter-menu/gameplay transitions still require phone testing.

Artifact: `NativUncharted-test47-unsigned.ipa`, 42,313,273 bytes; SHA-256
`e55fccb3313d5287b39bbb8323f7ba32363f3085b29d3b96c850decb935c2bd6`.
Changes remain local and have not been pushed to GitHub.

### Step 55 — test48 one Settings menu

Removed the separate Quick Controls controller and its duplicate setting
actions. The gear opens Settings directly; its home list includes Resume Game
and Quit Game alongside the existing categories. Native iOS still has no top
bar or top-edge menu trigger. Keyboard/controller entry uses the same Settings
surface. See `docs/ios-ui-test48-single-settings.md`.

The iOS build, native Clang analysis, native-overlay regressions and IPA checks
pass. Validation checks the removed controller is absent from the linked binary,
the UI object is fresh, ZIP/plist/arm64 are valid, the packaged executable matches
the build, and the download responds with the correct HTTP length. Phone testing
is still needed for presentation and interactions.

Artifact: `NativUncharted-test48-unsigned.ipa`, 42,305,469 bytes; SHA-256
`33aecff7811f8579bc4d34eb7ecf49a3753edf846f7863c14ee08c927e4dd952`.
Committed locally; no GitHub push.

### Step 56 — test49 shader preparation before play

Fixed shader recipe loading from Windows-built packages: CRLF headers and record
text are normalized before version/hash validation. The actual Uncharted recipe
file now loads 417 shader recipes and 413 pipeline recipes instead of being
rejected. Added production-code regression coverage for line endings, record
integrity and merged files.

iOS defaults to Before Play preparation, covering indexing, known recipes and
the additional prediction pass. Skip restores background worker limits at any
stage. Performance settings offers Background, Automatic and Before Play;
saved choices still apply. First-install controls guidance appears afterward.
Desktop defaults remain unchanged. Existing Metal cache reuse remains active;
unseen combinations can still require compilation during play.

The iOS build, shader/overlay/input sanitizer suites and upgrade package checks
pass. The Clang report has three reviewed diagnostics in unchanged renderer draw
paths and none in the loader/preparation changes. See
`docs/ios-shader-preparation-test49.md` for behavior and device verification limits.

Upgrade: `NativUncharted-test49-unsigned.ipa`, 42,307,267 bytes; SHA-256
`0e38101e7983604ff98c5c687e238d4553b8e5d9b37047421a18bf158f92c4a5`.
The earlier UI changes were pushed through `a8b9458`; shader changes are local.

### Step 51 — two-thumb shooting: tap L to toggle aim, drag R to look while firing

- Three fingers were the price of hold-L, look and fire at once. The
  native buttons now do it with two: a short L tap (under 250 ms,
  barely moved) toggles an aim hold on top of its normal momentary
  press -- a second tap releases it -- and while that toggle is on,
  dragging R steers the camera on the same displacement path touch
  look uses, so firing and looking happen with one thumb on the
  button. Lifting R stops firing and keeps the aim; everything long
  or dragging on L stays the original momentary shoulder.
- RECOMP_TOUCH_SHOOT=1 gates it to this pack, and only over the
  native buttons with touch look on and Two-thumb shooting enabled;
  physical pads, keyboard, mouse and the SDL-screen buttons are
  untouched, and recognized puzzle prompts, menus, focus loss,
  layout changes and hidden controls clear the synthetic state --
  the suite covers each. Controls carries the toggle back to the
  original behavior.
