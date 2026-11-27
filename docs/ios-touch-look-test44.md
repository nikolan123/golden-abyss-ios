# Direct touch camera — test44

Test43 converted smoothed finger velocity into an 8-bit right stick. Uncharted's
look-message path reduces that stick to direction, so this could not preserve
finger distance. The 12-point/160 ms gesture gate, discarded initial movement,
velocity filtering and 60 ms stop timer added delay and overrun.

Test44 sends displacement through the existing Uncharted camera-velocity hook.
The UI accumulates a single atomic x/y pair; the game consumes it once, in
radians. At 100% sensitivity, a swipe across the screen width turns 180 degrees.
Both axes use the same point scale. Mouse sensitivity, inversion, capture and
raw-look settings do not affect touch.

Camera drags claim after 3 points of movement, retaining that initial distance.
A stationary hold remains a game touch. There is no velocity filter, timed
continuation or activation haptic. Ordinary release preserves unsampled final
movement; cancellation, menu entry, geometry changes and focus loss discard it.
Ownership remains with one look finger even after its pending motion is consumed.

The movement stick and buttons keep their input paths. Rear contacts and known
swipe/twist prompts stay with the game. Touch look can be disabled for puzzles
that need unrestricted screen drawing; the floating right-stick option then
applies. Only packs declaring a direct-look consumer expose this mode, so a
global saved preference cannot take screen gestures from unsupported games.

The supplied device log includes periods around 30 fps and periods around 60 fps;
it has no per-finger motion trace. Frame cadence still limits visible response.
This change addresses the confirmed input transformation rather than inferring
touch latency from GPU fence timings.

Validation:

- The production touch-input code and Uncharted hooks compile together with
  AddressSanitizer/UndefinedBehaviorSanitizer and warnings treated as errors.
  Tests cover initial/subsequent/final movement, slow reversal, stationary input,
  sparse/coalesced events, equal total turns at 30/60 fps, sensitivity, exclusive
  finger ownership, simultaneous movement/buttons, cancellation, focus loss,
  prompted gestures, unsupported packs and the legacy-stick fallback.
- The same suite verifies yaw/pitch writes by the actual game hooks, unchanged
  desktop mouse scaling/inversion, delayed camera consumption and stale-input
  expiry. Concurrent tests preserve 100,000 direct-look x/y updates and the
  existing 200,000 pad snapshots. The prior 96 layout cases still pass.
- The iOS build passed. Native chrome, window input and Uncharted hooks were
  checked with Clang static analysis. IPA validation checks ZIP integrity,
  arm64 Mach-O, plist, source freshness and exact executable equality.

No iPhone or iOS simulator was available for interactive verification. The final
feel, direction and sensitivity still need a phone test; begin at 100% Look
sensitivity when comparing against test43. The new package retains the existing
game-data setup.

Artifact: `NativUncharted-test44-unsigned.ipa`, 42,305,110 bytes.
SHA-256: `81df7a3411043c62e5ecfd83cd9566be04dee310ae3afb2bc3996f7b964a0ec6`.
ZIP/executable validation passed; the download returned HTTP 200 with the
matching Content-Length. Build, analysis, packaging and validation records are
under `C:/ProgramData/t3/nativ-test44-*`.
