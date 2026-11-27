# iOS test48: one settings menu

The gear now opens the existing Settings category list directly. The separate
Quick Controls navigation controller and its duplicated setting actions have
been removed, including their modal state and input-routing checks.

Display, Performance, Game, Controls and Help remain in Settings. Metal
HUD is under Performance, resolution is under Display, and frame rate is under
Game. Resume Game and Quit Game are on the Settings home list. Opening
Settings pauses the game; Done or Resume Game closes it and resumes play. Quit
uses the existing system confirmation alert and preserves its revision checks.

The old ImGui top bar and its top-edge touch trigger remain disabled while the
native iOS interface is active. There is no native top bar or pull gesture: the
gear below the eye is the visible entry to Settings. Keyboard/controller entry
uses the same Settings surface.

Checks cover the iOS build, native Clang analysis, native-overlay state and
lifecycle regressions, compiled UI freshness and IPA integrity. Package checks
also reject the removed Quick Controls controller if it is still linked.
Interactive device access remains disabled, so phone verification is still
needed for gear entry, category navigation, Done/Resume and Quit confirmation.

Changes are committed locally and have not been pushed to GitHub.

The iOS build, Clang analysis, native-overlay regressions and IPA/download
checks passed. Artifact: `NativUncharted-test48-unsigned.ipa`, 42,305,469 bytes;
SHA-256 `33aecff7811f8579bc4d34eb7ecf49a3753edf846f7863c14ee08c927e4dd952`.
Records are under `C:/ProgramData/t3/nativ-test48-*`.
