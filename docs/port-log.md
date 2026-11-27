
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

### Step 52 — the phone's own gyroscope is the Vita's motion sensor

- Tilt sections (the balance beams, the river slide) had nothing to
  read on the phone: the sensor path took a gamepad's samples, and
  with no pad the sections fell back to the left stick. The phone
  has the same two sensors the Vita has, so iOS now feeds them:
  CoreMotion's accelerometer and gyroscope at 60 Hz, rotated from
  the device's portrait frame into the game screen's landscape
  frame (whichever way round it is being held -- the chrome's
  window sync hands the interface orientation over), into the
  same motion.c filter a gyro pad's samples ride. A phone held in
  landscape IS the device, so neither "upright/flat" pose applies
  -- motion.c gained a native source that passes the samples
  through as the Vita's own frame. The accelerometers' opposite
  sign conventions (CoreMotion's gravity vector against SDL's
  specific force) are converted on the way in.
- The phone counts exactly like a gyro pad everywhere: the Motion
  section of the settings center (its Gyro toggle, sensitivity,
  Recentre), the balance/slide toasts ("Tilt the phone"), the
  left-stick fallback stood down, and the source chooser. A gyro
  pad connected by hand takes the source back (the phone stands
  down, its native flag with it -- the pad's pose applies again)
  and returns it on disconnect. The regression suite gains the
  tilt gate: a gyro source, whichever it is, keeps the left stick
  the game's in a tilt section.

### Step 53 — the tilt's direction, corrected on the device's word

- The first CoreMotion build read the tilt mirrored: a 180-degree
  error about the screen's axis, the interface-orientation table
  written to the doc's names instead of the home button's side
  (UIInterfaceOrientationLandscapeLeft is home on the RIGHT; the
  device's own orientation names are each other's inverses). The
  two rows swap, and both the accelerometer and the gyroscope
  rotate consistently again.

### Step 54 — R drags with L held, and the system's edge gestures defer to the game

- Two-thumb shooting's R drag now arms on any aim input: the latched
  toggle or a thumb simply holding L. The latch stays as the one-thumb
  convenience it was; the two-thumb hold-L-and-drag-R play needs no
  ceremony. The suite covers the held case (a 300 ms hold, past the
  tap window) and the unarmed one (nothing held: R stays a trigger).
- The system can no longer take the game away with one swipe: the
  root view controller now reports the game's preference -- the home
  bar hides, and every edge gesture (home, notification, control
  centre) defers: a first swipe only peeks, a second, deliberate one
  acts. A runtime subclass of SDL's own controller carries the two
  overrides; the settings menus keep normal gestures (the system
  asks the presented controller, not the root, while they are up).
- The game's own Auto Aim option (Options -> Aiming, difficulty-gated
  in its frontend) does nothing on the touch camera path. The two
  candidates: the engine ignores the flag where our hooks bypass it,
  or the assist rides the camera's "set look velocity" -- the exact
  call uc_look_velocity replaces with touch radians, wiping the
  assist with it. A stick-aim experiment on the device (the floating
  second stick, auto-aim on) separates them; an additive-look mode
  is the fix if the assist rides the velocity, and a deeper engine
  trace is next if it does not.

### Step 55 — held R re-taps for semi-auto weapons; the bottom edge asks twice

- The pistol fired once on a held R because the game is right: one
  shot a trigger press, as the Vita's own trigger. The two-thumb
  fire finger now re-taps it -- a 20 ms release every 125 ms, about
  eight a second -- so a held thumb fires semi-auto weapons at a
  hand's pace and automatic ones never notice a frame's gap. The
  button's art stays pressed; only the game's bit pulses. The suite
  covers the release and the re-press on the tick.
- The home bar stays visible now, on purpose: with the indicator
  hidden, the bottom edge's deferral had no bar to reveal on its
  first swipe and the system often took the exit straight away --
  the one-swipe-away the top edge had already lost. Visible bar,
  all edges deferred: the first swipe peeks, the second acts.
- The asked-for strong snap (always on the nearest live enemy while
  aiming) is the next dig: it needs the enemy actor list out of the
  game's memory -- a live-traced round, the game's own faint assist
  confirmed present but too weak to feel.

### Step 56 — the magnetism round opens with the assist's ground truth

