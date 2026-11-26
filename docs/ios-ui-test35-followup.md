# iOS lifecycle follow-up — test35

This continues the [test34 UI/input review](ios-ui-test34-review.md). It fixes
additional lifecycle defects in that implementation and the surrounding input
path. These are code and host-test results, not physical-device verification.

Artifact: `NativUncharted-test35-unsigned.ipa`, 42,290,163 bytes.
SHA-256: `e5dd96c3ce412051304bac4454444cb639e71b3619e7fe0d4191defacecce159`.
ZIP integrity and the packaged arm64 executable match the final build. The
download returned HTTP 200 with the matching Content-Length.

## Findings and changes

1. **Keyboard positioning could be undone.** SDL's UIKit controller deliberately
   shifts its view upward to reveal the active text field. The test34 geometry
   repair treated that offset as corruption. Repair now defers during text entry,
   native presentations, transitions and non-identity view transforms.
2. **Changing SDL's requested size cannot repair its iOS logical-size cache.**
   `UIKit_SetWindowSize` is intentionally empty outside visionOS. A mismatch
   confined to SDL's logical dimensions can persist even when the UIView and
   drawable are correct. The repair now requests a fresh UIKit layout; SDL's own
   `viewDidLayoutSubviews` publishes the actual size. It handles frame, drawable
   and logical-size mismatches independently.
3. **A native choice sheet could outlive settings.** Closing settings with a
   controller/keyboard did not dismiss a presented language picker. The picker
   now has explicit ownership, dismisses on settings close/page rebuild, and
   rejects callbacks for retired rows. Choice, cancel and interactive dismissal
   release its retained owner without a sheet/action retain cycle.
4. **Focus loss did not release every input source.** The earlier screen-pad
   cancellation left physical stick axes, virtual flick/twist gestures and mouse
   motion behind. One reset now releases all of them. While unfocused, the game
   receives neutral buttons, axes, screen contacts and raw mouse motion. The
   PS TV mapping cannot reintroduce shoulder bits after that suppression.
5. **Controller shortcut state could remain held.** Back/Start combination state
   resets on focus loss and controller removal. Foreground entry resamples current
   controller axes and shoulder state.

## Verification

- `dev/tests/touchpad_test.py` compiles the production pad, input, contact,
  mouse-delta and cancellation functions with deterministic host adapters.
  AddressSanitizer and UndefinedBehaviorSanitizer pass, including the prior 96
  layout combinations and 200,000 cross-thread input publications.
- Added assertions for background input suppression, PS TV mapping, physical
  axes/keys, flick/twist release, raw mouse clearing and normal foreground input.
- `dev/tests/ios_viewport_test.c` runs the actual reconciliation decision code
  for a healthy surface, portrait frame/drawable, logical-only and drawable-only
  damage, intentional keyboard displacement, deferred transitions and 2x/3x
  screen scales. AddressSanitizer and UndefinedBehaviorSanitizer pass.
- The arm64 iOS build, complete native-chrome/window Clang analysis and final IPA
  checks are recorded in `C:/ProgramData/t3/nativ-test35-*.log` and the validation
  JSON beside them. Analysis emits only an unused linker-option notice.

## Remaining verification

No iPhone or Apple Mobile Device was connected to this host when checked. There
is no local iOS simulator. The eye, actual UIKit layout, app-switcher returns,
keyboard entry and picker dismissal still need to be exercised on an iPhone.
Passing the host tests does not establish that every visual/device defect is gone.
