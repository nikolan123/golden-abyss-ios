# iOS test47: menu gestures and dialog spacing

The chapter/difficulty menu needs the game's original screen gestures. Touch
look and floating movement sticks previously claimed drags there as if the
player were in gameplay. Uncharted now enables those controls only while its
eligible player-controller update is running. A pack-specific instruction hook
at `0x810ee988`, after the controller's object and eligibility checks, refreshes
a 100 ms heartbeat. Without that heartbeat, screen gestures pass through and
stale stick/look ownership is cleared. Face and shoulder buttons remain usable
for menu navigation. Other packs retain their existing behavior.

Look sensitivity defaults to 400% when no preference is saved. Its slider spans
30–1000%, and the runtime applies the same bounds. Existing preferences remain
in effect. Direct camera displacement is still independent of frame rate.

The gear now has an explicit tap action opening a UIKit navigation popover;
its activation no longer depends on automatic context-menu recognition inside
SDL. Submenus use navigation, and settings/quit actions wait for dismissal.
Metal HUD remains available under Display. The floating eye/gear use white
tint, and the eye's state is conveyed through accessibility without selecting
a blue Glass fill. Notifications have no accent stripe and use a darker surface.

Save questions, quit confirmation and button-only messages now use system
alerts. Save selection uses one compact inset-grouped list, with no reserved
subtitle space when absent, no repeated section gaps and a narrower card.
Saving shows existing saves plus one available new slot. Loading/deleting shows
existing saves. Visible selections map back to the original backend row index;
slot identities are not renumbered. Controller navigation and confirmation
use that same mapping. Native alert callbacks retain dialog revision checks,
and external answers or game closure dismiss the alert.

## Verification

The sanitized production touch/camera suite passes, including 96 layout cases,
200,000 pad publications, 100,000 direct-look publications, sensitivity bounds,
main-menu gesture routing and gameplay-heartbeat expiry. Native overlay state
and lifecycle regressions pass, as do the 184 message/text-dialog API checks
and pack configuration validation.

Packaging checks require the generated gameplay-hook call and its fresh game
object, as well as fresh native UI sources, the embedded gameplay gate and
60 fps/direct-look defaults, arm64 Mach-O, plist, ZIP integrity and exact
executable equality. A runtime-only build alone does not regenerate pack hooks;
test47 explicitly regenerates the guest code before compiling it.

Device access is disabled and no iOS simulator is available here. Phone checks
remain necessary for chapter/difficulty swipes, resumed gameplay look/movement,
gear taps and submenus, save selection/confirmation, and the final appearance
with normal/large text and accessibility material settings. The heartbeat's
timing should also be checked during slow frames and gameplay/menu transitions.

These changes are committed locally. They have not been pushed to GitHub.

The regenerated arm64 iOS build, Clang analysis and IPA checks passed. The
download endpoint returns HTTP 200 with the expected length. Artifact:
`NativUncharted-test47-unsigned.ipa`, 42,313,273 bytes; SHA-256
`e55fccb3313d5287b39bbb8323f7ba32363f3085b29d3b96c850decb935c2bd6`.
Build, analysis, packaging and validation records are under
`C:/ProgramData/t3/nativ-test47-*`. The local-commit secret scan found no leaks.
