
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
