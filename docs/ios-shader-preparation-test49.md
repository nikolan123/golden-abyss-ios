# iOS test49: prepare shaders before play

The phone log showed that the shipped shader recipe file was rejected as a
different version. The header and every record had CRLF line endings from the
Windows checkout, while the runtime accepted only LF. It consequently loaded
zero shipped recipes and had to discover those shader/pipeline combinations
during play.

The recipe reader now normalizes CRLF before checking the version header,
verifying record hashes and loading pipeline references. The actual shipped
Uncharted file loads all 417 shader recipes and 413 pipeline recipes. Locally
recorded recipes use the same reader; version/hash checks and rejection of a
cut-short final record remain intact.

iOS defaults to **Before Play** preparation. The startup card begins while
shader programs are being indexed from the installed game files, stays active
through known shader/pipeline builds, and waits for the additional predicted
fragment variants. The first-launch controls hint is deferred until preparation
finishes, so it remains available on a fresh install.
The game resumes only after preparation completes or the player chooses Skip.

Skip works during indexing, known builds and the extra pass. It restores the
workers reserved for gameplay and the prediction pass's background limit.
Foreground preparation uses the available build workers without the prediction
pass's background limit. Warm objects continue to be released as work completes,
rather than keeping every level's shaders resident.

Performance settings has one Shader preparation choice: Background, Automatic
or Before Play. A saved choice applies on the next launch. Desktop defaults
remain Automatic; existing saved choices and the diagnostic environment override
still apply. Unknown totals use a spinner rather than a misleading 0-of-0 count.
Progress publication uses atomic counters/rate snapshots across the renderer
and UI threads.

The existing Metal library/pipeline archive remains in use. Preparation runs on
the phone's GPU/OS, and cache reuse makes later preparation cheaper. This is not
a promise that every future draw is covered: an unseen vertex layout, render
state or setting combination may still need compilation during play. The
prediction pass warms additional fragment variants but is not a complete list
of every possible pipeline.

## Verification and packages

The new sanitized production-code harness loads the actual shipped file and
checks LF, CRLF, mixed endings, merged duplicates, invalid versions/hashes and
truncated records. It exercises startup defaults/overrides, lazy worker creation,
zero recipe builds, both Skip transitions, extra-pass completion, worker limits,
headless and synchronous modes. The native-overlay suite checks preparation
priority over the first-launch hint. Both suites run in the shared test runner.

Two unsigned packages use the same final arm64 executable: a small upgrade for
the main phone, reusing the installed game data, and a full first-install package
for the iPhone 11 Pro. Full-package checks compare every app0 filename and size
with the source data, verify ZIP CRCs and runtime images, and compare its
executable with the upgrade and final build. No shader cache from another GPU is
bundled. Game data and cache files are not committed to Git.

Interactive device access is disabled here. Phone checks should confirm startup
preparation completes, Skip restores play, subsequent launches reuse the cache,
and new levels show fewer compilation hitches. The iPhone 11 Pro's cold/warm
preparation time and memory behavior still need measurement on that phone.
