# iOS test50: toggle aim and drag on the fire button

Holding L, moving the camera and pressing R required three fingers on the
on-screen controls. Uncharted's native touch buttons now support a short L tap
to toggle aiming and dragging on R while firing to adjust the camera.

L is pressed normally on contact. Releasing within 250 ms, without moving more
than 10 points, toggles the additional aim hold. Longer holds or drags keep
momentary L behavior. A second tap releases the toggle. R retains its normal
trigger behavior; its camera drag starts only while this native aim toggle is
active. Lifting R stops firing but leaves the aim toggle on. Turning the aim
toggle off while R is held ends camera dragging and keeps R as an ordinary
held button until release.

The R drag uses the existing screen-width/sensitivity displacement path and
camera hooks. Its three-point movement threshold includes the first movement,
and the final lift contributes its last displacement once. A separate camera
finger keeps ownership if it was already looking; R can still fire, but does
not take over that finger's camera. UIKit uses absolute host-view coordinates,
coalesced samples and one tracked touch identity per button. Late callbacks
cannot release a newer touch.

## Scope and cancellation

`RECOMP_TOUCH_SHOOT=1` enables this capability only for the Uncharted pack.
The assistance is limited to native iOS buttons with Touch Look and Two-thumb
shooting enabled, recent eligible gameplay updates, a focused app and no open
menu/dialog. Recognized gesture/twist puzzles and physical touch-cursor/rear
modifiers suspend it. No controller bindings, firing cadence, weapon behavior,
movement sensitivity or game targeting logic are changed.

Loss of eligibility, touch-puzzle prompts, settings changes, focus loss, hidden
controls and geometry changes clear the synthetic aim/fire-look state. Ordinary
face-button contributions are preserved by this cleanup; the existing global
input-cancellation paths still release all input when required. The user can
disable Two-thumb shooting under Controls to restore the original L/R behavior.
The toggle's pressed state is reflected by the L artwork and accessibility value.

The new mapping does not change how SDL screen buttons, physical controllers,
keyboard or mouse bindings work. Published hardware inputs remain independent
of the synthetic native aim hold.

## Verification limits

The production-code sanitizer suite covers normal holds/taps, R displacement and
final lift, ordinary R without aim toggle, exclusive camera ownership, late
callbacks, cancellation, aim-off while firing, physical input contribution,
mirroring, hidden controls, option changes, gameplay expiry and puzzle/menu/focus
transitions. Existing layout, input publication and direct-camera regressions
remain in the same suite.

Interactive phone access is disabled here. Source/host tests cannot establish
that every game section signals its touch-puzzle state. Device review should
include combat, climbing, scripted sequences, the touch puzzles, app switching,
menu return and changing between touch and a physical controller. The setting
provides a way back to the original controls for any unrecognized interaction.
