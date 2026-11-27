# Building for iOS

This is the whole path from a copy of the game to an app on a phone: the toolchain once, the game once, then a
build and a package. It is the only platform this fork builds for.

Everything below is a cross build: an arm64 iOS binary made on Windows or macOS. The pipeline's Python and the
recompiler run on the build machine; only the result goes to the phone.

## 1. Python and the pipeline

Python 3.11 or newer, and this repository's requirements in a virtual environment at the top of the checkout:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

On macOS or Linux the same, with `.venv/bin/python`.

## 2. The iOS toolchain

Three environment variables tell `runtime/build.py` where things are. There is no setup script for iOS in this
repository (the desktop platforms have one each); the libraries are the same ones, built for a different target.

| Variable | What it points at |
|---|---|
| `ATIV_IOS_TC` | the `bin` directory of a clang that can target arm64 iOS, with `ld64.lld` beside it |
| `ATIV_IOS_SDK` | an `iPhoneOS*.sdk` from Apple |
| `ATIV_IOS_TOOLCHAIN` | a directory of static libraries for arm64 iOS: `SDL3/`, `zlib/`, `spirv-cross/`, and optionally `ffmpeg/` |

**On Windows** the compiler and SDK come from a Windows iOS toolchain package — the one used for this fork is a
community SDK, laid out as `toolchain\windows\iphone\bin` (`clang.exe`, `clang++.exe`, `ld64.lld.exe`) with
`sdks\iPhoneOS*.sdk` beside it. Set:

```powershell
$env:ATIV_IOS_TC     = 'D:\t3\community-sdk\toolchain\toolchain\windows\iphone\bin'
$env:ATIV_IOS_SDK    = 'D:\t3\community-sdk\sdk-root\sdks\iPhoneOS27.2.sdk'
$env:ATIV_IOS_TOOLCHAIN = 'D:\work\ios\toolchain'
```

**On macOS** the same variables point into Xcode, and `brew install lld` provides `ld64.lld`:

```bash
export ATIV_IOS_TC="$HOME/toolchains/llvm/bin"                 # clang, clang++, ld64.lld
export ATIV_IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
export ATIV_IOS_TOOLCHAIN="$HOME/toolchains/ativ-ios"
```

### The libraries in `ATIV_IOS_TOOLCHAIN`

Four static libraries, built once for `arm64-apple-ios15.0` with the same compiler. The layout `build.py` expects
is the name of each project as its own directory, with `include/` and `lib/` inside:

```
toolchain/
  SDL3/lib/libSDL3.a           SDL3 3.4.16, SDL_SHARED=OFF SDL_STATIC=ON
  zlib/lib/libz.a              zlib 1.3.1
  spirv-cross/lib/libspirv-cross-c.a   SPIRV-Cross (vulkan-sdk-1.4.363.0), static C API
  ffmpeg/lib/libavcodec.a libavutil.a  optional: the H.264, AAC and MP3 decoders
```

The CMake flags are the macOS ones in `runtime/platform/macos/setup-toolchain.sh` with the target changed to
iOS, i.e. `-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64
-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0` in place of `CMAKE_OSX_DEPLOYMENT_TARGET` alone.

FFmpeg is what plays the game's movies: without it the runtime builds and the game runs, but its cutscene videos
fail to start. Its iOS build is the macOS one with `--enable-cross-compile --target-os=darwin --arch=arm64
--sysroot="$ATIV_IOS_SDK"` and the same decoder list.

## 3. Firmware and the game

Sony's firmware update file, from Sony's own site — newer is fine, 3.74 is what they serve:

```powershell
.\.venv\Scripts\python.exe pipeline\vitarecomp.py firmware PSP2UPDAT.PUP
```