- The strong snap (always on the nearest live enemy while aiming)
- needs the game's own aim assist understood first: its toggle
  exists (Options -> Aiming), its effect is present but too faint
  to feel, and no Lua knob exposes its strength -- it is pure
  engine code. The camera's "set look velocity" (uc_look_velocity's
  own call site) is where an assist would leave its mark, and the
  touch path replaces that velocity -- so the hook now logs the
  game's own value before the replacement (RECOMP_UC_AIM_TRACE,
  throttled to a twentieth of the frames).
- One firefight with the game's Auto Aim on, one with it off, and
  the difference between the two logs is the assist's own
  contribution -- the thing to amplify, or the proof that a
  host-side magnet (the enemy actor list, live-traced) is the
  only way to effortless.

### Step 57 — the aim magnet, and the melee QTE's swipes back

- The trace answered the assist question: with the game's Auto Aim
  on, its pull reaches ~0.01 rad/frame toward its chosen target
  (visible with the touch finger at rest); off, the camera's own
  value collapses to the nudge's ~0.002 residue. The assist is
  real, proportional, and feeble.
- The magnet amplifies it: the camera hook keeps the game's own
  velocity where it used to replace it -- the touch deltas stay
  exact, the assist's component (the game's value minus the
  nudge's residue along the drag) scales by the strength and adds.
  Lowpassed, so a pull flipping sign at the target's centre eases
  over it rather than jittering, and clamped. The game's own
  targeting logic picks the enemy; the magnet only makes its pull
  felt. Controls -> "Aim magnet" (0-10, the pack's default 5);
  zero restores the plain camera exactly.
- The melee QTE's up/down swipes were eaten by touch look: the
  gesture-hint machinery existed but nothing in this pack fed
  it, and unlike the puzzles the melee finishers keep the player
  controller live. uc_gesture_update now tells the input layer a
  gesture is listening -- the look stands down for its window and
  the drag reaches the game's own recognizer (the machete and
  rubbing prompts take the same road, now by signal as well as by
  the puzzle state).

### Step 58 — the magnet stood down; the lock-on's raw material, captured

- The magnet rode the game's own assist, and that ceiling is the
  problem: the assist picks its target only inside its own cone and
  pulls proportionally -- amplified it aims near enemies but never
  locks, and outside the cone it does nothing. Uncharted 4-style
  magnetism needs the target list itself, hard-snapped and tracked
  while visible. The pack's RECOMP_AIM_MAGNET goes to 0 by default;
  the slider stays for whoever wants the soft pull back.
- The lock-on's data source is the renderer's own frame list: the
  game must enumerate every visible actor to draw it, and the
  port already enlarged those pools -- the list (+0xeb0), the
  64-byte items, the frame's count (+0xeac) are addresses the
  renderer hooks already know. RECOMP_UC_LOCK_TRACE (this pack,
  once a second) dumps a tenth of a frame's items -- a frame
  aiming at an enemy against one looking at scenery tells the
  actor-link word from the transform floats -- plus the player
  controller's registers (the anchor for reaching the actor list
  next round) and the camera field diff (RECOMP_YAW_DIAG) for the
  camera's world position and orientation.

### Step 59 — the capture round that fixes the position: the actor's own object, its render packet and the camera's raw block

- Step 58's capture settled identity and visibility: an item's words
  2/3 are -1 exactly for moving actors, and word 10 is one owner
  pointer shared by every mesh part of one actor -- enemies appear
  as groups of items owning 0x12b7eb90/0x12ce2e30/0x12c8d270 while
  the player's parts own the controller+0x1d0, so the player excludes
  by the gameplay hook's own controller address. The PVS work already
  knew the instances keep a bounding sphere at +0x60, so the position
  is one hop away: in the item's owner object, its render packet
  (word 4) or the words past 10 that the first round never dumped.
- The trace (RECOMP_UC_LOCK_TRACE, once a second) now dumps all
  sixteen words of each sampled item, and for every dynamic actor
  also 128 bytes at its owner and 64 at its packet; the active
  camera's first 0x200 bytes ride along raw (the field-diff diag
  never showed anything -- the two camera objects alternate, so
  every second's comparison was against a different base), and the
  header marks the aim latch, so the seconds spent aiming stand out
  in the log. One fight played against this build gives the enemy
  positions, the camera's own position and basis, and the frames they
  were aimed in.

### Step 60 — the lock itself: what is drawn is what is visible, and the nearest chest takes the camera

