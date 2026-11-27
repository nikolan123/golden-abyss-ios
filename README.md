# Uncharted: Golden Abyss for iOS

Uncharted: Golden Abyss, statically recompiled from its ARM code into a native iOS app. A fork of
[Project Nativ](https://github.com/TheLostPantheon/nativ) narrowed to this game on this platform: the engine and
the Golden Abyss pack are upstream's, the iOS work is this fork's.

## What it adds over the Vita

- **JIT-less.** The game is translated to C ahead of time and compiled to arm64, so there is no interpreter and
  no JIT: it runs on a stock device, without a jailbreak or a special entitlement.
- **Native UI.** The menu bar, settings, dialogs and toasts are UIKit, not an imitation drawn over the game.
- **Higher resolution** than the Vita's 960×544.
- **MetalFX upscaling** (iOS 16 and later): the game renders below the screen's resolution and Apple's spatial
  upscaler brings it up, which buys frame time on a phone.
- **Touch controls**, including two-thumb shooting, and direct touch look: the camera turns as far as the finger
  moves.
- **Tilt**, from the phone's own gyro, for the balance sections.

## Status

Playable on device; a work in progress. Tested on an iPhone 15 Pro Max.

- US 1.00 (`PCSA00029`) only. The 1.03 update is not supported and not needed.
- 60 fps is experimental: parts of the game run on fixed 1/30 s steps and speed up. Use 30.
- One game per app: no launcher, no library.
- Saves and settings live in the app's `Documents`, visible in Files.

## What you need

- **Your own copy of the game** (`ux0:app/PCSA00029`, or a PKG with its licence) and **Sony's firmware update
  file**. Neither is in this repository.
- **Windows or macOS** with an iOS toolchain: clang targeting arm64 iOS with `ld64.lld`, the iPhoneOS SDK, and
  SDL3, zlib, SPIRV-Cross and FFmpeg built for iOS (the three `ATIV_IOS_*` variables below say where they are).
- **A way to install it**: Sideloadly or AltStore with a free Apple ID (re-signed every seven days), a paid
  developer account (a year), or TrollStore on a device that supports it.

## Building

Once those are in place:

```powershell
# firmware and the game, decrypted and recompiled (once)
.\.venv\Scripts\python.exe pipeline\vitarecomp.py firmware PSP2UPDAT.PUP
.\.venv\Scripts\python.exe pipeline\vitarecomp.py add <copy of ux0:app\PCSA00029>

# the app: arm64, iOS 15 minimum
$env:TARGET = 'ios'
$env:ATIV_IOS_TOOLCHAIN = 'D:\work\ios\toolchain'   # SDL3, zlib, SPIRV-Cross, FFmpeg built for iOS
$env:ATIV_IOS_SDK = '<iPhoneOS SDK>'
$env:ATIV_IOS_TC = '<clang toolchain bin, with ld64.lld>'
.\.venv\Scripts\python.exe pipeline\vitarecomp.py build PCSA00029

# the ipa
.\.venv\Scripts\python.exe runtime\platform\ios\pack-ios.py PCSA00029
```

That writes `dist/GoldenAbyss-unsigned.ipa`. `--smoke` packages the runtime alone, with no game data, to check
that a build boots before sitting through a full one.

## Licence

GNU GPL, version 2 or later: [LICENSE](LICENSE). [CONTRIBUTORS.md](CONTRIBUTORS.md) and
[THIRD_PARTY.md](THIRD_PARTY.md) carry the credits and the third-party licences this fork inherits.

No Sony or game code ships here, in either the repository or the ipa: your copy is decrypted and recompiled on
your own machine.

## AI disclosure

Nativ, and this fork with it, is written with AI assistance under its developer's direction, and tested on the
game.