Then the game: a folder copied off a Vita (`ux0:app/PCSA00029`, via VitaShell's FTP or a USB copy), or a PKG
beside its licence file. `add` decrypts it, imports it, analyses it, recompiles it and builds it:

```powershell
.\.venv\Scripts\python.exe pipeline\vitarecomp.py add "D:\vita\ux0\app\PCSA00029" --no-build
```

`--no-build` skips the host build that `add` would otherwise make: the interesting build is the iOS one, next.
If the game's licence lives elsewhere the launcher's Licences page or `vitarecomp licenses add <file|folder>`
takes it; a PKG needs it, a decrypted folder does not.

`vitarecomp versions PCSA00029` says which release the copy is. The pack plays the US 1.00 build; the 1.03
update is added as a separate, unsupported version and the game runs without it.

## 4. The app

The cross build, and the step that takes the longest — Uncharted's C is tens of parts of ~10 MB each:

```powershell
$env:TARGET = 'ios'
$env:JOBS = '3'                 # compiles at once; a part file needs ~2 GB while it compiles
.\.venv\Scripts\python.exe pipeline\vitarecomp.py build PCSA00029
```

The result is `dump\decrypted\PCSA00029\recomp\game_host` — an arm64 iOS executable with the game's own images
beside it. `JOBS` matters on a small machine: the default is one compile per 2 GB of free memory.

## 5. The ipa

```powershell
.\.venv\Scripts\python.exe runtime\platform\ios\pack-ios.py PCSA00029
```

That writes `dist\GoldenAbyss-unsigned.ipa`: `Payload/GoldenAbyss.app` with the executable, `Info.plist`, the
icon set, the runtime images and the game's own files, zipped with the permissions iOS expects.

| Step | What it produces |
|---|---|
| `pack-ios.py PCSA00029` | the full ipa, game data included (a few GB) |
| `pack-ios.py PCSA00029 --smoke` | the runtime alone (~40 MB): boots, logs what it is missing, reuses an installed build's data |
| `pack-ios.py PCSA00029 --app-name X` | a different bundle name, and its own identifier, so a test build installs beside the real app |
| `pack-ios.py PCSA00029 --icon <png>` | a different app icon |

`ATIV_IPA_OUT` puts the ipa somewhere other than `dist\`.

### The app icon

The icon on the home screen is the game's own: packaging takes `app0/sce_sys/icon0.png` out of your copy and
renders it at every size iOS asks for, the way `pipeline/steam.py` takes the game's art for a Steam shortcut. It
never enters this repository, which is why nothing of the game has to.

For a build without a copy — a `--smoke` ipa, or a dump that has no `icon0.png` — the fallback is the drawn icon
in `runtime/platform/ios/AppIcon/`, made from `AppIcon.svg` by `runtime/platform/ios/icons.py`:

```powershell
.\.venv\Scripts\python.exe runtime\platform\ios\icons.py                      # the drawn icon, from the SVG
.\.venv\Scripts\python.exe runtime\platform\ios\icons.py --from icon0.png    # any square image
```

Both write `AppIcon/*.png`; those are committed, so packing needs no browser and no drawing tool at hand.

## 6. On the phone

The ipa is unsigned. Any of these gets it running:

- **Sideloadly or AltStore** with a free Apple ID. The app works for seven days at a time, then is signed again.
- **Xcode** with a paid team: sign the unpacked `Payload/GoldenAbyss.app` and run it to the device.
- **TrollStore**, on a device that supports it, installs the unsigned ipa unchanged.

On first launch the app sets up its `Documents` folder and starts the game.

### Settings on the device

The app keeps its working files under `Documents/Nativ/`, where the Files app can reach them (the app declares
`UIFileSharingEnabled`):

- `env.txt` — `NAME=VALUE` lines, read at startup like environment variables. It is the only way to pass a
  `RECOMP_*` switch to a phone, which has no shell.
- `settings.ini` and the game's saves, written by the game.

Logs go to the device's console (`idevicesyslog`, or Xcode's Devices window).

## Troubleshooting

| Symptom | Cause |
|---|---|
| `no iOS toolchain: set ATIV_IOS_TOOLCHAIN ...` | one of the three variables is unset or points nowhere |
| `ld64.lld: not found` | the clang in `ATIV_IOS_TC` has no linker beside it (macOS: `brew install lld`) |
| The app installs, then exits at launch | a build without its images: check that `data/entry.txt` is in the bundle, and read the device log |
| Movies do not play | FFmpeg was not in `ATIV_IOS_TOOLCHAIN` when the build ran |
| The app shows a blank icon | `AppIcon/` was missing at packaging time; `pack-ios.py` refuses to pack without it |

## What is in the tree, and what is not

This fork builds one game for one platform. The desktop launcher, the other games' packs and the online servers
are upstream's and stay in the tree untouched; this fork does not build or test them. The iOS-specific code is:

| Path | What it is |
|---|---|
| `runtime/platform/ios/` | packaging (`pack-ios.py`), the icon and its renderer |
| `runtime/platform/ios_shims.m` | the pieces the cross toolchain's compiler-rt lacks |
| `runtime/platform/ios_ui_chrome.m` | the UIKit chrome: menu bar, dialogs, toasts |
| `runtime/platform/ios_motion.m` | CoreMotion as the Vita's motion sensor |
| `runtime/gfx/gfx_metalfx.m` | MetalFX spatial upscaling |
| `runtime/ui/window.c` | the touch controls, touch look and gesture input |
| `packs/PCSA00029/hooks.c` | the game's own patches: cameras, 60 fps fixes, touch prompts |