- Step 59's capture settled the last two unknowns. The
  actor's owner object carries four world-space points on
  the body (words 12/16/20/24, ~1.5 m apart, moving with
  the actor; the highest rides where a head would), and the
  camera object holds its full 4x4 world matrix at +0x40 --
  rows right, up and the view's opposite, the translation
  at +0x70 the position itself: measured against the same
  seconds' actors, the camera sits 2.7-2.9 m from the
  player's chest every gameplay frame, and the game's own
  scripted turns write up to 1.35 rad/frame, so a hard
  snap's rate is nothing the solver has not seen.
- The lock, then: the render reset (which already walks
  the frame's item list) tabulates every moving actor --
  words 2/3 = -1, one owner per actor, the player excluded
  by the gameplay hook's controller pointer (and by the
  3 m the camera keeps from him) -- as the mean of the
  owner's four points, the chest. The camera hook, when a
  thumb holds aim (L held or latched) and "Snap aim" is
  on (Controls; the pack's RECOMP_UC_SNAP its default),
  turns the camera's own basis on each chest into an exact
  yaw/pitch error and writes it as the frame's look
  velocity: a hard pull (clamped at 0.45 rad/frame, about
  a quarter turn a second at the clamp) that becomes
  tracking once the crosshair is on the chest, with a
  deadband so a locked target sits still and the touch's
  own deltas still composing on top, so a drag can break
  out. The chosen actor keeps the lock while it stays
  visible within half again of the best bearing; a dead
  one leaves the render list and the lock moves to the
  next nearest. Letting go of aim releases it.
- The camera matrix's rows are strided words of a 4x4
  (right/up/back at words 0-2, 4-6, 8-10) -- the first
  cut read them contiguously and the test's zero w-column
  caught it before a device ever did. Tests cover the
  dead-ahead stillness, the clamped pull, the handover
  inside hysteresis, the player's 3 m exclusion, the
  behind-the-lens skip, the release and the env
  kill-switch.

### Step 61 — the lock's first device round: the wobble read out of the log, three ways

- The first test59 fight log showed the lock writing to the
  camera's velocity in alternating signs, frame after frame,
  at a steady amplitude -- a ring that never settles. Three
  causes, all read from the same log:
- The store site runs for several camera objects a frame
  (0x1147e4f0 with 0x11475730/0x11474e80 in the same
  seconds), and the lock's held-actor memory was one static
  shared by all of them -- each camera's call overwrote the
  chosen target, so the hysteresis could never hold and the
  nearest-bearing pick ping-ponged. The held actor is now
  kept per camera, and a camera whose +0x40 does not hold an
  orthonormal matrix (norms near one, rows mutually
  perpendicular) gets no lock writes at all -- the basis
  the error is computed from has to be a real camera.
- The target table filled its 24 slots in a six-man fight:
  the words-2/3 = -1 flag marks every moving thing drawn,
  tarps and debris and riders included, and their jittering
  "chests" were what the wobble chased. An owner is now
  taken only when it is built like a body: word 5 exactly
  1.0 and words 0/2 a unit pair (the yaw rotation every
  traced actor carries), at least two mesh parts of it in
  the list, and its four points clustered within 0.25-3 m
  of their mean.
- The ring's signature -- a steady amplitude at full-error
  writes -- says the velocity lands on the camera twice a
  frame, so the full error overshoots into a self-sustaining
  wobble. The lock now writes half the error: what lands
  twice closes exactly, and the clamp still caps a hard
  snap at 0.45 rad/frame of written velocity. The trace's
  own line now names the camera and the target's world
  point, so the next capture says what it aimed at, not
  just which index won.

### Step 62 — the playtest's own save rides in the ipa

- Every device round began with the whole intro, because a
  fresh install's Documents holds no fs/savedata0 and the
  game starts from nothing. The pack can now carry a save:
  packs/PCSA00029/savedata/ (the playtest's own six files,
  plus a blank .slot1 marker, 0x34c zeroed bytes -- the
  port's own history is that a blank param lists fine and
  the game dates the slot by its file) is bundled by
  pack-ios.py into data/savedata0, and the iOS bootstrap
  copies it into Documents/Nativ/fs/savedata0 on first
  boot -- only while that folder holds no checkpoint.bin
  of its own, so a save the game has already written is
  never overwritten by an update. The dotfile marker is
  copied with the rest (a skip-the-dotfiles copy would
  have silently dropped the one file that makes the slot
  exist).

### Step 63 — one camera: the lock steers only the one the game looks through

- The second device round read clean in the lock's own
  numbers -- 1-4 targets of body shape (the junk filter
  holds), chest-height points, errors that converge, and
  the locked targets sitting dead ahead of the steered
  camera's basis -- but the same log shows the writes
  going to two cameras at once during one aim: the aim
  view 0x11474e80 and the gameplay 0x1147e4f0, each with
  its own nearest enemy (a -0.368 pull on the gameplay
  camera mid-aim). Whatever the blend does with a camera
  yanked somewhere random, the player sees it -- the
  "keeps moving toward a random axis" of both rounds.
- The fix is the manager's own answer: the chain the diag
  has always read (DAT_81905310, mgr+0x60, then
  **(mgr+0x5c)+8) censors out to exactly the camera in
  use -- 0x11474e80 during aim, 0x1147e4f0 in gameplay,
  cinematic rigs in cutscenes (both rounds' captures
  agree). The lock now writes only when the store's camera
  is that one; every other object the store runs for is
  left alone.
- The shipped save worked -- the restore line is in the
  round's own log -- it was just the first upload's older
  checkpoint; the pack now carries the newer files the
  playtest sent.

### Step 64 — the channel the aim camera actually listens to, and the slot param made visible

- The third capture measured the aim camera's response
  directly: full-rate velocity writes (-0.13 rad/frame, 7.5
  degrees a frame) moved its basis eleven degrees in a
  second. The aim camera -- the zoomed one, fov 0.47
  against the gameplay 0.96 -- damps the +0x160 channel
  forty-fold. That was the whole story of "hold L: nothing
  happens": the lock's writes were absorbed, while the
  spare cameras the store also runs for (where +0x160 does
  integrate) were yanked toward their own targets and
  handed the randomness back on the blend; the visible
  slow drift was the aim camera's damped crawl.
- The lock now rides the one channel verified to steer the
  aim view: the pad's look stick, the same deflection a
  thumb's drag writes (the two-thumb shooting round proved
  it turns while aiming). uc_mouse_look's rest branch (no
  touch deltas this frame) deflection-nudges the stick
  toward the nearest visible enemy's chest -- full stick
  while the bearing is past a 0.06 rad deadband (the game
  turns ~0.075 rad a frame at full deflection, so the band
  is one frame's turn wide), nothing within it. The
  camera is the manager's active one and only when its fov
  says aim (0.2-0.75: the chain flickers to the gameplay
  camera mid-aim, and that basis must not steer). A drag
  still owns the stick while deltas flow; the lock takes
  it back whenever the finger rests. The +0x160 lock is
  gone entirely; the touch path and the magnet keep theirs.
- The shipped save restored again (the line is in the log)
  and the game still ignored it -- the blank slot param is
  the suspect. The shipped .slot1 now carries a real one
  (status: exists, the game's own title, its size, a
  stamped time), and if the game wants more than that, the
  bootstrap now also copies fs/savedata0/.slot1 out to
  Documents/Nativ/slot1-param.bin at every boot: the game
  writes the real param itself once it saves, and the
  Files app can finally see it. One round with that file
  attached ends the guessing.

### Step 65 — the snap aim stands down

- The lock-on tried three channels across four device
  rounds -- the camera's look velocity, the same gated to
  the manager's active camera, and finally the pad's look
  stick -- and none of them held up on the device: the aim
  camera damps the velocity channel forty-fold, the store
  site runs for cameras the player is not looking through,
  and the stick path arrived too late to be proven before
  patience with the feature ran out. The call: not worth
  more rounds. Everything aim-assist is gone: the snap
  aim and its toggle, the magnet and its slider, the
  target table, the capture traces (RECOMP_UC_LOCK_TRACE,
  the aim and yaw diag env flags in the pack), the
  touchpad's aim-held query, and their tests.
- The shipped save goes with it: the bundling, the
  first-boot restore, the slot-param export, and the
  playtest's own save files out of the pack (and out of
  the repository's history -- a public fork is no place
  for them). Every other gain stays: the MetalFX upscale,
  the touch look and two-thumb shooting, the melee QTE's
  swipes, tilt via CoreMotion, the gesture deferral, the
  view-distance pools, and the rest of the controls.
