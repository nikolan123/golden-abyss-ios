
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
