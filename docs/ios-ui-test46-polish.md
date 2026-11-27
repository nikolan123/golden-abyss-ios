# iOS presentation and interaction passes — test46

These changes refine the host UI's layout, hierarchy and interactions. The game
interface, rendering configuration, experimental 60 fps default and direct touch
look remain as in test45. This work is committed locally; it has not been pushed.

## Quick controls and materials

The gear opens a system UIMenu instead of the custom full-width strip and nested
panel. Frame rate, resolution and statistics use native checked options. Display
and control submenus share the existing settings actions; volume and other
sliders are available in settings. Quit uses the system destructive style.
Menu presentation cancels ongoing touch controls, suppresses game touch input
and delays opening settings/quit cards until menu dismissal completes.

Floating surfaces use UIGlassEffect and native Glass button configurations on
iOS 26+. Earlier systems use system materials and configured buttons. Reduced
Transparency provides an opaque semantic background; Reduced Motion shortens
custom transitions to zero. Eye/gear controls, cards and feedback share a system
blue tint, continuous corners and readable semantic colors.

## Save flow and dialogs

Save slots appear as individual inset cards with a title, icon, concise metadata
and selection mark. Tapping selects a card; a separate Save, Load or Delete action
confirms that selection. The game's focused row remains selected initially.
Changing selection preserves the scroll position. Empty lists cannot confirm.
Existing save-answer values and revision checks are preserved.

Dialogs size to their content and the safe area rather than using a fixed box.
They retain a stable surface while the game advances between save steps and
fade when closed. Native configured buttons distinguish primary and destructive
actions. Three-button/large-text layouts can scroll their action area. Compact
keyboard layouts put Cancel and Done in the navigation bar, leaving space for
the editor. Text validation and marked composition also govern that Done item.
Navigation callbacks capture the dialog revision; retired controls cannot answer
a later dialog. Game-owned dialogs continue polling without pausing the game.

## Settings and choices

Settings opens a category list with familiar Back and Done navigation. Detail
pages use actual grouped table sections, headers and explanatory footers instead
of decorative header cells and five page tabs. Large option lists are selectable
rows that open a system navigation sheet with checked choices and native dismissal.
They no longer use an alert action sheet. Sheet corner styling remains system
managed. Choice callbacks verify their originating page and retained row.

Dynamic Type updates visible tables; control callbacks reject retired models or
controls after a page refresh. Escape closes a choice sheet first, then navigates
back to Settings before closing the settings card.

## Verification limits

The iOS build, full chrome Clang analysis and existing sanitized native-overlay
and touch/camera suites are used to check this work. The native chrome analysis
includes all three UI implementation includes. Existing dialog API checks cover
message/IME semantics. Package checks cover arm64, plist, ZIP integrity, source
freshness, compiled UI-object freshness and exact executable equality.

Interactive device access is disabled in this environment, and there is no local
iOS simulator. These are code/state checks, not a visual approval of UIKit or
Liquid Glass on a phone. Device review should cover the quick menu, selection
and confirmation of a save, transitions between save steps, keyboard editing,
large text, setting choices and app-switcher returns.

The final build, Clang analysis and sanitizer suites passed; the message/IME API
suite passed 184 checks. The compiled UI object is newer than all four UI source
files, and the IPA executable matches that build exactly. ZIP/plist/arm64 checks
and the HTTP 200 response with matching length passed.

Artifact: `NativUncharted-test46-unsigned.ipa`, 42,310,506 bytes.
SHA-256: `7881308072558964076be268c8d7dc9cc8dc190378da2882819c165d69799e30`.
Records are under `C:/ProgramData/t3/nativ-test46-*`.
