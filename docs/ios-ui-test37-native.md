# iOS host UI migration — test37

The standard iOS path now draws the host UI entirely with UIKit and Core
Animation. This completes the native settings/chrome work from test34–35.
The game's own interface still comes from the game.

The pre-change checkpoint is `ca52ae8`. HUD/gear changes were committed
separately as `1780cbb`; this migration follows that commit.

## User-visible changes

- Metal HUD is available in quick-menu Display and settings Performance.
  It is opt-in and requires an app restart. A saved preference is applied
  before GPU creation; an explicit `RECOMP_METAL_HUD` override takes priority.
- The quick-menu button is a gear beneath the eye, with a 44-point touch
  target and no Menu text. The performance readout starts below it.
- Save slots use a native scrolling table; save questions, wait cards,
  messages and progress bars use native views and actual game button labels.
- Text entry uses native single-line/multiline controls, the system keyboard,
  secure entry and keyboard types. Limits count UTF-16 units, with composition
  allowed and invalid final text prevented from submitting. Arrow keys edit
  text; multiline Return inserts a newline. Drafts survive settings/quit-card
  interruption.
- Shader preparation, Skip, background progress, controller-layout selection
  with Remember, and quit confirmation use native cards. D-pad, analog-stick
  and keyboard navigation work on these cards. Circle-enter games retain their
  confirm/cancel mapping. Controller West or keyboard R toggles Remember.
- Touch/cursor/rear-panel marks use Core Animation shape layers.

## State, lifetime and compatibility review

UIKit installation remains after SDL's GPU claim, before overlay startup.
Normal native startup skips ImGui fonts and platform/GPU backend setup;
normal rendering and event paths skip ImGui frames. A minimal context remains
for existing shared-state guards, and its shutdown avoids uninitialized
backends. No ini file is written.

Host cards use revision-checked replies. Save/message/IME snapshots are copied
under their view locks, including borrowed text and save rows. The locks are
released before any answer API is called. Save Yes/No maps to the save API's
1/2 values; cancellation remains -1. Cancelling a layout choice selects Standard
without storing Remember. Shader completion cannot dismiss a quit/layout card.

Game-owned dialogs keep the game running so it can poll their results; input
remains exclusive to the dialog. Automatic shader/layout cards wait until those
dialogs finish. Native editing also defers viewport reconciliation. All UIKit
mutation stays on the main thread.

Desktop/headless rendering retains the legacy ImGui implementation.
`RECOMP_NATIVE_CHROME=0` opts iOS into that path. The older
`RECOMP_NATIVE_PAD=0` diagnostic now selects the complete legacy UI as well,
preventing an invisible pad with live input areas.

## Verification

- Final arm64 iOS build passed. Clang analysis of the full chrome (including
  the new native dialog implementation) and window input code passed with
  only the existing unused linker-option notices.
- `dev/tests/native_overlay_test.py` compiles production state, reply, layout,
  frame and lifecycle functions under AddressSanitizer/UndefinedBehaviorSanitizer.
  It covers stale replies, preference persistence, dialog priority, shader
  skip/completion, quit interruption, zero native ImGui rendering/backend
  initialization, shutdown and legacy/failed initialization.
- The sanitized touch-input suite passed 96 layouts and 200,000 concurrent
  input publications, plus hold/release, cancellation and focus suppression.
- The sanitized viewport suite passed healthy/portrait/logical/drawable
  scenarios, text/transition deferral and 2x/3x screen scales.
- The existing system-dialog suite passed 184 checks, including API states,
  stale answers, UTF-16 conversion and text limits. This suite does not test
  UIKit drawing.
- IPA ZIP integrity, arm64 Mach-O, plist, executable permissions, source
  freshness and exact packaged-executable equality passed. HTTP returned 200
  and the matching Content-Length.

Artifact: `D:/work/dist/NativUncharted-test37-unsigned.ipa`, 42,302,309 bytes.
SHA-256: `3922b0fad36b6b9b133b9fcbaef0a6045de1cc4a6904610251c01e5f6d556af6`.
It is the runtime-only package, using the existing game-data setup.
Build/analysis/package logs and validation JSON are in
`C:/ProgramData/t3/nativ-test37-*`.

No physical iPhone or iOS simulator was available. These checks establish
build and host-state correctness, not that every UIKit layout or interaction
has been verified on a phone. Device checks still include the eye/gear, save
selection, keyboard sizing/composition, modal interruption, app switching and
the opt-in Metal HUD after restart.

Direct finger-drag camera control is feasible using the existing Uncharted
direct-camera hooks. It is not included in this UI migration; it needs explicit
gesture ownership so camera swipes do not take over the game's touch puzzles.
