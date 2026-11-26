# iOS UI and input review — test34

Artifact: `NativUncharted-test34-unsigned.ipa`, 42,288,739 bytes.
SHA-256: `bca403418a2c56bbc210b3039aa9fb44d1df2c3029c890f00b29920ebae5aebe`.
The download endpoint returned HTTP 200 with the matching Content-Length.

Reviewed the iOS chrome, SDL UIKit/Metal view lifecycle, window/presentation loop,
touchpad layout and input, settings page bindings and persistence, overlay/dialog
integration, and IPA packaging. This is a review of that complete path, not a claim
that every game, graphics shader, network protocol or recompiler function was audited.

## Screenshot failures

The missing eye is explained by installation order. `window_run` installed UIKit
chrome before `SDL_ClaimWindowForGPUDevice`. SDL's `setSDLWindow:` then removes the
old root view and installs its Metal view above those window children. Replacing
SF Symbols and changing background colors did not address that ordering.

Install now uses SDL's exact native UIWindow after the GPU claim. One transparent,
pass-through chrome container stays above the game. It yields to presented native
sheets. The eye and a labelled Menu handle remain reachable with the pad switched off.

The second screenshot is consistent with a 430 × 932 point portrait surface being
used in the 932 × 430 landscape window. A fitted 960:544 image in that portrait
surface is 430 points wide and starts near y=344, which matches the image cut off
at the lower left. Portrait layout math also produces the tall, narrow shoulders
shown there. This diagnosis is based on source and screenshot geometry; a new
device log was not supplied for that screenshot.

The new reconciliation checks the actual game UIView and CAMetalLayer drawable,
not only SDL's cached logical size. It runs before and after event pumping, even
when a menu is open, waits through UIKit transitions, and logs any repaired size.
Pad artwork refuses to stretch a layout whose dimensions disagree with its host.

## Corrected defects and usability changes

| Area | Correction |
| --- | --- |
| Layout publication | Build the full layout before publishing it or updating native hit areas. Remove the game thread's fallback layout/ UIKit calls. |
| Input handoff | Publish buttons and four stick axes in one atomic 64-bit snapshot. |
| Cache invalidation | Include safe-area changes; update opacity independently without losing a held button. Cache every button's geometry and state. |
| Hidden controls | Visibility changes, menus, focus loss and background entry release held and pending screen input. |
| Sticks | A stationary hold now creates a stick without needing a motion event. Keep the last observed point during a pending hold; preserve a clamped right-stick base on subsequent motion. |
| Eye/Menu | Visible above SDL; a labelled Menu handle and at least 44-point-high hit areas. Reserve space between Start and Select on smaller phones. |
| Menu actions | Each control owns its action holder. Rebuilding a panel no longer destroys the bar-tab targets. Keep the executing block alive while it rebuilds its own row. |
| Menu bounds | Safe-area-aware position, scrollable contents, 44-point action rows, selected tabs and explicit Done. Preserve UIScrollView's internal views. |
| Outside tap | Shield sits behind the bar and panel, closes the menu and consumes the tap. Existing SDL finger events cannot leak through the open menu. |
| Settings reuse | Each cell owns its model and control. Reuse removes previous controls; edited model values survive scrolling. |
| Settings layout | Compute frames after the cell is sized. Put segments/sliders below their labels and explanations. Reflow for safe-area/size changes. Long language lists use a native choice sheet. |
| Sliders | Commit on inside release, outside release or cancellation. Avoid saving to disk on every movement. Volume displays percent rather than an incorrect multiplier. |
| FPS/settings entry | Update visible FPS cells directly, without a dangling global label. Controller/keyboard settings entry and close stay synchronized with UIKit; special game cards retain their own flow. |
| Old overlay state | The invisible ImGui bar cannot hide the native pad. Save/message/text dialogs also hide native controls and receive input. |
| Pause/intro | Pause card can be tapped to resume. Intro text describes Menu and dynamic sticks, fits the safe area and dismisses on first game touch, Menu or eye use. |
| Rendering cost | Cache small images for individual buttons/sticks. A moving stick no longer allocates and rasterizes a full Retina-screen image per refresh. Throttle the stats label to four updates/second. |
| Quit/lifetime | Restore quit confirmation, retain the cached highlight image correctly, and remove discarded action arrays and duplicate full-screen artwork carriers. |

## Validation

- The production pad section from `window.c` is compiled verbatim by
  `dev/tests/touchpad_test.py`, with deterministic SDL, settings and clock adapters.
- AddressSanitizer and UndefinedBehaviorSanitizer: pass.
- 96 combinations of phone dimensions, scale, handedness and notch side: all
  controls remain in bounds and the eye/Menu slots remain clear.
- Multi-button release, opacity changes while held, safe-area invalidation,
  visibility toggle, handedness change, cancelled touch, stationary hold, quick
  tap, disabled second stick, clamped base, small motion before a hold and menu
  interruption: pass.
- 200,000 input snapshot publications with a concurrent reader: pass.
- Clang static analysis of the complete native chrome and window implementation:
  no analyzer findings after correcting the reported null-path guard and dead
  initializations. The command emits an unused linker-option notice during analysis.
- Cross-compiled and linked the actual arm64 iOS runtime successfully.
- IPA integrity, arm64 executable, bundle metadata and served download are checked
  during packaging.

Host logs are `C:/ProgramData/t3/nativ-test34-build.log` and
`C:/ProgramData/t3/nativ-test34-analysis.log`.

## Device verification limit

This Windows host has no iOS simulator or attached runnable iPhone session.
UIKit appearance, app-switcher recovery, native sheets and real multitouch cannot
be honestly marked device-tested here. The first device run should cover the eye
off/on, each Menu tab, scrolling settings and returning to edited rows, both
landscape orientations, several app-switcher returns, and a game save/text dialog.
The IPA is a runtime update that uses the existing game-data setup, like test33.
